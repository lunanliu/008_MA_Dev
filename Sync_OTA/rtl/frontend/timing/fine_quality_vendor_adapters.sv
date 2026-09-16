`timescale 1ns/1ps

// Thin control wrappers around the production Vivado-2021.1 quality IP.
// All arithmetic remains inside official AMD/Xilinx IP instances.

module fine_quality_denominator_vendor_adapter (
  input  logic clk,
  input  logic rst_n,

  input  logic req_valid,
  output logic req_ready,
  input  logic [45:0] req_segment_energy,
  input  logic [35:0] req_reference_energy,

  output logic rsp_valid,
  input  logic rsp_ready,
  output logic [81:0] rsp_product,
  output logic protocol_error_sticky
);
  localparam int unsigned LATENCY = 6;

  logic [LATENCY-1:0] valid_pipe;
  logic [81:0] native_product;
  logic launch;

  assign req_ready = !rsp_valid && !(|valid_pipe);
  assign launch = req_valid && req_ready;

  t05_mult_quality_u46x36_full82 u_quality_denominator_mult (
    .CLK(clk),
    .A(req_segment_energy),
    .B(req_reference_energy),
    .P(native_product)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_pipe <= '0;
      rsp_valid <= 1'b0;
      rsp_product <= '0;
      protocol_error_sticky <= 1'b0;
    end else begin
      valid_pipe[0] <= launch;
      for (int stage=1;stage<LATENCY;stage++)
        valid_pipe[stage] <= valid_pipe[stage-1];

      if (rsp_valid && rsp_ready)
        rsp_valid <= 1'b0;
      if (valid_pipe[LATENCY-1]) begin
        if (rsp_valid && !rsp_ready)
          protocol_error_sticky <= 1'b1;
        else begin
          rsp_product <= native_product;
          rsp_valid <= 1'b1;
        end
      end
    end
  end
endmodule

module fine_quality_divider_vendor_adapter (
  input  logic clk,
  input  logic rst_n,

  input  logic req_valid,
  output logic req_ready,
  input  logic signed [63:0] req_dividend,
  input  logic signed [63:0] req_divisor,

  output logic rsp_valid,
  input  logic rsp_ready,
  output logic signed [79:0] rsp_quotient_q15,
  output logic protocol_error_sticky
);
  logic request_active;
  logic signed [63:0] held_dividend;
  logic signed [63:0] held_divisor;
  logic dividend_sent;
  logic divisor_sent;

  logic dividend_axis_valid;
  logic dividend_axis_ready;
  logic divisor_axis_valid;
  logic divisor_axis_ready;
  logic dividend_fire;
  logic divisor_fire;
  logic native_output_valid;
  logic [79:0] native_output_data;

  assign req_ready = !request_active && !rsp_valid;
  assign dividend_axis_valid = request_active && !dividend_sent;
  assign divisor_axis_valid = request_active && !divisor_sent;
  assign dividend_fire = dividend_axis_valid && dividend_axis_ready;
  assign divisor_fire = divisor_axis_valid && divisor_axis_ready;

  t05_div_quality_s64_s64_f15 u_quality_divider (
    .aclk(clk),
    .aresetn(rst_n),
    .s_axis_divisor_tvalid(divisor_axis_valid),
    .s_axis_divisor_tready(divisor_axis_ready),
    .s_axis_divisor_tdata(held_divisor),
    .s_axis_dividend_tvalid(dividend_axis_valid),
    .s_axis_dividend_tready(dividend_axis_ready),
    .s_axis_dividend_tdata(held_dividend),
    .m_axis_dout_tvalid(native_output_valid),
    .m_axis_dout_tdata(native_output_data)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      request_active <= 1'b0;
      held_dividend <= '0;
      held_divisor <= '0;
      dividend_sent <= 1'b0;
      divisor_sent <= 1'b0;
      rsp_valid <= 1'b0;
      rsp_quotient_q15 <= '0;
      protocol_error_sticky <= 1'b0;
    end else begin
      if (req_valid && req_ready) begin
        request_active <= 1'b1;
        held_dividend <= req_dividend;
        held_divisor <= req_divisor;
        dividend_sent <= 1'b0;
        divisor_sent <= 1'b0;
      end

      if (dividend_fire)
        dividend_sent <= 1'b1;
      if (divisor_fire)
        divisor_sent <= 1'b1;
      if (request_active && (dividend_sent || dividend_fire) &&
          (divisor_sent || divisor_fire))
        request_active <= 1'b0;

      if (rsp_valid && rsp_ready)
        rsp_valid <= 1'b0;
      if (native_output_valid) begin
        if (rsp_valid && !rsp_ready)
          protocol_error_sticky <= 1'b1;
        else begin
          rsp_quotient_q15 <= $signed(native_output_data);
          rsp_valid <= 1'b1;
        end
      end

      if (native_output_valid && request_active)
        protocol_error_sticky <= 1'b1;
    end
  end
endmodule
