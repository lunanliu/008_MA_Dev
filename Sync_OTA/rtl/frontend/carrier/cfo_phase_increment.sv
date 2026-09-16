`timescale 1ns/1ps

module cfo_phase_increment #(
  parameter logic signed [39:0] SCALE_CONSTANT_N35 = 40'sd295147905179,
  parameter int signed MAX_ABS_CFO_HZ = 250000
) (
  input  logic clk,
  input  logic rst_n,

  input  logic cfo_valid,
  output logic cfo_ready,
  input  logic signed [31:0] cfo_hz,

  output logic mul_req_valid,
  output logic signed [18:0] mul_req_a,
  output logic signed [39:0] mul_req_b,
  input  logic mul_rsp_valid,
  input  logic signed [58:0] mul_rsp_product,

  output logic phase_code_valid,
  input  logic phase_code_ready,
  output logic [31:0] phase_increment_code,
  output logic conversion_error
);
  typedef enum logic [1:0] {
    ST_WAIT_INPUT,
    ST_ISSUE_PRODUCT,
    ST_WAIT_PRODUCT,
    ST_HOLD_OUTPUT
  } state_t;

  state_t state;
  logic signed [18:0] held_cfo;
  logic held_range_error;

  function automatic [32:0] rne_shift35_to_signed32(
      input logic signed [58:0] value);
    logic sign_value;
    logic signed [59:0] extended_value;
    logic [59:0] magnitude;
    logic [24:0] quotient;
    logic [34:0] remainder;
    logic increment;
    logic [31:0] rounded_magnitude;
    logic overflow;
    logic signed [31:0] result;
    begin
      sign_value = value[58];
      extended_value = {value[58],value};
      magnitude = sign_value ? $unsigned(-extended_value) :
          $unsigned(extended_value);
      quotient = magnitude >> 35;
      remainder = magnitude[34:0];
      increment = (remainder > 35'h400000000) ||
          ((remainder == 35'h400000000) && quotient[0]);
      rounded_magnitude = {7'b0,quotient} + increment;
      overflow = (!sign_value &&
          {1'b0,rounded_magnitude} > 33'd2147483647) ||
          (sign_value &&
          {1'b0,rounded_magnitude} > 33'd2147483648);
      if (overflow)
        result = sign_value ? 32'sh8000_0000 : 32'sh7fff_ffff;
      else if (sign_value)
        result = -$signed(rounded_magnitude);
      else
        result = $signed(rounded_magnitude);
      return {overflow,result};
    end
  endfunction

  logic [32:0] converted;
  assign converted = rne_shift35_to_signed32(mul_rsp_product);
  assign cfo_ready = state == ST_WAIT_INPUT;
  assign mul_req_valid = state == ST_ISSUE_PRODUCT;
  assign mul_req_a = held_cfo;
  assign mul_req_b = SCALE_CONSTANT_N35;
  assign phase_code_valid = state == ST_HOLD_OUTPUT;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_WAIT_INPUT;
      held_cfo <= '0;
      held_range_error <= 1'b0;
      phase_increment_code <= '0;
      conversion_error <= 1'b0;
    end else begin
      unique case (state)
        ST_WAIT_INPUT: begin
          if (cfo_valid && cfo_ready) begin
            held_range_error <= cfo_hz < -MAX_ABS_CFO_HZ ||
                cfo_hz > MAX_ABS_CFO_HZ;
            held_cfo <= cfo_hz[18:0];
            state <= ST_ISSUE_PRODUCT;
          end
        end
        ST_ISSUE_PRODUCT: state <= ST_WAIT_PRODUCT;
        ST_WAIT_PRODUCT: begin
          if (mul_rsp_valid) begin
            phase_increment_code <= converted[31:0];
            conversion_error <= held_range_error || converted[32];
            state <= ST_HOLD_OUTPUT;
          end
        end
        ST_HOLD_OUTPUT: begin
          if (phase_code_valid && phase_code_ready) begin
            state <= ST_WAIT_INPUT;
            conversion_error <= 1'b0;
          end
        end
        default: begin
          state <= ST_WAIT_INPUT;
          conversion_error <= 1'b1;
        end
      endcase
    end
  end
endmodule
