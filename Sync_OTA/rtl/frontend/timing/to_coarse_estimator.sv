`timescale 1ns/1ps

module to_coarse_estimator (
  input  logic clk,
  input  logic rst_n,

  input  logic data_valid,
  output logic data_ready,
  input  logic [127:0] data,
  input  bistatic_stream_pkg::bistatic_stream_metadata_t metadata,

  output logic estimator_result_valid,
  input  logic estimator_result_ready,
  output bistatic_stream_pkg::bistatic_estimator_result_t
      estimator_result,

  output logic deadline_miss_sticky,
  output logic input_protocol_error_sticky,
  output logic result_service_error_sticky,
  output logic arithmetic_error_sticky,
  output logic arithmetic_ip_error_sticky,
  output logic [1:0] queued_result_pairs
);
  import bistatic_stream_pkg::*;

  localparam int unsigned LAST_OBSERVATION_BEAT_INDEX = 2812;
  localparam int unsigned DEADLINE_DELTA_CYCLES = 1024;
  localparam int unsigned MAX_READY_LOW_CYCLES = 334080;

  logic beat_accept;
  logic recognized_frame_start;

  logic pair_valid;
  logic pair_first;
  logic pair_last;
  logic [127:0] pair_current_data;
  logic [127:0] pair_delayed_data;
  logic [31:0] pair_frame_id;
  logic [31:0] pair_current_base_sample_index;
  logic pair_context_valid;
  logic lag_protocol_error;

  logic aggregate_valid;
  logic aggregate_first;
  logic aggregate_last;
  logic signed [34:0] aggregate_p_re;
  logic signed [34:0] aggregate_p_im;
  logic [33:0] aggregate_energy;
  logic [31:0] aggregate_frame_id;
  logic [31:0] aggregate_current_base_sample_index;
  logic aggregate_context_valid;
  logic correlation_arithmetic_error;
  logic correlation_ip_error;

  logic metric_input_valid;
  logic metric_input_last;
  logic [8:0] metric_input_index;
  logic signed [42:0] metric_input_p_re;
  logic signed [42:0] metric_input_p_im;
  logic [41:0] metric_input_energy;
  logic rolling_arithmetic_error;
  logic rolling_protocol_error;

  logic metric_valid;
  logic metric_last;
  logic [8:0] metric_index;
  logic signed [42:0] metric_p_re;
  logic signed [42:0] metric_p_im;
  logic [41:0] metric_energy;
  logic metric_qualified;
  logic [86:0] metric_p_magnitude_squared;
  logic [83:0] metric_energy_squared;
  logic [93:0] metric_threshold_lhs;
  logic [85:0] metric_threshold_rhs;

  logic selection_done;
  logic selection_found;
  logic selection_ambiguity;
  logic signed [31:0] selected_start_sample;
  logic [8:0] selected_plateau_beats;
  logic signed [10:0] safe_first_trace_index;
  logic signed [10:0] safe_last_trace_index;
  logic plateau_protocol_error;

  logic replay_busy;
  logic replay_done;
  logic replay_aggregate_valid;
  logic signed [47:0] replay_p_re;
  logic signed [47:0] replay_p_im;
  logic [46:0] replay_energy;
  logic [5:0] replay_point_count;
  logic replay_protocol_error;
  logic replay_arithmetic_error;

  logic phase_request_ready;
  logic phase_engine_busy;
  logic phase_result_valid;
  logic phase_result_algorithm_valid;
  logic phase_result_energy_invalid;
  logic signed [47:0] phase_result_code_q3_45;
  logic [47:0] phase_result_magnitude;
  logic signed [31:0] phase_result_cfo;
  logic [15:0] phase_result_quality;
  logic phase_arithmetic_error;
  logic phase_ip_error;

  logic active_frame;
  logic [31:0] active_frame_id;
  logic [31:0] expected_observation_index;
  logic observation_complete;
  logic frame_input_error;
  logic frame_context_known;
  logic frame_context_valid;
  logic [10:0] deadline_counter;
  logic algorithm_closed;

  logic selection_found_reg;
  logic selection_ambiguity_reg;
  logic signed [31:0] selected_start_reg;

  logic [2:0] arithmetic_error_bus;
  logic [5:0] ip_error_bus;
  logic new_arithmetic_error;
  logic new_ip_error;

  logic invalid_replay_completion;
  logic algorithm_completion_now;
  logic deadline_fallback_now;
  logic new_pair_event;
  logic [15:0] new_common_status;
  bistatic_estimator_result_t new_start_record;
  bistatic_estimator_result_t new_cfo_record;

  logic pending_pair;
  bistatic_estimator_result_t pending_start_record;
  bistatic_estimator_result_t pending_cfo_record;
  logic fifo_pair_ready;
  logic fifo_pair_valid;
  bistatic_estimator_result_t fifo_start_record;
  bistatic_estimator_result_t fifo_cfo_record;
  logic fifo_pair_handshake;
  logic fifo_overflow_sticky;

  logic result_pair_error_pending;
  logic service_monitor_active;
  logic [18:0] consecutive_ready_low;
  logic frame_window_active;
  logic [2:0] result_handshakes_in_window;
  logic result_handshake;

  assign data_ready = rst_n;
  assign beat_accept = data_valid && data_ready;
  assign recognized_frame_start = beat_accept &&
      (metadata.beat_base_sample_index == 0);

  coarse_lag1024_beat_ring u_lag1024 (
    .clk(clk),
    .rst_n(rst_n),
    .beat_accept(beat_accept),
    .beat_data(data),
    .beat_frame_id(metadata.frame_id),
    .beat_base_sample_index(metadata.beat_base_sample_index),
    .beat_lane_valid(metadata.lane_valid),
    .beat_nominal_region(metadata.nominal_region),
    .beat_halo_or_guard(metadata.halo_or_guard),
    .beat_physical_frame_end(metadata.physical_frame_end),
    .pair_valid(pair_valid),
    .pair_first(pair_first),
    .pair_last(pair_last),
    .pair_current_data(pair_current_data),
    .pair_delayed_data(pair_delayed_data),
    .pair_frame_id(pair_frame_id),
    .pair_current_base_sample_index(
        pair_current_base_sample_index),
    .pair_context_valid(pair_context_valid),
    .protocol_error_sticky(lag_protocol_error)
  );

  coarse_corr_energy_4lane u_corr_energy (
    .clk(clk),
    .rst_n(rst_n),
    .pair_valid(pair_valid),
    .pair_first(pair_first),
    .pair_last(pair_last),
    .pair_current_data(pair_current_data),
    .pair_delayed_data(pair_delayed_data),
    .pair_frame_id(pair_frame_id),
    .pair_current_base_sample_index(
        pair_current_base_sample_index),
    .pair_context_valid(pair_context_valid),
    .aggregate_valid(aggregate_valid),
    .aggregate_first(aggregate_first),
    .aggregate_last(aggregate_last),
    .aggregate_p_re(aggregate_p_re),
    .aggregate_p_im(aggregate_p_im),
    .aggregate_energy(aggregate_energy),
    .aggregate_frame_id(aggregate_frame_id),
    .aggregate_current_base_sample_index(
        aggregate_current_base_sample_index),
    .aggregate_context_valid(aggregate_context_valid),
    .arithmetic_overflow_sticky(correlation_arithmetic_error),
    .ip_protocol_error_sticky(correlation_ip_error)
  );

  coarse_rolling_sc_accumulator u_rolling_accumulator (
    .clk(clk),
    .rst_n(rst_n),
    .aggregate_valid(aggregate_valid),
    .aggregate_first(aggregate_first),
    .aggregate_last(aggregate_last),
    .aggregate_p_re(aggregate_p_re),
    .aggregate_p_im(aggregate_p_im),
    .aggregate_energy(aggregate_energy),
    .metric_valid(metric_input_valid),
    .metric_last(metric_input_last),
    .metric_index(metric_input_index),
    .rolling_p_re(metric_input_p_re),
    .rolling_p_im(metric_input_p_im),
    .rolling_energy(metric_input_energy),
    .arithmetic_overflow_sticky(rolling_arithmetic_error),
    .protocol_error_sticky(rolling_protocol_error)
  );

  coarse_metric_threshold u_metric_threshold (
    .clk(clk),
    .rst_n(rst_n),
    .metric_in_valid(metric_input_valid),
    .metric_in_last(metric_input_last),
    .metric_in_index(metric_input_index),
    .metric_in_p_re(metric_input_p_re),
    .metric_in_p_im(metric_input_p_im),
    .metric_in_energy(metric_input_energy),
    .metric_out_valid(metric_valid),
    .metric_out_last(metric_last),
    .metric_out_index(metric_index),
    .metric_out_p_re(metric_p_re),
    .metric_out_p_im(metric_p_im),
    .metric_out_energy(metric_energy),
    .metric_out_qualified(metric_qualified),
    .metric_out_p_magnitude_squared(
        metric_p_magnitude_squared),
    .metric_out_energy_squared(metric_energy_squared),
    .metric_out_threshold_lhs(metric_threshold_lhs),
    .metric_out_threshold_rhs(metric_threshold_rhs)
  );

  coarse_plateau_selector u_plateau_selector (
    .clk(clk),
    .rst_n(rst_n),
    .metric_valid(metric_valid),
    .metric_index(metric_index),
    .metric_qualified(metric_qualified),
    .metric_last(metric_last),
    .selection_done(selection_done),
    .selection_found(selection_found),
    .selection_ambiguity(selection_ambiguity),
    .selected_start_sample(selected_start_sample),
    .selected_plateau_beats(selected_plateau_beats),
    .safe_first_trace_index(safe_first_trace_index),
    .safe_last_trace_index(safe_last_trace_index),
    .protocol_error_sticky(plateau_protocol_error)
  );

  coarse_safe_phase_replay u_safe_phase_replay (
    .clk(clk),
    .rst_n(rst_n),
    .trace_valid(metric_valid),
    .trace_index(metric_index),
    .trace_p_re(metric_p_re),
    .trace_p_im(metric_p_im),
    .trace_energy(metric_energy),
    .selection_done(selection_done),
    .selection_found(selection_found),
    .safe_first_trace_index(safe_first_trace_index),
    .safe_last_trace_index(safe_last_trace_index),
    .replay_busy(replay_busy),
    .replay_done(replay_done),
    .aggregate_valid(replay_aggregate_valid),
    .aggregate_p_re(replay_p_re),
    .aggregate_p_im(replay_p_im),
    .aggregate_energy(replay_energy),
    .aggregate_point_count(replay_point_count),
    .protocol_error_sticky(replay_protocol_error),
    .arithmetic_overflow_sticky(replay_arithmetic_error)
  );

  cfo_coarse_estimator u_phase_quality (
    .clk(clk),
    .rst_n(rst_n),
    .request_valid(replay_aggregate_valid),
    .request_ready(phase_request_ready),
    .safe_p_re(replay_p_re),
    .safe_p_im(replay_p_im),
    .safe_energy(replay_energy),
    .engine_busy(phase_engine_busy),
    .result_valid(phase_result_valid),
    .result_algorithm_valid(phase_result_algorithm_valid),
    .result_energy_or_correlation_invalid(
        phase_result_energy_invalid),
    .result_phase_code_q3_45(phase_result_code_q3_45),
    .result_magnitude_code_q1_47(phase_result_magnitude),
    .result_cfo_hz(phase_result_cfo),
    .result_quality_q1_15(phase_result_quality),
    .arithmetic_overflow_sticky(phase_arithmetic_error),
    .ip_protocol_error_sticky(phase_ip_error)
  );

  assign arithmetic_error_bus = {
      phase_arithmetic_error,
      replay_arithmetic_error,
      rolling_arithmetic_error ||
          correlation_arithmetic_error};
  assign ip_error_bus = {
      phase_ip_error,
      replay_protocol_error,
      plateau_protocol_error,
      rolling_protocol_error,
      correlation_ip_error,
      lag_protocol_error};
  // The child diagnostics are sticky-until-reset.  Treat an asserted level
  // as an active error for every later frame until reset, rather than using
  // a rising-edge snapshot that could miss a repeated fault.
  assign new_arithmetic_error = |arithmetic_error_bus;
  assign new_ip_error = |ip_error_bus;

  assign invalid_replay_completion =
      replay_done && !replay_aggregate_valid;
  assign algorithm_completion_now =
      active_frame && !algorithm_closed &&
      (phase_result_valid || invalid_replay_completion);
  assign deadline_fallback_now =
      active_frame && !algorithm_closed &&
      !algorithm_completion_now &&
      (deadline_counter == DEADLINE_DELTA_CYCLES-1);
  assign new_pair_event =
      algorithm_completion_now || deadline_fallback_now;

  always_comb begin
    new_common_status = '0;
    if (deadline_fallback_now) begin
      new_common_status[6] = 1'b1;
      new_common_status[5] =
          frame_input_error || !observation_complete ||
          !frame_context_known || !frame_context_valid;
      new_common_status[4] = result_pair_error_pending;
    end else if (algorithm_completion_now) begin
      new_common_status[10] = selection_ambiguity_reg;
      new_common_status[9] =
          !selection_found_reg ||
          invalid_replay_completion ||
          phase_result_energy_invalid;
      new_common_status[8] = new_arithmetic_error;
      new_common_status[7] = new_ip_error ||
          (phase_result_valid &&
           !phase_result_algorithm_valid &&
           !phase_result_energy_invalid);
      new_common_status[5] =
          frame_input_error ||
          !frame_context_known ||
          !frame_context_valid;
      new_common_status[4] = result_pair_error_pending;
    end
    new_common_status[11] =
        new_pair_event && !(|new_common_status[10:4]);

    new_start_record = '0;
    new_start_record.frame_id = active_frame_id;
    new_start_record.status = new_common_status;
    new_start_record.status[15:12] = 4'h1;
    new_start_record.value = new_common_status[11] ?
        selected_start_reg : 32'sd0;
    new_start_record.quality = 16'd0;

    new_cfo_record = '0;
    new_cfo_record.frame_id = active_frame_id;
    new_cfo_record.status = new_common_status;
    new_cfo_record.status[15:12] = 4'h2;
    new_cfo_record.value =
        new_common_status[11] && phase_result_valid ?
        phase_result_cfo : 32'sd0;
    new_cfo_record.quality =
        new_common_status[11] && phase_result_valid ?
        phase_result_quality : 16'd0;
  end

  always_comb begin
    fifo_start_record =
        pending_pair ? pending_start_record : new_start_record;
    fifo_cfo_record =
        pending_pair ? pending_cfo_record : new_cfo_record;
    fifo_pair_valid = pending_pair || new_pair_event;
    fifo_pair_handshake = fifo_pair_valid && fifo_pair_ready;
  end

  coarse_result_pair_fifo u_result_pair_fifo (
    .clk(clk),
    .rst_n(rst_n),
    .pair_valid(fifo_pair_valid),
    .pair_ready(fifo_pair_ready),
    .start_record(fifo_start_record),
    .cfo_record(fifo_cfo_record),
    .result_valid(estimator_result_valid),
    .result_ready(estimator_result_ready),
    .result_record(estimator_result),
    .overflow_sticky(fifo_overflow_sticky),
    .queued_pairs(queued_result_pairs)
  );

  assign result_handshake =
      estimator_result_valid && estimator_result_ready;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      active_frame <= 1'b0;
      active_frame_id <= '0;
      expected_observation_index <= '0;
      observation_complete <= 1'b0;
      frame_input_error <= 1'b0;
      frame_context_known <= 1'b0;
      frame_context_valid <= 1'b0;
      deadline_counter <= '0;
      algorithm_closed <= 1'b0;
      selection_found_reg <= 1'b0;
      selection_ambiguity_reg <= 1'b0;
      selected_start_reg <= '0;
      pending_pair <= 1'b0;
      pending_start_record <= '0;
      pending_cfo_record <= '0;
      deadline_miss_sticky <= 1'b0;
      input_protocol_error_sticky <= 1'b0;
      arithmetic_error_sticky <= 1'b0;
      arithmetic_ip_error_sticky <= 1'b0;
      result_pair_error_pending <= 1'b0;
      result_service_error_sticky <= 1'b0;
      service_monitor_active <= 1'b0;
      consecutive_ready_low <= '0;
      frame_window_active <= 1'b0;
      result_handshakes_in_window <= '0;
    end else begin
      if (recognized_frame_start) begin
        service_monitor_active <= 1'b1;
        if (!active_frame && !pending_pair) begin
          active_frame <= 1'b1;
          active_frame_id <= metadata.frame_id;
          expected_observation_index <= 32'd4;
          observation_complete <= 1'b0;
          frame_input_error <=
              !metadata.nominal_region ||
              (metadata.lane_valid != 4'hf) ||
              metadata.halo_or_guard ||
              metadata.physical_frame_end;
          if (!metadata.nominal_region ||
              metadata.lane_valid != 4'hf ||
              metadata.halo_or_guard ||
              metadata.physical_frame_end)
            input_protocol_error_sticky <= 1'b1;
          frame_context_known <= 1'b0;
          frame_context_valid <= 1'b0;
          deadline_counter <= '0;
          algorithm_closed <= 1'b0;
          selection_found_reg <= 1'b0;
          selection_ambiguity_reg <= 1'b0;
          selected_start_reg <= '0;
        end else begin
          frame_input_error <= 1'b1;
          input_protocol_error_sticky <= 1'b1;
        end

        if (frame_window_active &&
            result_handshakes_in_window < 2) begin
          result_service_error_sticky <= 1'b1;
          result_pair_error_pending <= 1'b1;
        end
        frame_window_active <= 1'b1;
        result_handshakes_in_window <=
            result_handshake ? 3'd1 : 3'd0;
      end else if (result_handshake && frame_window_active) begin
        if (result_handshakes_in_window < 3'd7)
          result_handshakes_in_window <=
              result_handshakes_in_window + 1'b1;
      end

      if (active_frame && !observation_complete &&
          !recognized_frame_start) begin
        if (!beat_accept) begin
          frame_input_error <= 1'b1;
          input_protocol_error_sticky <= 1'b1;
        end else if (!metadata.nominal_region ||
                     metadata.halo_or_guard ||
                     metadata.lane_valid != 4'hf ||
                     metadata.frame_id != active_frame_id ||
                     metadata.beat_base_sample_index !=
                         expected_observation_index) begin
          frame_input_error <= 1'b1;
          input_protocol_error_sticky <= 1'b1;
        end else if (metadata.beat_base_sample_index ==
                     LAST_OBSERVATION_BEAT_INDEX) begin
          observation_complete <= 1'b1;
        end else begin
          expected_observation_index <=
              expected_observation_index + 32'd4;
        end
      end

      if (aggregate_valid && aggregate_first &&
          active_frame) begin
        frame_context_known <= 1'b1;
        frame_context_valid <= aggregate_context_valid &&
            (aggregate_frame_id == active_frame_id) &&
            (aggregate_current_base_sample_index == 32'd768);
        if (!aggregate_context_valid ||
            aggregate_frame_id != active_frame_id ||
            aggregate_current_base_sample_index != 32'd768)
          input_protocol_error_sticky <= 1'b1;
      end

      if (selection_done && active_frame) begin
        selection_found_reg <= selection_found;
        selection_ambiguity_reg <= selection_ambiguity;
        selected_start_reg <= selected_start_sample;
      end

      if (replay_aggregate_valid && !phase_request_ready) begin
        arithmetic_ip_error_sticky <= 1'b1;
        input_protocol_error_sticky <= 1'b1;
      end

      if (active_frame && !fifo_pair_handshake) begin
        if (deadline_counter < DEADLINE_DELTA_CYCLES-1)
          deadline_counter <= deadline_counter + 1'b1;
      end

      if (new_pair_event)
        algorithm_closed <= 1'b1;

      if (new_pair_event && !fifo_pair_ready) begin
        pending_pair <= 1'b1;
        pending_start_record <= new_start_record;
        pending_cfo_record <= new_cfo_record;
        pending_start_record.value <= '0;
        pending_start_record.quality <= '0;
        pending_start_record.status[11] <= 1'b0;
        pending_start_record.status[4] <= 1'b1;
        pending_cfo_record.value <= '0;
        pending_cfo_record.quality <= '0;
        pending_cfo_record.status[11] <= 1'b0;
        pending_cfo_record.status[4] <= 1'b1;
        result_pair_error_pending <= 1'b1;
        result_service_error_sticky <= 1'b1;
        if (deadline_counter == DEADLINE_DELTA_CYCLES-1) begin
          pending_start_record.value <= '0;
          pending_start_record.quality <= '0;
          pending_start_record.status[11] <= 1'b0;
          pending_start_record.status[6] <= 1'b1;
          pending_start_record.status[4] <= 1'b1;
          pending_cfo_record.value <= '0;
          pending_cfo_record.quality <= '0;
          pending_cfo_record.status[11] <= 1'b0;
          pending_cfo_record.status[6] <= 1'b1;
          pending_cfo_record.status[4] <= 1'b1;
          deadline_miss_sticky <= 1'b1;
          result_pair_error_pending <= 1'b1;
          result_service_error_sticky <= 1'b1;
        end
      end

      if (pending_pair &&
          deadline_counter == DEADLINE_DELTA_CYCLES-1 &&
          !fifo_pair_ready) begin
        pending_start_record.value <= '0;
        pending_start_record.quality <= '0;
        pending_start_record.status[11] <= 1'b0;
        pending_start_record.status[6] <= 1'b1;
        pending_start_record.status[4] <= 1'b1;
        pending_cfo_record.value <= '0;
        pending_cfo_record.quality <= '0;
        pending_cfo_record.status[11] <= 1'b0;
        pending_cfo_record.status[6] <= 1'b1;
        pending_cfo_record.status[4] <= 1'b1;
        deadline_miss_sticky <= 1'b1;
        result_pair_error_pending <= 1'b1;
        result_service_error_sticky <= 1'b1;
      end

      if (deadline_fallback_now)
        deadline_miss_sticky <= 1'b1;

      if (fifo_pair_handshake) begin
        pending_pair <= 1'b0;
        active_frame <= 1'b0;
        if (fifo_start_record.status[4])
          result_pair_error_pending <= 1'b0;
      end

      if (new_arithmetic_error)
        arithmetic_error_sticky <= 1'b1;
      if (new_ip_error)
        arithmetic_ip_error_sticky <= 1'b1;
      // A failed pair admission is already handled at the exact
      // new_pair_event above.  The child FIFO overflow flag is sticky and
      // therefore must not be edge-converted back into another frame error:
      // doing so would report one backpressure incident on two pairs.

      if (recognized_frame_start) begin
        consecutive_ready_low <= estimator_result_ready ?
            '0 : 19'd1;
      end else if (service_monitor_active) begin
        if (estimator_result_ready) begin
          consecutive_ready_low <= '0;
        end else if (consecutive_ready_low < MAX_READY_LOW_CYCLES) begin
          consecutive_ready_low <= consecutive_ready_low + 1'b1;
        end else begin
          result_service_error_sticky <= 1'b1;
          result_pair_error_pending <= 1'b1;
        end
      end
    end
  end
endmodule
