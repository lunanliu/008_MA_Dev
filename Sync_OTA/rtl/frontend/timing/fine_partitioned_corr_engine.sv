`timescale 1ns/1ps

module fine_partitioned_corr_engine #(
  parameter string PS1_MEMORY_INIT_FILE = "fine_ps1_reference_16lane.mem",
  parameter int unsigned TAG_FIFO_DEPTH = 8
) (
  input  logic clk,
  input  logic rst_n,

  input  logic corrected_write_valid,
  output logic corrected_write_ready,
  input  logic [11:0] corrected_write_index,
  input  logic signed [17:0] corrected_write_i,
  input  logic signed [17:0] corrected_write_q,
  output logic corrected_buffer_full,
  input  logic buffer_release,

  input  logic correlation_start,
  input  logic signed [31:0] coarse_start,

  output logic result_valid,
  input  logic result_ready,
  output logic signed [31:0] peak_start,
  output logic [96:0] peak_metric,
  output logic signed [31:0] runner_start,
  output logic [96:0] runner_metric,
  output logic timing_valid,
  output logic ambiguity,
  output logic result_error,

  output logic busy,
  output logic [31:0] schedule_accept_count,
  output logic [31:0] candidate_metric_count,
  output logic [31:0] correlation_cycle_count,
  output logic protocol_error_sticky,
  output logic arithmetic_error_sticky
);
  localparam int unsigned LANES = 16;
  localparam int unsigned TAG_PTR_WIDTH = $clog2(TAG_FIFO_DEPTH);
  localparam int unsigned TAG_COUNT_WIDTH = $clog2(TAG_FIFO_DEPTH+1);

  logic corrected_read_req_valid;
  logic corrected_read_req_ready;
  logic [11:0] corrected_read_base;
  logic corrected_read_valid;
  logic corrected_read_ready;
  logic [15:0][17:0] corrected_read_i;
  logic [15:0][17:0] corrected_read_q;
  logic corrected_protocol_error;
  logic corrected_overwrite_error;
  logic corrected_read_error;

  logic reference_req_valid;
  logic reference_req_ready;
  logic [6:0] reference_req_group;
  logic reference_rsp_valid;
  logic reference_rsp_ready;
  logic [6:0] reference_rsp_group;
  logic [15:0][15:0] reference_i;
  logic [15:0][15:0] reference_q;
  logic reference_backpressure_error;

  logic scheduler_start_valid;
  logic scheduler_start_ready;
  logic scheduler_valid;
  logic scheduler_ready;
  logic [8:0] scheduler_candidate;
  logic [6:0] scheduler_group;
  logic [15:0][11:0] scheduler_sample_index;
  logic [15:0][10:0] scheduler_ref_index;
  logic scheduler_first;
  logic scheduler_last;
  logic scheduler_fire;

  logic signed [31:0] active_coarse_start;
  logic signed [31:0] scheduler_candidate_start;
  logic engine_active;
  logic start_accept;

  logic signed [31:0] tag_candidate_start [0:TAG_FIFO_DEPTH-1];
  logic [6:0] tag_group [0:TAG_FIFO_DEPTH-1];
  logic tag_first [0:TAG_FIFO_DEPTH-1];
  logic tag_last [0:TAG_FIFO_DEPTH-1];
  logic tag_candidate_last [0:TAG_FIFO_DEPTH-1];
  logic [TAG_PTR_WIDTH-1:0] tag_write_ptr;
  logic [TAG_PTR_WIDTH-1:0] tag_read_ptr;
  logic [TAG_COUNT_WIDTH-1:0] tag_count;
  logic tag_fifo_space;
  logic tag_push;
  logic tag_pop;
  logic join_fire;

  logic cmpy_output_valid;
  logic [LANES*35-1:0] cmpy_product_re;
  logic [LANES*35-1:0] cmpy_product_im;
  logic signed [31:0] cmpy_candidate_start;
  logic cmpy_first_group;
  logic cmpy_last_group;
  logic cmpy_candidate_last;
  logic cmpy_protocol_error;
  logic cmpy_conjugate_error;

  logic accumulator_ready;
  logic accumulator_result_valid;
  logic metric_corr_ready;
  logic signed [31:0] accumulator_candidate_start;
  logic signed [47:0] accumulator_corr_re;
  logic signed [47:0] accumulator_corr_im;
  logic accumulator_overflow;
  logic accumulator_candidate_last;

  logic square_req_valid;
  logic signed [47:0] square_req_operand;
  logic square_rsp_valid;
  logic [95:0] square_rsp;
  logic metric_valid;
  logic peak_candidate_ready;
  logic signed [31:0] metric_candidate_start;
  logic metric_candidate_last;
  logic [96:0] metric_value;
  logic metric_overflow;
  logic peak_error;

  initial begin
    if (TAG_FIFO_DEPTH < 4 || (TAG_FIFO_DEPTH & (TAG_FIFO_DEPTH-1)) != 0)
      $error("T05 correlation read-tag FIFO depth must be a power of two >=4");
  end

  always_comb begin
    busy = engine_active || result_valid;
    start_accept = correlation_start && corrected_buffer_full &&
        scheduler_start_ready && !busy;
    scheduler_start_valid = start_accept;
    scheduler_candidate_start = active_coarse_start-32'sd128+
        $signed({1'b0,scheduler_candidate});

    tag_fifo_space = tag_count < TAG_FIFO_DEPTH;
    scheduler_ready = corrected_read_req_ready && reference_req_ready &&
        tag_fifo_space;
    scheduler_fire = scheduler_valid && scheduler_ready;
    tag_push = scheduler_fire;

    corrected_read_req_valid = scheduler_fire;
    corrected_read_base = scheduler_sample_index[0];
    reference_req_valid = scheduler_fire;
    reference_req_group = scheduler_group;
    corrected_read_ready = 1'b1;
    reference_rsp_ready = 1'b1;

    join_fire = corrected_read_valid && reference_rsp_valid &&
        (tag_count != 0);
    tag_pop = join_fire;
    result_error = peak_error || protocol_error_sticky ||
        arithmetic_error_sticky;
  end

  fine_corrected_local_buffer u_corrected_buffer (
    .clk(clk),.rst_n(rst_n),
    .write_valid(corrected_write_valid),
    .write_ready(corrected_write_ready),
    .write_index(corrected_write_index),
    .write_i(corrected_write_i),.write_q(corrected_write_q),
    .buffer_full(corrected_buffer_full),.buffer_release(buffer_release),
    .read_req_valid(corrected_read_req_valid),
    .read_req_ready(corrected_read_req_ready),
    .read_base_index(corrected_read_base),
    .read_valid(corrected_read_valid),.read_ready(corrected_read_ready),
    .read_i(corrected_read_i),.read_q(corrected_read_q),
    .protocol_error_sticky(corrected_protocol_error),
    .overwrite_error_sticky(corrected_overwrite_error),
    .read_error_sticky(corrected_read_error)
  );

  fine_ps1_reference_rom #(
    .MEMORY_INIT_FILE(PS1_MEMORY_INIT_FILE),.READ_LATENCY(2)
  ) u_reference_rom (
    .clk(clk),.rst_n(rst_n),
    .req_valid(reference_req_valid),.req_ready(reference_req_ready),
    .req_group(reference_req_group),
    .rsp_valid(reference_rsp_valid),.rsp_ready(reference_rsp_ready),
    .rsp_group(reference_rsp_group),.rsp_i(reference_i),.rsp_q(reference_q),
    .backpressure_error_sticky(reference_backpressure_error)
  );

  fine_corr_scheduler u_scheduler (
    .clk(clk),.rst_n(rst_n),
    .start_valid(scheduler_start_valid),.start_ready(scheduler_start_ready),
    .schedule_valid(scheduler_valid),.schedule_ready(scheduler_ready),
    .candidate_index(scheduler_candidate),.group_index(scheduler_group),
    .sample_index(scheduler_sample_index),.ref_index(scheduler_ref_index),
    .first(scheduler_first),.last(scheduler_last)
  );

  fine_corr_cmpy_array u_cmpy_array (
    .clk(clk),.rst_n(rst_n),.input_valid(join_fire),
    .sample_i(corrected_read_i),.sample_q(corrected_read_q),
    .reference_i(reference_i),.reference_q(reference_q),
    .candidate_start(tag_candidate_start[tag_read_ptr]),
    .first_group(tag_first[tag_read_ptr]),
    .last_group(tag_last[tag_read_ptr]),
    .candidate_last(tag_candidate_last[tag_read_ptr]),
    .output_valid(cmpy_output_valid),
    .product_re(cmpy_product_re),.product_im(cmpy_product_im),
    .output_candidate_start(cmpy_candidate_start),
    .output_first_group(cmpy_first_group),
    .output_last_group(cmpy_last_group),
    .output_candidate_last(cmpy_candidate_last),
    .ip_protocol_error_sticky(cmpy_protocol_error),
    .reference_conjugate_error_sticky(cmpy_conjugate_error)
  );

  fine_corr_accumulator u_accumulator (
    .clk(clk),.rst_n(rst_n),
    .input_valid(cmpy_output_valid),.input_ready(accumulator_ready),
    .product_re(cmpy_product_re),.product_im(cmpy_product_im),
    .candidate_start(cmpy_candidate_start),
    .first_group(cmpy_first_group),.last_group(cmpy_last_group),
    .candidate_last(cmpy_candidate_last),
    .result_valid(accumulator_result_valid),.result_ready(metric_corr_ready),
    .result_candidate_start(accumulator_candidate_start),
    .corr_re(accumulator_corr_re),.corr_im(accumulator_corr_im),
    .overflow(accumulator_overflow),
    .result_candidate_last(accumulator_candidate_last)
  );

  fine_corr_metric_controller u_metric_controller (
    .clk(clk),.rst_n(rst_n),
    .corr_valid(accumulator_result_valid),.corr_ready(metric_corr_ready),
    .corr_re(accumulator_corr_re),.corr_im(accumulator_corr_im),
    .corr_candidate_start(accumulator_candidate_start),
    .corr_candidate_last(accumulator_candidate_last),
    .corr_overflow(accumulator_overflow),
    .mul_req_valid(square_req_valid),.mul_req_operand(square_req_operand),
    .mul_rsp_valid(square_rsp_valid),.mul_rsp_square(square_rsp),
    .metric_valid(metric_valid),.metric_ready(peak_candidate_ready),
    .metric_candidate_start(metric_candidate_start),
    .metric_candidate_last(metric_candidate_last),
    .metric(metric_value),.metric_overflow(metric_overflow)
  );

  fine_square48_vendor_adapter u_square_adapter (
    .clk(clk),.rst_n(rst_n),.req_valid(square_req_valid),
    .req_operand(square_req_operand),.rsp_valid(square_rsp_valid),
    .rsp_square(square_rsp)
  );

  fine_peak_selector u_peak_selector (
    .clk(clk),.rst_n(rst_n),
    .candidate_valid(metric_valid),.candidate_ready(peak_candidate_ready),
    .candidate_last(metric_candidate_last),
    .candidate_start(metric_candidate_start),
    .candidate_metric(metric_value),
    .result_valid(result_valid),.result_ready(result_ready),
    .peak_start(peak_start),.peak_metric(peak_metric),
    .runner_start(runner_start),.runner_metric(runner_metric),
    .timing_valid(timing_valid),.ambiguity(ambiguity),.error(peak_error)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      active_coarse_start <= '0;
      engine_active <= 1'b0;
      tag_write_ptr <= '0;
      tag_read_ptr <= '0;
      tag_count <= '0;
      schedule_accept_count <= '0;
      candidate_metric_count <= '0;
      correlation_cycle_count <= '0;
      protocol_error_sticky <= 1'b0;
      arithmetic_error_sticky <= 1'b0;
    end else begin
      if (start_accept) begin
        active_coarse_start <= coarse_start;
        engine_active <= 1'b1;
        schedule_accept_count <= '0;
        candidate_metric_count <= '0;
        correlation_cycle_count <= '0;
        if (tag_count != 0)
          protocol_error_sticky <= 1'b1;
      end else if (engine_active) begin
        correlation_cycle_count <= correlation_cycle_count+1'b1;
        if (result_valid)
          engine_active <= 1'b0;
      end

      if (correlation_start && !start_accept)
        protocol_error_sticky <= 1'b1;
      if (buffer_release && (busy || tag_count != 0))
        protocol_error_sticky <= 1'b1;

      if (tag_push) begin
        tag_candidate_start[tag_write_ptr] <= scheduler_candidate_start;
        tag_group[tag_write_ptr] <= scheduler_group;
        tag_first[tag_write_ptr] <= scheduler_first;
        tag_last[tag_write_ptr] <= scheduler_last;
        tag_candidate_last[tag_write_ptr] <=
            (scheduler_candidate == 9'd256) && scheduler_last;
        tag_write_ptr <= tag_write_ptr+1'b1;
        schedule_accept_count <= schedule_accept_count+1'b1;
      end
      if (tag_pop)
        tag_read_ptr <= tag_read_ptr+1'b1;
      case ({tag_push,tag_pop})
        2'b10: tag_count <= tag_count+1'b1;
        2'b01: tag_count <= tag_count-1'b1;
        default: tag_count <= tag_count;
      endcase

      if ((corrected_read_valid != reference_rsp_valid) ||
          ((corrected_read_valid || reference_rsp_valid) && tag_count == 0) ||
          (join_fire && reference_rsp_group != tag_group[tag_read_ptr]) ||
          (cmpy_output_valid && !accumulator_ready) ||
          corrected_protocol_error || corrected_overwrite_error ||
          corrected_read_error || reference_backpressure_error ||
          cmpy_protocol_error || cmpy_conjugate_error)
        protocol_error_sticky <= 1'b1;

      if (metric_valid && peak_candidate_ready) begin
        candidate_metric_count <= candidate_metric_count+1'b1;
        if (metric_overflow)
          arithmetic_error_sticky <= 1'b1;
      end
    end
  end
endmodule
