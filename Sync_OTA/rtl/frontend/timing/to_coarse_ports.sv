`timescale 1ns/1ps

// Port-only wrapper used by complete-top OOC and post-synthesis simulation.
// It contains no synchronization algorithm or state.  The packed vectors keep
// generated functional-netlist port names stable across Vivado flows.
module to_coarse_ports (
  input  logic clk,
  input  logic rst_n,

  input  logic data_valid,
  output logic data_ready,
  input  logic [127:0] data,
  input  logic [71:0] metadata_flat,

  output logic estimator_result_valid,
  input  logic estimator_result_ready,
  output logic [95:0] estimator_result_flat,

  output logic deadline_miss_sticky,
  output logic input_protocol_error_sticky,
  output logic result_service_error_sticky,
  output logic arithmetic_error_sticky,
  output logic arithmetic_ip_error_sticky,
  output logic [1:0] queued_result_pairs
);
  bistatic_stream_pkg::bistatic_stream_metadata_t metadata;
  bistatic_stream_pkg::bistatic_estimator_result_t estimator_result;

  // bistatic_stream_metadata_t is a 72-bit packed struct.  Its declaration
  // order freezes the flat layout as:
  // [71:40] frame_id, [39:8] beat_base_sample_index, [7:4] lane_valid,
  // [3] transaction_end, [2] physical_frame_end,
  // [1] nominal_region, [0] halo_or_guard.
  assign metadata = metadata_flat;

  // bistatic_estimator_result_t is a 96-bit packed struct:
  // [95:64] value, [63:48] quality, [47:32] status, [31:0] frame_id.
  assign estimator_result_flat = estimator_result;

  to_coarse_estimator u_coarse_coarse_sync (
    .clk(clk),
    .rst_n(rst_n),
    .data_valid(data_valid),
    .data_ready(data_ready),
    .data(data),
    .metadata(metadata),
    .estimator_result_valid(estimator_result_valid),
    .estimator_result_ready(estimator_result_ready),
    .estimator_result(estimator_result),
    .deadline_miss_sticky(deadline_miss_sticky),
    .input_protocol_error_sticky(input_protocol_error_sticky),
    .result_service_error_sticky(result_service_error_sticky),
    .arithmetic_error_sticky(arithmetic_error_sticky),
    .arithmetic_ip_error_sticky(arithmetic_ip_error_sticky),
    .queued_result_pairs(queued_result_pairs)
  );
endmodule
