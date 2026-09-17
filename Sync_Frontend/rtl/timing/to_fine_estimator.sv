`timescale 1ns/1ps

// Production T05 wrapper.  The algorithmic core exposes the quality product
// and quotient transactions so this layer can bind them to the exact
// Vivado-2021.1 AMD/Xilinx IP configurations measured by the T05 IP probe.
module to_fine_estimator #(
  parameter string PS1_MEMORY_INIT_FILE =
      "fine_ps1_reference_16lane.mem",
  parameter int unsigned DEADLINE_CYCLES = 65024
) (
  input  logic clk,
  input  logic rst_n,

  input  logic raw_tap_fire,
  input  logic [127:0] raw_tap_data,
  input  logic [31:0] raw_tap_frame_id,
  input  logic signed [31:0] raw_tap_base_sample_index,
  input  logic [3:0] raw_tap_lane_valid,

  input  logic coarse_result_valid,
  output logic coarse_result_ready,
  input  bistatic_stream_pkg::bistatic_estimator_result_t coarse_result,

  output logic estimator_result_valid,
  input  logic estimator_result_ready,
  output bistatic_stream_pkg::bistatic_estimator_result_t estimator_result,

  output logic busy,
  output logic [31:0] service_cycle_count,
  output logic deadline_miss_sticky,
  output logic protocol_error_sticky,
  output logic arithmetic_error_sticky,
  output logic quality_ip_protocol_error_sticky
);
  logic denominator_mul_req_valid;
  logic denominator_mul_req_ready;
  logic [45:0] denominator_mul_operand_a;
  logic [35:0] denominator_mul_operand_b;
  logic denominator_mul_rsp_valid;
  logic denominator_mul_rsp_ready;
  logic [81:0] denominator_mul_rsp_product;

  logic divider_req_valid;
  logic divider_req_ready;
  logic signed [63:0] divider_dividend;
  logic signed [63:0] divider_divisor;
  logic divider_rsp_valid;
  logic divider_rsp_ready;
  logic signed [79:0] divider_rsp_quotient_q15;

  logic denominator_protocol_error;
  logic divider_protocol_error;
  logic core_protocol_error;

  assign quality_ip_protocol_error_sticky =
      denominator_protocol_error || divider_protocol_error;
  assign protocol_error_sticky = core_protocol_error ||
      quality_ip_protocol_error_sticky;

  to_fine_core #(
    .PS1_MEMORY_INIT_FILE(PS1_MEMORY_INIT_FILE),
    .DEADLINE_CYCLES(DEADLINE_CYCLES)
  ) u_core (
    .clk(clk),
    .rst_n(rst_n),
    .raw_tap_fire(raw_tap_fire),
    .raw_tap_data(raw_tap_data),
    .raw_tap_frame_id(raw_tap_frame_id),
    .raw_tap_base_sample_index(raw_tap_base_sample_index),
    .raw_tap_lane_valid(raw_tap_lane_valid),
    .coarse_result_valid(coarse_result_valid),
    .coarse_result_ready(coarse_result_ready),
    .coarse_result(coarse_result),
    .denominator_mul_req_valid(denominator_mul_req_valid),
    .denominator_mul_req_ready(denominator_mul_req_ready),
    .denominator_mul_operand_a(denominator_mul_operand_a),
    .denominator_mul_operand_b(denominator_mul_operand_b),
    .denominator_mul_rsp_valid(denominator_mul_rsp_valid),
    .denominator_mul_rsp_ready(denominator_mul_rsp_ready),
    .denominator_mul_rsp_product(denominator_mul_rsp_product),
    .divider_req_valid(divider_req_valid),
    .divider_req_ready(divider_req_ready),
    .divider_dividend(divider_dividend),
    .divider_divisor(divider_divisor),
    .divider_rsp_valid(divider_rsp_valid),
    .divider_rsp_ready(divider_rsp_ready),
    .divider_rsp_quotient_q15(divider_rsp_quotient_q15),
    .quality_ip_protocol_error(quality_ip_protocol_error_sticky),
    .estimator_result_valid(estimator_result_valid),
    .estimator_result_ready(estimator_result_ready),
    .estimator_result(estimator_result),
    .busy(busy),
    .service_cycle_count(service_cycle_count),
    .deadline_miss_sticky(deadline_miss_sticky),
    .protocol_error_sticky(core_protocol_error),
    .arithmetic_error_sticky(arithmetic_error_sticky)
  );

  fine_quality_denominator_vendor_adapter
      u_quality_denominator_vendor_adapter (
    .clk(clk),
    .rst_n(rst_n),
    .req_valid(denominator_mul_req_valid),
    .req_ready(denominator_mul_req_ready),
    .req_segment_energy(denominator_mul_operand_a),
    .req_reference_energy(denominator_mul_operand_b),
    .rsp_valid(denominator_mul_rsp_valid),
    .rsp_ready(denominator_mul_rsp_ready),
    .rsp_product(denominator_mul_rsp_product),
    .protocol_error_sticky(denominator_protocol_error)
  );

  fine_quality_divider_vendor_adapter u_quality_divider_vendor_adapter (
    .clk(clk),
    .rst_n(rst_n),
    .req_valid(divider_req_valid),
    .req_ready(divider_req_ready),
    .req_dividend(divider_dividend),
    .req_divisor(divider_divisor),
    .rsp_valid(divider_rsp_valid),
    .rsp_ready(divider_rsp_ready),
    .rsp_quotient_q15(divider_rsp_quotient_q15),
    .protocol_error_sticky(divider_protocol_error)
  );
endmodule
