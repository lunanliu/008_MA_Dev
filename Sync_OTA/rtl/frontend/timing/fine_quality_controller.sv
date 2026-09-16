`timescale 1ns/1ps

module fine_quality_controller (
  input  logic clk,
  input  logic rst_n,

  input  logic input_valid,
  output logic input_ready,
  input  logic [96:0] peak_metric,
  input  logic [45:0] segment_energy,
  input  logic timing_valid,
  input  logic no_signal,
  input  logic ambiguity,
  input  logic accumulator_overflow,
  input  logic corrected_overflow,
  input  logic protocol_error,

  output logic denominator_mul_req_valid,
  input  logic denominator_mul_req_ready,
  output logic [45:0] denominator_mul_operand_a,
  output logic [35:0] denominator_mul_operand_b,
  input  logic denominator_mul_rsp_valid,
  output logic denominator_mul_rsp_ready,
  input  logic [81:0] denominator_mul_rsp_product,

  output logic divider_req_valid,
  input  logic divider_req_ready,
  output logic signed [63:0] divider_dividend,
  output logic signed [63:0] divider_divisor,
  input  logic divider_rsp_valid,
  output logic divider_rsp_ready,
  input  logic signed [79:0] divider_rsp_quotient_q15,

  output logic result_valid,
  input  logic result_ready,
  output logic [15:0] quality_code_q1_15,
  output logic quality_threshold_pass,
  output logic fine_valid,
  output logic result_error,
  output logic [2:0] error_code,
  output logic [5:0] normalization_shift
);
  localparam logic [35:0] REFERENCE_ENERGY = 36'd55559182922;
  localparam logic [15:0] QUALITY_SATURATION = 16'd32768;
  localparam logic [2:0] ERROR_NONE = 3'd0;
  localparam logic [2:0] ERROR_NO_SIGNAL = 3'd1;
  localparam logic [2:0] ERROR_AMBIGUITY = 3'd2;
  localparam logic [2:0] ERROR_QUALITY_LOW = 3'd3;
  localparam logic [2:0] ERROR_ACCUMULATOR_OVERFLOW = 3'd4;
  localparam logic [2:0] ERROR_CORRECTED_OVERFLOW = 3'd5;
  localparam logic [2:0] ERROR_PROTOCOL = 3'd6;
  localparam logic [2:0] ERROR_IP_ARITHMETIC = 3'd7;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_MUL_REQUEST,
    ST_MUL_RESPONSE,
    ST_DIV_REQUEST,
    ST_DIV_RESPONSE,
    ST_OUTPUT
  } state_t;

  state_t state;
  logic [96:0] held_peak_metric;
  logic [45:0] held_segment_energy;
  logic held_timing_valid;
  logic held_no_signal;
  logic held_ambiguity;
  logic held_accumulator_overflow;
  logic held_corrected_overflow;
  logic held_protocol_error;
  logic held_exact_threshold_pass;
  logic signed [63:0] held_dividend;
  logic signed [63:0] held_divisor;

  logic [6:0] denominator_bit_length;
  logic [5:0] common_shift_comb;
  logic [81:0] denominator_shifted;
  logic [96:0] peak_shifted;
  logic signed [63:0] normalized_denominator;
  logic signed [63:0] normalized_peak;
  logic no_signal_comb;
  logic normalization_domain_error;
  logic [93:0] threshold_denominator_extended;
  logic [93:0] threshold_rhs_shift_add;
  logic [111:0] threshold_lhs_exact;
  logic exact_threshold_pass_comb;
  logic [15:0] divider_quality_saturated;
  logic divider_response_error;

  function automatic logic [6:0] bit_length_82(input logic [81:0] value);
    logic [6:0] length;
    begin
      length = '0;
      for (int bit_index=0;bit_index<82;bit_index++) begin
        if (value[bit_index])
          length = bit_index+1;
      end
      bit_length_82 = length;
    end
  endfunction

  always_comb begin
    input_ready = (state == ST_IDLE);
    denominator_mul_req_valid = (state == ST_MUL_REQUEST);
    denominator_mul_operand_a = held_segment_energy;
    denominator_mul_operand_b = REFERENCE_ENERGY;
    denominator_mul_rsp_ready = (state == ST_MUL_RESPONSE);
    divider_req_valid = (state == ST_DIV_REQUEST);
    divider_dividend = held_dividend;
    divider_divisor = held_divisor;
    divider_rsp_ready = (state == ST_DIV_RESPONSE);

    denominator_bit_length = bit_length_82(denominator_mul_rsp_product);
    if (denominator_bit_length > 63)
      common_shift_comb = denominator_bit_length-63;
    else
      common_shift_comb = '0;
    denominator_shifted = denominator_mul_rsp_product >> common_shift_comb;
    peak_shifted = held_peak_metric >> common_shift_comb;
    normalized_denominator = $signed({1'b0,denominator_shifted[62:0]});
    normalized_peak = $signed({1'b0,peak_shifted[62:0]});
    no_signal_comb = held_no_signal ||
        (denominator_mul_rsp_product == 0) || (held_peak_metric == 0);
    normalization_domain_error =
        (held_peak_metric > {15'd0,denominator_mul_rsp_product}) ||
        (|denominator_shifted[81:63]) ||
        (|peak_shifted[96:63]);

    // Decide the acceptance threshold from the unnormalized integers.  The
    // fixed 3162 factor is 2048+1024+64+16+8+2, so no general multiplier is
    // inferred and divider rounding cannot move the threshold decision.
    threshold_denominator_extended =
        {{12{1'b0}},denominator_mul_rsp_product};
    threshold_rhs_shift_add =
        (threshold_denominator_extended << 11) +
        (threshold_denominator_extended << 10) +
        (threshold_denominator_extended << 6) +
        (threshold_denominator_extended << 4) +
        (threshold_denominator_extended << 3) +
        (threshold_denominator_extended << 1);
    threshold_lhs_exact = {held_peak_metric,15'b0};
    exact_threshold_pass_comb = threshold_lhs_exact >=
        {{18{1'b0}},threshold_rhs_shift_add};

    divider_response_error = divider_rsp_quotient_q15[79];
    if (!divider_response_error &&
        ($unsigned(divider_rsp_quotient_q15) >= QUALITY_SATURATION))
      divider_quality_saturated = QUALITY_SATURATION;
    else if (!divider_response_error)
      divider_quality_saturated = divider_rsp_quotient_q15[15:0];
    else
      divider_quality_saturated = '0;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      held_peak_metric <= '0;
      held_segment_energy <= '0;
      held_timing_valid <= 1'b0;
      held_no_signal <= 1'b0;
      held_ambiguity <= 1'b0;
      held_accumulator_overflow <= 1'b0;
      held_corrected_overflow <= 1'b0;
      held_protocol_error <= 1'b0;
      held_exact_threshold_pass <= 1'b0;
      held_dividend <= '0;
      held_divisor <= '0;
      result_valid <= 1'b0;
      quality_code_q1_15 <= '0;
      quality_threshold_pass <= 1'b0;
      fine_valid <= 1'b0;
      result_error <= 1'b0;
      error_code <= ERROR_NONE;
      normalization_shift <= '0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (input_valid && input_ready) begin
            held_peak_metric <= peak_metric;
            held_segment_energy <= segment_energy;
            held_timing_valid <= timing_valid;
            held_no_signal <= no_signal;
            held_ambiguity <= ambiguity;
            held_accumulator_overflow <= accumulator_overflow;
            held_corrected_overflow <= corrected_overflow;
            held_protocol_error <= protocol_error;
            held_exact_threshold_pass <= 1'b0;
            state <= ST_MUL_REQUEST;
          end
        end

        ST_MUL_REQUEST: begin
          if (denominator_mul_req_valid && denominator_mul_req_ready)
            state <= ST_MUL_RESPONSE;
        end

        ST_MUL_RESPONSE: begin
          if (denominator_mul_rsp_valid && denominator_mul_rsp_ready) begin
            normalization_shift <= common_shift_comb;
            if (no_signal_comb || normalization_domain_error) begin
              quality_code_q1_15 <= '0;
              quality_threshold_pass <= 1'b0;
              fine_valid <= 1'b0;
              result_error <= 1'b1;
              if (no_signal_comb)
                error_code <= ERROR_NO_SIGNAL;
              else if (held_ambiguity)
                error_code <= ERROR_AMBIGUITY;
              else if (held_accumulator_overflow)
                error_code <= ERROR_ACCUMULATOR_OVERFLOW;
              else if (held_corrected_overflow)
                error_code <= ERROR_CORRECTED_OVERFLOW;
              else if (held_protocol_error || !held_timing_valid)
                error_code <= ERROR_PROTOCOL;
              else
                error_code <= ERROR_IP_ARITHMETIC;
              result_valid <= 1'b1;
              state <= ST_OUTPUT;
            end else begin
              held_exact_threshold_pass <= exact_threshold_pass_comb;
              held_dividend <= normalized_peak;
              held_divisor <= normalized_denominator;
              state <= ST_DIV_REQUEST;
            end
          end
        end

        ST_DIV_REQUEST: begin
          if (divider_req_valid && divider_req_ready)
            state <= ST_DIV_RESPONSE;
        end

        ST_DIV_RESPONSE: begin
          if (divider_rsp_valid && divider_rsp_ready) begin
            quality_code_q1_15 <= divider_quality_saturated;
            if (divider_response_error) begin
              quality_threshold_pass <= 1'b0;
              fine_valid <= 1'b0;
              result_error <= 1'b1;
              error_code <= ERROR_IP_ARITHMETIC;
            end else begin
              quality_threshold_pass <= held_exact_threshold_pass;
              if (held_ambiguity) begin
                fine_valid <= 1'b0;
                result_error <= 1'b1;
                error_code <= ERROR_AMBIGUITY;
              end else if (!held_exact_threshold_pass) begin
                fine_valid <= 1'b0;
                result_error <= 1'b1;
                error_code <= ERROR_QUALITY_LOW;
              end else if (held_accumulator_overflow) begin
                fine_valid <= 1'b0;
                result_error <= 1'b1;
                error_code <= ERROR_ACCUMULATOR_OVERFLOW;
              end else if (held_corrected_overflow) begin
                fine_valid <= 1'b0;
                result_error <= 1'b1;
                error_code <= ERROR_CORRECTED_OVERFLOW;
              end else if (held_protocol_error || !held_timing_valid) begin
                fine_valid <= 1'b0;
                result_error <= 1'b1;
                error_code <= ERROR_PROTOCOL;
              end else begin
                fine_valid <= 1'b1;
                result_error <= 1'b0;
                error_code <= ERROR_NONE;
              end
            end
            result_valid <= 1'b1;
            state <= ST_OUTPUT;
          end
        end

        ST_OUTPUT: begin
          if (result_valid && result_ready) begin
            result_valid <= 1'b0;
            quality_code_q1_15 <= '0;
            quality_threshold_pass <= 1'b0;
            fine_valid <= 1'b0;
            result_error <= 1'b0;
            error_code <= ERROR_NONE;
            normalization_shift <= '0;
            state <= ST_IDLE;
          end
        end

        default: begin
          result_valid <= 1'b0;
          fine_valid <= 1'b0;
          result_error <= 1'b1;
          error_code <= ERROR_IP_ARITHMETIC;
          state <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
