`timescale 1ns/1ps

module to_fine_core #(
  parameter string PS1_MEMORY_INIT_FILE =
      "fine_ps1_reference_16lane.mem",
  parameter int unsigned DEADLINE_CYCLES = 65024
) (
  input  logic clk,
  input  logic rst_n,

  // Non-backpressurable raw-frame observer tap.  Lane zero is earliest and
  // every lane is packed as {Q[15:0],I[15:0]}.
  input  logic raw_tap_fire,
  input  logic [127:0] raw_tap_data,
  input  logic [31:0] raw_tap_frame_id,
  input  logic signed [31:0] raw_tap_base_sample_index,
  input  logic [3:0] raw_tap_lane_valid,

  // T04 emits kind-one coarse-start then kind-two coarse-CFO records.
  input  logic coarse_result_valid,
  output logic coarse_result_ready,
  input  bistatic_stream_pkg::bistatic_estimator_result_t coarse_result,

  // The production quality multiplier and divider are integration-owned.
  // The core contains no inferred multiplication or division for this path.
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
  input  logic quality_ip_protocol_error,

  output logic estimator_result_valid,
  input  logic estimator_result_ready,
  output bistatic_stream_pkg::bistatic_estimator_result_t estimator_result,

  output logic busy,
  output logic [31:0] service_cycle_count,
  output logic deadline_miss_sticky,
  output logic protocol_error_sticky,
  output logic arithmetic_error_sticky
);
  import bistatic_stream_pkg::*;

  localparam logic [3:0] FINE_RESULT_KIND = 4'h3;
  localparam logic [2:0] ERROR_NONE = 3'd0;
  localparam logic [2:0] ERROR_NO_SIGNAL = 3'd1;
  localparam logic [2:0] ERROR_AMBIGUITY = 3'd2;
  localparam logic [2:0] ERROR_QUALITY_LOW = 3'd3;
  localparam logic [2:0] ERROR_ACCUMULATOR_OVERFLOW = 3'd4;
  localparam logic [2:0] ERROR_CORRECTED_OVERFLOW = 3'd5;
  localparam logic [2:0] ERROR_PROTOCOL = 3'd6;
  localparam logic [2:0] ERROR_IP_ARITHMETIC = 3'd7;

  typedef enum logic [3:0] {
    ST_WAIT_CONTEXT,
    ST_REQUEST_PHASE,
    ST_WAIT_PHASE,
    ST_CORRECT_WINDOW,
    ST_WAIT_LOCAL_BUFFERS,
    ST_WAIT_CORRELATION,
    ST_REQUEST_PEAK_ENERGY,
    ST_WAIT_PEAK_ENERGY,
    ST_WAIT_QUALITY,
    ST_HOLD_RESULT
  } state_t;

  state_t state;

  logic pair_job_valid;
  logic pair_job_ready;
  logic [31:0] pair_job_frame_id;
  logic signed [31:0] pair_job_coarse_start;
  logic signed [31:0] pair_job_coarse_cfo_hz;
  logic pair_job_handoff_valid;
  logic [15:0] pair_job_error_status;
  logic pair_protocol_error;

  logic capture_valid;
  logic capture_context_valid;
  logic [31:0] capture_frame_id;
  logic capture_release;
  logic capture_read_req_valid;
  logic capture_read_req_ready;
  logic [9:0] capture_read_req_addr;
  logic capture_read_rsp_valid;
  logic [127:0] capture_read_rsp_data;
  logic capture_protocol_error;
  logic capture_overwrite_error;
  logic capture_read_error;

  logic phase_cfo_valid;
  logic phase_cfo_ready;
  logic phase_mul_req_valid;
  logic signed [18:0] phase_mul_req_a;
  logic signed [39:0] phase_mul_req_b;
  logic phase_mul_rsp_valid;
  logic signed [58:0] phase_mul_rsp_product;
  logic phase_code_valid;
  logic phase_code_ready;
  logic [31:0] phase_increment_code;
  logic phase_conversion_error;

  logic reader_start_valid;
  logic reader_start_ready;
  logic reader_sample_valid;
  logic signed [15:0] reader_sample_i;
  logic signed [15:0] reader_sample_q;
  logic [11:0] reader_sample_local_index;
  logic signed [31:0] reader_sample_global_index;
  logic reader_sample_first;
  logic reader_sample_last;
  logic reader_busy;
  logic reader_done;
  logic reader_range_error;
  logic reader_protocol_error;

  logic corrector_start_valid;
  logic corrector_start_ready;
  logic corrector_start_fire;
  logic corrector_reader_start;
  logic corrected_valid;
  logic signed [17:0] corrected_i;
  logic signed [17:0] corrected_q;
  logic [11:0] corrected_local_index;
  logic corrected_first;
  logic corrected_last;
  logic corrector_busy;
  logic corrector_done;
  logic corrector_fifo_overflow;
  logic corrector_dds_underflow;
  logic corrector_ip_protocol_error;
  logic corrector_overflow;

  logic energy_build_start;
  logic energy_square_i_req_valid;
  logic signed [17:0] energy_square_i_operand;
  logic energy_square_i_rsp_valid;
  logic [35:0] energy_square_i_rsp_value;
  logic energy_square_q_req_valid;
  logic signed [17:0] energy_square_q_operand;
  logic energy_square_q_rsp_valid;
  logic [35:0] energy_square_q_rsp_value;
  logic energy_build_done;
  logic energy_read_req_valid;
  logic energy_read_req_ready;
  logic [8:0] energy_read_candidate_offset;
  logic energy_segment_valid;
  logic energy_segment_ready;
  logic [8:0] energy_segment_candidate_offset;
  logic [45:0] energy_segment_value;
  logic energy_protocol_error;
  logic energy_prefix_overflow;

  logic corrected_write_ready;
  logic partition_buffer_full;
  logic partition_buffer_release;
  logic partition_correlation_start;
  logic partition_result_valid;
  logic partition_result_ready;
  logic signed [31:0] partition_peak_start;
  logic [96:0] partition_peak_metric;
  logic signed [31:0] partition_runner_start;
  logic [96:0] partition_runner_metric;
  logic partition_timing_valid;
  logic partition_ambiguity;
  logic partition_result_error;
  logic partition_busy;
  logic [31:0] partition_schedule_count;
  logic [31:0] partition_candidate_count;
  logic [31:0] partition_cycle_count;
  logic partition_protocol_error;
  logic partition_arithmetic_error;

  logic quality_input_valid;
  logic quality_input_ready;
  logic quality_result_valid;
  logic quality_result_ready;
  logic [15:0] quality_code;
  logic quality_threshold_pass;
  logic quality_fine_valid;
  logic quality_result_error;
  logic [2:0] quality_error_code;
  logic [5:0] quality_normalization_shift;

  logic [31:0] active_frame_id;
  logic signed [31:0] active_coarse_start;
  logic signed [31:0] active_coarse_cfo_hz;
  logic active_pair_error;
  logic active_protocol_error;
  logic active_accumulator_overflow;
  logic active_corrected_overflow;
  logic active_ip_arithmetic_error;

  logic signed [31:0] held_peak_start;
  logic [96:0] held_peak_metric;
  logic held_peak_timing_valid;
  logic held_peak_ambiguity;
  logic held_peak_result_error;
  logic [8:0] held_peak_candidate_offset;
  logic held_peak_offset_valid;

  logic job_accept;
  logic job_identity_valid;
  logic job_range_valid;
  logic job_precheck_valid;
  logic pair_job_ambiguity;
  logic partition_result_fire;
  logic energy_request_fire;
  logic quality_input_fire;
  logic quality_completion_now;
  logic estimator_result_fire;
  logic service_active;
  logic deadline_fallback_now;
  logic signed [32:0] peak_offset_comb;
  logic peak_offset_valid;
  logic live_protocol_error;
  logic quality_protocol_input;
  logic quality_accumulator_overflow_input;
  logic quality_corrected_overflow_input;
  logic [2:0] effective_quality_error_code;
  logic effective_quality_fine_valid;
  logic subsystems_idle;

  initial begin
    if (DEADLINE_CYCLES != 65024)
      $error("T05 fine-timing deadline must remain 65024 cycles");
  end

  // Common-record integration mapping, approved for the T05 wrapper:
  // [15:12] kind=3, [11] valid, [10] ambiguity,
  // [9] no-signal or quality-low, [8] accumulator/corrected overflow,
  // [7] external-IP arithmetic, [6] deadline, [5] protocol/capture,
  // [4] T04 pair/handoff, [3]=0, [2:0] frozen T05 error code.
  function automatic logic [15:0] make_status(
      input logic fine_valid,
      input logic [2:0] error_code,
      input logic ambiguity_flag,
      input logic overflow_flag,
      input logic ip_arithmetic_flag,
      input logic protocol_flag,
      input logic pair_error,
      input logic deadline_error);
    logic [15:0] status_value;
    begin
      status_value = '0;
      status_value[15:12] = FINE_RESULT_KIND;
      status_value[11] = fine_valid && !deadline_error;
      status_value[10] = ambiguity_flag ||
          (error_code == ERROR_AMBIGUITY);
      status_value[9] = (error_code == ERROR_NO_SIGNAL) ||
          (error_code == ERROR_QUALITY_LOW);
      status_value[8] = overflow_flag ||
          (error_code == ERROR_ACCUMULATOR_OVERFLOW) ||
          (error_code == ERROR_CORRECTED_OVERFLOW);
      status_value[7] = ip_arithmetic_flag ||
          (error_code == ERROR_IP_ARITHMETIC);
      status_value[6] = deadline_error;
      status_value[5] = protocol_flag ||
          ((error_code == ERROR_PROTOCOL) && !deadline_error);
      status_value[4] = pair_error;
      status_value[2:0] = error_code;
      return status_value;
    end
  endfunction

  always_comb begin
    subsystems_idle = phase_cfo_ready && corrector_start_ready &&
        reader_start_ready && quality_input_ready && !partition_busy &&
        !partition_buffer_full && !protocol_error_sticky &&
        !arithmetic_error_sticky && !deadline_miss_sticky;
    pair_job_ready = (state == ST_WAIT_CONTEXT) && capture_valid &&
        !estimator_result_valid && subsystems_idle;
    job_accept = pair_job_valid && pair_job_ready;
    job_identity_valid = capture_frame_id == pair_job_frame_id;
    job_range_valid = pair_job_coarse_start >= -32'sd232 &&
        pair_job_coarse_start <= 32'sd232;
    pair_job_ambiguity = !pair_job_handoff_valid &&
        (pair_job_error_status == 16'h0400);
    job_precheck_valid = pair_job_handoff_valid &&
        !(|pair_job_error_status) && capture_context_valid &&
        job_identity_valid && job_range_valid;

    phase_cfo_valid = state == ST_REQUEST_PHASE;
    phase_code_ready = (state == ST_WAIT_PHASE) && corrector_start_ready;
    corrector_start_valid = (state == ST_WAIT_PHASE) && phase_code_valid;
    corrector_start_fire = corrector_start_valid && corrector_start_ready;
    energy_build_start = corrector_start_fire;

    reader_start_valid = corrector_reader_start;

    partition_correlation_start =
        (state == ST_WAIT_LOCAL_BUFFERS) && partition_buffer_full &&
        energy_build_done && !partition_busy;
    partition_result_ready = state == ST_WAIT_CORRELATION;
    partition_result_fire = partition_result_valid && partition_result_ready;

    peak_offset_comb =
        {partition_peak_start[31],partition_peak_start} -
        {active_coarse_start[31],active_coarse_start} + 33'sd128;
    peak_offset_valid = !peak_offset_comb[32] &&
        peak_offset_comb <= 33'd256;

    energy_read_req_valid = state == ST_REQUEST_PEAK_ENERGY;
    energy_read_candidate_offset = held_peak_candidate_offset;
    energy_request_fire = energy_read_req_valid && energy_read_req_ready;

    quality_input_valid = (state == ST_WAIT_PEAK_ENERGY) &&
        energy_segment_valid;
    energy_segment_ready = (state == ST_WAIT_PEAK_ENERGY) &&
        quality_input_ready;
    quality_input_fire = quality_input_valid && quality_input_ready;
    quality_result_ready = state == ST_WAIT_QUALITY;
    quality_completion_now = quality_result_valid && quality_result_ready;

    estimator_result_fire = estimator_result_valid &&
        estimator_result_ready;
    capture_release = estimator_result_fire;
    partition_buffer_release = estimator_result_fire &&
        partition_buffer_full;
    service_active = (state != ST_WAIT_CONTEXT) &&
        (state != ST_HOLD_RESULT);
    deadline_fallback_now = service_active && !quality_completion_now &&
        (service_cycle_count == DEADLINE_CYCLES-1);
    busy = (state != ST_WAIT_CONTEXT) || estimator_result_valid;

    live_protocol_error = pair_protocol_error ||
        capture_protocol_error || capture_overwrite_error ||
        capture_read_error || reader_range_error || reader_protocol_error ||
        corrector_fifo_overflow || corrector_dds_underflow ||
        corrector_ip_protocol_error || energy_protocol_error ||
        partition_protocol_error ||
        quality_ip_protocol_error ||
        (corrector_reader_start && !reader_start_ready) ||
        (corrected_valid && !corrected_write_ready) ||
        (energy_segment_valid &&
         energy_segment_candidate_offset != held_peak_candidate_offset);
    quality_protocol_input = active_protocol_error || live_protocol_error ||
        held_peak_result_error || !held_peak_offset_valid;
    quality_accumulator_overflow_input =
        active_accumulator_overflow || partition_arithmetic_error;
    quality_corrected_overflow_input =
        active_corrected_overflow || corrector_overflow;

    // The current quality-controller port set detects its own arithmetic
    // domain/divider errors but has no separate input for the earlier CFO-to-
    // PINC conversion.  Preserve no-signal/ambiguity and other already-frozen
    // hardware errors; an otherwise accepted or low-threshold result becomes
    // domain code seven because its corrected-energy domain is not trustworthy.
    effective_quality_error_code = quality_error_code;
    if (((quality_error_code == ERROR_NONE) ||
         (quality_error_code == ERROR_QUALITY_LOW)) &&
        active_ip_arithmetic_error)
      effective_quality_error_code = ERROR_IP_ARITHMETIC;
    effective_quality_fine_valid = quality_fine_valid &&
        !active_ip_arithmetic_error;
  end

  sync_coarse_pair_join u_coarse_pair_join (
    .clk(clk),.rst_n(rst_n),
    .coarse_result_valid(coarse_result_valid),
    .coarse_result_ready(coarse_result_ready),.coarse_result(coarse_result),
    .job_valid(pair_job_valid),.job_ready(pair_job_ready),
    .job_frame_id(pair_job_frame_id),
    .job_coarse_start(pair_job_coarse_start),
    .job_coarse_cfo_hz(pair_job_coarse_cfo_hz),
    .job_handoff_valid(pair_job_handoff_valid),
    .job_error_status(pair_job_error_status),
    .pair_protocol_error_sticky(pair_protocol_error)
  );

  fine_local_capture_buffer u_local_capture (
    .clk(clk),.rst_n(rst_n),
    .tap_fire(raw_tap_fire),.tap_data(raw_tap_data),
    .tap_frame_id(raw_tap_frame_id),
    .tap_base_sample_index(raw_tap_base_sample_index),
    .tap_lane_valid(raw_tap_lane_valid),
    .capture_valid(capture_valid),
    .capture_context_valid(capture_context_valid),
    .capture_frame_id(capture_frame_id),
    .capture_release(capture_release),
    .read_req_valid(capture_read_req_valid),
    .read_req_ready(capture_read_req_ready),
    .read_req_addr(capture_read_req_addr),
    .read_rsp_valid(capture_read_rsp_valid),
    .read_rsp_data(capture_read_rsp_data),
    .capture_protocol_error_sticky(capture_protocol_error),
    .capture_overwrite_error_sticky(capture_overwrite_error),
    .read_protocol_error_sticky(capture_read_error)
  );

  cfo_phase_increment u_phase_increment (
    .clk(clk),.rst_n(rst_n),
    .cfo_valid(phase_cfo_valid),.cfo_ready(phase_cfo_ready),
    .cfo_hz(active_coarse_cfo_hz),
    .mul_req_valid(phase_mul_req_valid),
    .mul_req_a(phase_mul_req_a),.mul_req_b(phase_mul_req_b),
    .mul_rsp_valid(phase_mul_rsp_valid),
    .mul_rsp_product(phase_mul_rsp_product),
    .phase_code_valid(phase_code_valid),
    .phase_code_ready(phase_code_ready),
    .phase_increment_code(phase_increment_code),
    .conversion_error(phase_conversion_error)
  );

  fine_cfo_scale_vendor_adapter u_cfo_scale (
    .clk(clk),.rst_n(rst_n),
    .req_valid(phase_mul_req_valid),
    .req_a(phase_mul_req_a),.req_b(phase_mul_req_b),
    .rsp_valid(phase_mul_rsp_valid),
    .rsp_product(phase_mul_rsp_product)
  );

  fine_local_window_reader u_local_reader (
    .clk(clk),.rst_n(rst_n),
    .start_valid(reader_start_valid),.start_ready(reader_start_ready),
    .coarse_start_sample(active_coarse_start),
    .read_req_valid(capture_read_req_valid),
    .read_req_ready(capture_read_req_ready),
    .read_req_addr(capture_read_req_addr),
    .read_rsp_valid(capture_read_rsp_valid),
    .read_rsp_data(capture_read_rsp_data),
    .sample_valid(reader_sample_valid),
    .sample_i(reader_sample_i),.sample_q(reader_sample_q),
    .sample_local_index(reader_sample_local_index),
    .sample_global_index(reader_sample_global_index),
    .sample_first(reader_sample_first),.sample_last(reader_sample_last),
    .busy(reader_busy),.done_pulse(reader_done),
    .range_error_sticky(reader_range_error),
    .read_protocol_error_sticky(reader_protocol_error)
  );

  cfo_preamble_rotator u_cfo_corrector (
    .clk(clk),.rst_n(rst_n),
    .start_valid(corrector_start_valid),
    .start_ready(corrector_start_ready),
    .phase_increment_code(phase_increment_code),
    .reader_start_pulse(corrector_reader_start),
    .raw_sample_valid(reader_sample_valid),
    .raw_sample_i(reader_sample_i),.raw_sample_q(reader_sample_q),
    .raw_local_index(reader_sample_local_index),
    .raw_first(reader_sample_first),.raw_last(reader_sample_last),
    .corrected_valid(corrected_valid),
    .corrected_i(corrected_i),.corrected_q(corrected_q),
    .corrected_local_index(corrected_local_index),
    .corrected_first(corrected_first),.corrected_last(corrected_last),
    .busy(corrector_busy),.done_pulse(corrector_done),
    .fifo_overflow_sticky(corrector_fifo_overflow),
    .dds_underflow_sticky(corrector_dds_underflow),
    .ip_protocol_error_sticky(corrector_ip_protocol_error),
    .corrected_overflow_sticky(corrector_overflow)
  );

  fine_square18_vendor_adapter u_energy_square_i (
    .clk(clk),.rst_n(rst_n),
    .req_valid(energy_square_i_req_valid),
    .req_operand(energy_square_i_operand),
    .rsp_valid(energy_square_i_rsp_valid),
    .rsp_square(energy_square_i_rsp_value)
  );

  fine_square18_vendor_adapter u_energy_square_q (
    .clk(clk),.rst_n(rst_n),
    .req_valid(energy_square_q_req_valid),
    .req_operand(energy_square_q_operand),
    .rsp_valid(energy_square_q_rsp_valid),
    .rsp_square(energy_square_q_rsp_value)
  );

  fine_energy_prefix_buffer u_energy_prefix (
    .clk(clk),.rst_n(rst_n),
    .build_start(energy_build_start),
    .sample_valid(corrected_valid),
    .sample_i(corrected_i),.sample_q(corrected_q),
    .sample_index(corrected_local_index),
    .sample_first(corrected_first),.sample_last(corrected_last),
    .square_i_req_valid(energy_square_i_req_valid),
    .square_i_req_operand(energy_square_i_operand),
    .square_i_rsp_valid(energy_square_i_rsp_valid),
    .square_i_rsp_value(energy_square_i_rsp_value),
    .square_q_req_valid(energy_square_q_req_valid),
    .square_q_req_operand(energy_square_q_operand),
    .square_q_rsp_valid(energy_square_q_rsp_valid),
    .square_q_rsp_value(energy_square_q_rsp_value),
    .build_done(energy_build_done),
    .read_req_valid(energy_read_req_valid),
    .read_req_ready(energy_read_req_ready),
    .read_candidate_offset(energy_read_candidate_offset),
    .segment_valid(energy_segment_valid),
    .segment_ready(energy_segment_ready),
    .segment_candidate_offset(energy_segment_candidate_offset),
    .segment_energy(energy_segment_value),
    .protocol_error_sticky(energy_protocol_error),
    .prefix_overflow_sticky(energy_prefix_overflow)
  );

  fine_partitioned_corr_engine #(
    .PS1_MEMORY_INIT_FILE(PS1_MEMORY_INIT_FILE)
  ) u_partitioned_correlation (
    .clk(clk),.rst_n(rst_n),
    .corrected_write_valid(corrected_valid),
    .corrected_write_ready(corrected_write_ready),
    .corrected_write_index(corrected_local_index),
    .corrected_write_i(corrected_i),.corrected_write_q(corrected_q),
    .corrected_buffer_full(partition_buffer_full),
    .buffer_release(partition_buffer_release),
    .correlation_start(partition_correlation_start),
    .coarse_start(active_coarse_start),
    .result_valid(partition_result_valid),
    .result_ready(partition_result_ready),
    .peak_start(partition_peak_start),.peak_metric(partition_peak_metric),
    .runner_start(partition_runner_start),
    .runner_metric(partition_runner_metric),
    .timing_valid(partition_timing_valid),
    .ambiguity(partition_ambiguity),
    .result_error(partition_result_error),
    .busy(partition_busy),
    .schedule_accept_count(partition_schedule_count),
    .candidate_metric_count(partition_candidate_count),
    .correlation_cycle_count(partition_cycle_count),
    .protocol_error_sticky(partition_protocol_error),
    .arithmetic_error_sticky(partition_arithmetic_error)
  );

  fine_quality_controller u_quality (
    .clk(clk),.rst_n(rst_n),
    .input_valid(quality_input_valid),.input_ready(quality_input_ready),
    .peak_metric(held_peak_metric),.segment_energy(energy_segment_value),
    .timing_valid(held_peak_timing_valid),
    .no_signal((held_peak_metric == 0) || (energy_segment_value == 0)),
    .ambiguity(held_peak_ambiguity),
    .accumulator_overflow(quality_accumulator_overflow_input),
    .corrected_overflow(quality_corrected_overflow_input),
    .protocol_error(quality_protocol_input),
    .denominator_mul_req_valid(denominator_mul_req_valid),
    .denominator_mul_req_ready(denominator_mul_req_ready),
    .denominator_mul_operand_a(denominator_mul_operand_a),
    .denominator_mul_operand_b(denominator_mul_operand_b),
    .denominator_mul_rsp_valid(denominator_mul_rsp_valid),
    .denominator_mul_rsp_ready(denominator_mul_rsp_ready),
    .denominator_mul_rsp_product(denominator_mul_rsp_product),
    .divider_req_valid(divider_req_valid),
    .divider_req_ready(divider_req_ready),
    .divider_dividend(divider_dividend),.divider_divisor(divider_divisor),
    .divider_rsp_valid(divider_rsp_valid),
    .divider_rsp_ready(divider_rsp_ready),
    .divider_rsp_quotient_q15(divider_rsp_quotient_q15),
    .result_valid(quality_result_valid),.result_ready(quality_result_ready),
    .quality_code_q1_15(quality_code),
    .quality_threshold_pass(quality_threshold_pass),
    .fine_valid(quality_fine_valid),
    .result_error(quality_result_error),.error_code(quality_error_code),
    .normalization_shift(quality_normalization_shift)
  );

  always_ff @(posedge clk) begin : core_control
    bistatic_estimator_result_t completed_record;
    if (!rst_n) begin
      state <= ST_WAIT_CONTEXT;
      active_frame_id <= '0;
      active_coarse_start <= '0;
      active_coarse_cfo_hz <= '0;
      active_pair_error <= 1'b0;
      active_protocol_error <= 1'b0;
      active_accumulator_overflow <= 1'b0;
      active_corrected_overflow <= 1'b0;
      active_ip_arithmetic_error <= 1'b0;
      held_peak_start <= '0;
      held_peak_metric <= '0;
      held_peak_timing_valid <= 1'b0;
      held_peak_ambiguity <= 1'b0;
      held_peak_result_error <= 1'b0;
      held_peak_candidate_offset <= '0;
      held_peak_offset_valid <= 1'b0;
      estimator_result_valid <= 1'b0;
      estimator_result <= '0;
      service_cycle_count <= '0;
      deadline_miss_sticky <= 1'b0;
      protocol_error_sticky <= 1'b0;
      arithmetic_error_sticky <= 1'b0;
    end else begin
      if (live_protocol_error)
        protocol_error_sticky <= 1'b1;
      if (phase_conversion_error || corrector_overflow ||
          energy_prefix_overflow || partition_arithmetic_error)
        arithmetic_error_sticky <= 1'b1;

      if (service_active) begin
        if (service_cycle_count < DEADLINE_CYCLES)
          service_cycle_count <= service_cycle_count+1'b1;
        if (live_protocol_error)
          active_protocol_error <= 1'b1;
        if (partition_arithmetic_error)
          active_accumulator_overflow <= 1'b1;
        if (corrector_overflow)
          active_corrected_overflow <= 1'b1;
        if (phase_conversion_error || energy_prefix_overflow)
          active_ip_arithmetic_error <= 1'b1;
      end

      unique case (state)
        ST_WAIT_CONTEXT: begin
          if (job_accept) begin
            active_frame_id <= pair_job_frame_id;
            active_coarse_start <= pair_job_coarse_start;
            active_coarse_cfo_hz <= pair_job_coarse_cfo_hz;
            active_pair_error <= (!pair_job_handoff_valid ||
                (|pair_job_error_status)) && !pair_job_ambiguity;
            active_protocol_error <= !capture_context_valid ||
                !job_identity_valid || !job_range_valid;
            active_accumulator_overflow <= 1'b0;
            active_corrected_overflow <= 1'b0;
            active_ip_arithmetic_error <= 1'b0;
            service_cycle_count <= '0;
            held_peak_start <= '0;
            held_peak_metric <= '0;
            held_peak_timing_valid <= 1'b0;
            held_peak_ambiguity <= 1'b0;
            held_peak_result_error <= 1'b0;
            held_peak_candidate_offset <= '0;
            held_peak_offset_valid <= 1'b0;
            if (job_precheck_valid) begin
              state <= ST_REQUEST_PHASE;
            end else begin
              completed_record = '0;
              completed_record.frame_id = pair_job_frame_id;
              if (pair_job_ambiguity) begin
                completed_record.status = make_status(
                    1'b0,ERROR_AMBIGUITY,
                    1'b1,1'b0,1'b0,1'b0,1'b0,1'b0);
              end else begin
                completed_record.status = make_status(
                    1'b0,ERROR_PROTOCOL,
                    1'b0,1'b0,1'b0,1'b1,
                    !pair_job_handoff_valid ||
                        (|pair_job_error_status),1'b0);
                protocol_error_sticky <= 1'b1;
              end
              estimator_result <= completed_record;
              estimator_result_valid <= 1'b1;
              state <= ST_HOLD_RESULT;
            end
          end
        end

        ST_REQUEST_PHASE: begin
          if (phase_cfo_valid && phase_cfo_ready)
            state <= ST_WAIT_PHASE;
        end

        ST_WAIT_PHASE: begin
          if (corrector_start_fire) begin
            active_ip_arithmetic_error <= phase_conversion_error;
            state <= ST_CORRECT_WINDOW;
          end
        end

        ST_CORRECT_WINDOW: begin
          if (corrector_done)
            state <= ST_WAIT_LOCAL_BUFFERS;
        end

        ST_WAIT_LOCAL_BUFFERS: begin
          if (partition_correlation_start)
            state <= ST_WAIT_CORRELATION;
        end

        ST_WAIT_CORRELATION: begin
          if (partition_result_fire) begin
            held_peak_start <= partition_peak_start;
            held_peak_metric <= partition_peak_metric;
            held_peak_timing_valid <= partition_timing_valid;
            held_peak_ambiguity <= partition_ambiguity;
            held_peak_result_error <= partition_result_error &&
                (partition_peak_metric != 0) && !partition_ambiguity;
            held_peak_offset_valid <= peak_offset_valid;
            if (peak_offset_valid)
              held_peak_candidate_offset <= peak_offset_comb[8:0];
            else begin
              held_peak_candidate_offset <= '0;
              active_protocol_error <= 1'b1;
            end
            state <= ST_REQUEST_PEAK_ENERGY;
          end
        end

        ST_REQUEST_PEAK_ENERGY: begin
          if (energy_request_fire)
            state <= ST_WAIT_PEAK_ENERGY;
        end

        ST_WAIT_PEAK_ENERGY: begin
          if (quality_input_fire) begin
            if (energy_segment_candidate_offset !=
                held_peak_candidate_offset)
              active_protocol_error <= 1'b1;
            state <= ST_WAIT_QUALITY;
          end
        end

        ST_WAIT_QUALITY: begin
          if (quality_completion_now) begin
            completed_record = '0;
            completed_record.frame_id = active_frame_id;
            completed_record.value = effective_quality_fine_valid ?
                held_peak_start : 32'sd0;
            completed_record.quality = quality_code;
            completed_record.status = make_status(
                effective_quality_fine_valid,effective_quality_error_code,
                held_peak_ambiguity,
                quality_accumulator_overflow_input ||
                    quality_corrected_overflow_input,
                active_ip_arithmetic_error || quality_ip_protocol_error,
                quality_protocol_input,
                active_pair_error,1'b0);
            estimator_result <= completed_record;
            estimator_result_valid <= 1'b1;
            state <= ST_HOLD_RESULT;
          end
        end

        ST_HOLD_RESULT: begin
          if (estimator_result_fire) begin
            estimator_result_valid <= 1'b0;
            estimator_result <= '0;
            state <= ST_WAIT_CONTEXT;
          end
        end

        default: begin
          state <= ST_WAIT_CONTEXT;
          protocol_error_sticky <= 1'b1;
        end
      endcase

      // Algorithm completion on the deadline edge wins.  Otherwise publish a
      // stable invalid record; buffer release still waits for its handshake.
      if (deadline_fallback_now) begin
        completed_record = '0;
        completed_record.frame_id = active_frame_id;
        completed_record.status = make_status(
            1'b0,ERROR_PROTOCOL,held_peak_ambiguity,
            active_accumulator_overflow || active_corrected_overflow,
            active_ip_arithmetic_error || quality_ip_protocol_error,
            active_protocol_error || quality_ip_protocol_error,
            active_pair_error,1'b1);
        estimator_result <= completed_record;
        estimator_result_valid <= 1'b1;
        deadline_miss_sticky <= 1'b1;
        state <= ST_HOLD_RESULT;
      end
    end
  end
endmodule
