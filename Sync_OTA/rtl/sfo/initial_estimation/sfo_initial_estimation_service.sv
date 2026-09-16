`timescale 1ns / 1ps
// One T06 client of the existing shared T03 main FFT service.
// The external lease owner routes ONLY this frame's eight transforms to these ports.
module sfo_initial_estimation_service #(
    parameter integer MAX_CYCLES = 65024
) (
    input  logic                                               clk,
    input  logic                                               rst,
    input  logic                                               tap_fire,
    input  logic                                       [127:0] tap_data,
    input  logic                                       [ 31:0] tap_frame_id,
    input  logic signed                                [ 31:0] tap_abs,
    input  logic                                       [  3:0] tap_lane_valid,
    input  logic                                               s_cfo_valid,
    output logic                                               s_cfo_ready,
    input  sfo_stream_pkg::bistatic_estimator_result_t         s_cfo,
    input  logic                                               s_fine_valid,
    output logic                                               s_fine_ready,
    input  sfo_stream_pkg::bistatic_estimator_result_t         s_fine,
    output logic                                               fft_lease_valid,
    input  logic                                               fft_lease_ready,
    output logic                                       [ 31:0] fft_lease_frame_id,
    output logic                                               fft_lease_release,
    output logic                                               fft_abort,
    input  logic                                               fft_abort_done,
    output logic                                               fft_s_valid,
    input  logic                                               fft_s_ready,
    output logic                                       [127:0] fft_s_data,
    output logic                                               fft_s_last,
    input  logic                                               fft_m_valid,
    output logic                                               fft_m_ready,
    input  logic                                       [127:0] fft_m_data,
    input  logic                                               fft_m_last,
    input  logic                                               fft_error,
    output logic                                               m_valid,
    input  logic                                               m_ready,
    output sfo_stream_pkg::bistatic_estimator_result_t         m_result,
    output logic signed                                [ 47:0] m_slope,
    output logic                                       [  7:0] m_error_stage,
    output logic                                               halted,
    output logic                                       [ 31:0] elapsed_cycles,
    output logic                                       [ 31:0] fft_lease_wait_cycles,
    output logic                                       [ 31:0] fft_input_stall_cycles,
    output logic                                       [ 31:0] fft_output_stall_cycles,
    output logic                                       [ 31:0] shared_gain_sample_count,
    output logic                                       [ 12:0] fft_input_count,
    output logic                                       [ 12:0] fft_output_count,
    output logic                                       [ 12:0] observation_count,
    output logic                                       [ 12:0] weight_count,
    output logic                                       [  1:0] cfo_context_occupancy,
    output logic                                       [  1:0] fine_context_occupancy
);
  import sfo_stream_pkg::*;
  typedef enum logic [2:0] {
    IDLE,
    ACQUIRE,
    START,
    RUN,
    CANCEL,
    HOLD_RESULT,
    HALTED
  } state_t;
  state_t state;
  logic fatal_latched, cancel_requested, numeric_valid, lease_owned, front_done;
  logic [ 1:0] cancel_count;
  logic [ 3:0] fft_drain_count;
  logic [31:0] frame_id;
  logic signed [31:0] cfo_hz, fine_start;
  logic [15:0] bypass_status;
  logic
      join_cfo_ready,
      join_fine_ready,
      join_valid,
      join_ready,
      join_numeric,
      join_fail,
      join_outage,
      join_halted,
      join_protocol_fault;
  logic signed [31:0] join_cfo, join_fine;
  bistatic_estimator_result_t join_result;
  logic [7:0] join_fault;
  logic [31:0] join_expected, join_observed, join_age;
  logic [1:0] join_source;
  logic [2:0] join_cancel_cfo, join_cancel_fine;
  logic pipe_rst, active, atomic_start;
  logic front_start_ready, front_valid, front_ready, front_last, front_status_valid;
  logic [127:0] front_data;
  logic [31:0] front_frame, front_status_frame, front_cycles, front_stalls, front_generation;
  logic [11:0] front_beat;
  logic [3:0] front_scaled, front_limiting, front_s18;
  logic front_status_numeric, front_error, front_halted, front_capture_complete, front_lease_active;
  logic [2:0] front_code;
  logic [7:0] front_stage;
  logic [12:0] front_jobs, front_raw, front_corrected;
  logic [4:0] front_pending;
  logic back_start_ready, back_s_ready, back_valid, back_error;
  logic [31:0] back_frame, back_cycles;
  logic signed [31:0] back_ppm;
  logic signed [47:0] back_slope;
  logic [15:0] back_quality;
  logic [2:0] back_code;
  logic [7:0] back_stage;
  logic [12:0] back_fft, back_observations, back_weights;
  assign active = state == ACQUIRE || state == START || state == RUN;
  assign pipe_rst = rst || fatal_latched;
  assign halted = !rst && (fatal_latched || cancel_requested || state == HALTED);
  assign s_cfo_ready = join_cfo_ready && !halted;
  assign s_fine_ready = join_fine_ready && !halted;
  assign join_ready = !rst && state == IDLE;
  assign m_valid = !rst && state == HOLD_RESULT;
  assign fft_lease_valid = !rst && state == ACQUIRE && !fatal_latched;
  assign fft_lease_frame_id = frame_id;
  // Eight guard clocks cover scoped FFT error synchronization after the last result.
  assign fft_lease_release = !rst && state == RUN && lease_owned && fft_output_count == 4096 &&
      fft_drain_count == 8 && !fft_error && !fatal_latched;
  assign fft_abort = !rst && lease_owned && (fatal_latched || cancel_requested);
  assign atomic_start = !rst && state == START && front_start_ready &&
      (!numeric_valid || back_start_ready);
  assign fft_s_valid = !rst && state == RUN && lease_owned && front_valid && front_frame ==
      frame_id && front_beat == fft_input_count[11:0] && fft_input_count < 4096 && !fatal_latched;
  assign front_ready = fft_s_ready && state == RUN && lease_owned && front_frame == frame_id &&
      front_beat == fft_input_count[11:0] && fft_input_count < 4096 && !fft_error && !fatal_latched;
  assign fft_s_data = front_data;
  assign fft_s_last = front_last;
  assign fft_m_ready = !rst && state == RUN && lease_owned && back_s_ready &&
      fft_output_count < 4096 && !fft_error && !fatal_latched;
  sfo_initial_frame_context_join context_join (
      .clk              (clk),
      .rst              (rst),
      .s_cfo_valid      (s_cfo_valid && !halted),
      .s_cfo_ready      (join_cfo_ready),
      .s_cfo            (s_cfo),
      .s_fine_valid     (s_fine_valid && !halted),
      .s_fine_ready     (join_fine_ready),
      .s_fine           (s_fine),
      .m_valid          (join_valid),
      .m_ready          (join_ready),
      .m_result         (join_result),
      .m_coarse_cfo_hz  (join_cfo),
      .m_fine_start     (join_fine),
      .m_numeric_valid  (join_numeric),
      .m_fail_close     (join_fail),
      .m_approved_outage(join_outage),
      .m_protocol_fault (join_protocol_fault),
      .halted           (join_halted),
      .fault_reason     (join_fault),
      .fault_expected_id(join_expected),
      .fault_observed_id(join_observed),
      .fault_source_mask(join_source),
      .canceled_cfo     (join_cancel_cfo),
      .canceled_fine    (join_cancel_fine),
      .cfo_occupancy    (cfo_context_occupancy),
      .fine_occupancy   (fine_context_occupancy),
      .watchdog_age     (join_age)
  );
  sfo_initial_raw_to_fft_frontend #(
      .MAX_CYCLES(MAX_CYCLES)
  ) frontend (
      .clk                 (clk),
      .rst                 (pipe_rst || cancel_requested),
      .tap_fire            (tap_fire),
      .tap_data            (tap_data),
      .tap_frame_id        (tap_frame_id),
      .tap_abs             (tap_abs),
      .tap_lane_valid      (tap_lane_valid),
      .start_valid         (atomic_start),
      .start_ready         (front_start_ready),
      .start_frame_id      (frame_id),
      .start_cfo_hz        (cfo_hz),
      .start_fine_start    (fine_start),
      .start_numeric_valid (numeric_valid),
      .m_valid             (front_valid),
      .m_ready             (front_ready),
      .m_data              (front_data),
      .m_last              (front_last),
      .m_frame_id          (front_frame),
      .m_beat_index        (front_beat),
      .m_scaled            (front_scaled),
      .m_limiting_i        (front_limiting),
      .m_s18_overflow      (front_s18),
      .status_valid        (front_status_valid),
      .status_ready        (state == RUN),
      .status_frame_id     (front_status_frame),
      .status_numeric_valid(front_status_numeric),
      .status_error        (front_error),
      .status_error_code   (front_code),
      .status_error_stage  (front_stage),
      .halted              (front_halted),
      .elapsed_cycles      (front_cycles),
      .accepted_jobs       (front_jobs),
      .accepted_raw        (front_raw),
      .accepted_corrected  (front_corrected),
      .output_stall_cycles (front_stalls),
      .raw_pending_count   (front_pending),
      .capture_complete    (front_capture_complete),
      .lease_active        (front_lease_active),
      .capture_generation  (front_generation)
  );
  sfo_initial_fft_swls_backend #(
      .MAX_CYCLES(MAX_CYCLES)
  ) backend (
      .clk(clk),
      .rst(pipe_rst),
      .frame_start_valid(atomic_start && numeric_valid),
      .frame_start_ready(back_start_ready),
      .frame_start_id(frame_id),
      .s_valid(state == RUN && lease_owned && fft_m_valid && fft_output_count < 4096 &&
               !fft_error && !fatal_latched),
      .s_ready(back_s_ready),
      .s_data(fft_m_data),
      .s_last(fft_m_last),
      .s_fft_error((state == RUN && lease_owned && fft_error) || cancel_requested),
      .m_valid(back_valid),
      .m_ready(state == RUN),
      .m_frame_id(back_frame),
      .m_sfo_ppm(back_ppm),
      .m_quality(back_quality),
      .m_slope(back_slope),
      .m_error(back_error),
      .m_error_code(back_code),
      .m_error_stage(back_stage),
      .elapsed_cycles(back_cycles),
      .accepted_fft_beats(back_fft),
      .accepted_observations(back_observations),
      .weighted_observations(back_weights)
  );
  function automatic logic [15:0] failure_status(input logic [2:0] code, input logic deadline);
    logic [15:0] v;
    begin
      v = 16'h4000;
      v[2:0] = code;
      if (code == 1 || code == 3) v[9] = 1;
      if (code == 2) v[10] = 1;
      if (code == 4 || code == 5) v[8] = 1;
      if (code == 7) v[7] = 1;
      if (code == 6) begin
        v[6] = deadline;
        v[5] = !deadline;
      end
      return v;
    end
  endfunction
  task automatic fail_frame(input logic [2:0] code, input logic [7:0] stage, input logic deadline);
    begin
      cancel_requested <= 1;
      cancel_count <= 0;
      state <= CANCEL;
      m_result.value <= 0;
      m_result.quality <= 0;
      m_result.status <= failure_status(code, deadline);
      m_error_stage <= stage;
      m_slope <= 0;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      fatal_latched <= 0;
      cancel_requested <= 0;
      cancel_count <= 0;
      numeric_valid <= 0;
      lease_owned <= 0;
      front_done <= 0;
      fft_drain_count <= 0;
      frame_id <= 0;
      cfo_hz <= 0;
      fine_start <= 0;
      bypass_status <= 0;
      m_result <= '0;
      m_slope <= 0;
      m_error_stage <= 0;
      elapsed_cycles <= 0;
      fft_lease_wait_cycles <= 0;
      fft_input_stall_cycles <= 0;
      fft_output_stall_cycles <= 0;
      fft_input_count <= 0;
      fft_output_count <= 0;
      observation_count <= 0;
      weight_count <= 0;
      shared_gain_sample_count <= 0;
    end else begin
      if (active || state == CANCEL) elapsed_cycles <= elapsed_cycles + 1'b1;
      if (fft_abort && fft_abort_done) lease_owned <= 0;
      case (state)
        IDLE:
        if (join_valid && join_ready) begin
          frame_id <= join_result.frame_id;
          m_result.frame_id <= join_result.frame_id;
          cfo_hz <= join_cfo;
          fine_start <= join_fine;
          numeric_valid <= join_numeric;
          bypass_status <= join_result.status;
          m_result.value <= 0;
          m_result.quality <= 0;
          m_result.status <= 0;
          m_slope <= 0;
          m_error_stage <= 0;
          front_done <= 0;
          fft_drain_count <= 0;
          elapsed_cycles <= 0;
          fft_lease_wait_cycles <= 0;
          fft_input_stall_cycles <= 0;
          fft_output_stall_cycles <= 0;
          fft_input_count <= 0;
          fft_output_count <= 0;
          observation_count <= 0;
          weight_count <= 0;
          shared_gain_sample_count <= 0;
          if (join_protocol_fault) begin
            fatal_latched <= 1;
            state <= HOLD_RESULT;
            m_result.status <= join_result.status;
            m_error_stage <= 1;
          end else state <= join_numeric ? ACQUIRE : START;
        end
        ACQUIRE: begin
          if (fft_lease_valid && fft_lease_ready) begin
            lease_owned <= 1;
            state <= START;
          end else fft_lease_wait_cycles <= fft_lease_wait_cycles + 1'b1;
        end
        START:   if (atomic_start) state <= RUN;
        RUN: begin
          if (numeric_valid) begin
            observation_count <= back_observations;
            weight_count <= back_weights;
          end
          if (fft_s_valid && !fft_s_ready) fft_input_stall_cycles <= fft_input_stall_cycles + 1'b1;
          if (lease_owned && fft_m_valid && !fft_m_ready)
            fft_output_stall_cycles <= fft_output_stall_cycles + 1'b1;
          if (fft_s_valid && fft_s_ready) begin
            fft_input_count <= fft_input_count + 1'b1;
            shared_gain_sample_count <= shared_gain_sample_count + {31'd0, front_scaled[0]} +
                {31'd0, front_scaled[1]} + {31'd0, front_scaled[2]} + {31'd0, front_scaled[3]};
          end
          if (fft_m_valid && fft_m_ready) fft_output_count <= fft_output_count + 1'b1;
          if (fft_output_count == 4096 && fft_drain_count < 8)
            fft_drain_count <= fft_drain_count + 1'b1;
          if (fft_lease_release) lease_owned <= 0;
          if (front_status_valid) begin
            front_done <= 1;
            if (!numeric_valid && !front_error) begin
              m_result.status <= bypass_status;
              state <= HOLD_RESULT;
            end
          end
          if (back_valid) begin
            m_result.value <= back_ppm;
            m_result.quality <= back_quality;
            m_result.status <= 16'h4800;
            m_slope <= back_slope;
            state <= HOLD_RESULT;
          end
        end
        // Give the child its cancellation edge and one count-capture edge,
        // then sample the stable snapshot BEFORE resetting that child.
        CANCEL:
        if (cancel_count == 2) begin
          if (numeric_valid) begin
            observation_count <= back_observations;
            weight_count <= back_weights;
          end
          fatal_latched <= 1;
          state <= HOLD_RESULT;
        end else cancel_count <= cancel_count + 1'b1;
        HOLD_RESULT:
        if (m_ready) begin
          if (fatal_latched) state <= HALTED;
          else state <= IDLE;
        end
        HALTED:  state <= HALTED;
        default: fail_frame(3'd6, 8'd255, 0);
      endcase
      if (active) begin
        if (lease_owned && fft_error) fail_frame(3'd7, 8'd2, 0);
        else if (state == RUN && front_status_valid &&
                 (front_error || front_status_frame != frame_id ||
                  front_status_numeric != numeric_valid))
          fail_frame(front_error ? front_code : 3'd6, 8'd16 + front_stage, front_stage == 9);
        else if (state == RUN && numeric_valid && front_valid &&
                 (front_frame != frame_id || front_beat != fft_input_count[11:0] ||
                  fft_input_count >= 4096 || front_last != (front_beat[8:0] == 511)))
          fail_frame(3'd6, 8'd32, 0);
        else if (state == RUN && lease_owned && fft_m_valid && fft_output_count >= 4096)
          fail_frame(3'd6, 8'd33, 0);
        else if (state == RUN && back_valid && back_error)
          fail_frame(back_code == 0 ? 3'd7 : back_code, 8'd64 + back_stage, back_stage == 96);
        else if (state == RUN && back_valid &&
                 (!numeric_valid || back_frame != frame_id || !front_done || lease_owned ||
                  fft_input_count != 4096 || fft_output_count != 4096 || back_fft != 4096 ||
                  back_observations != 6560 || back_weights != 6560))
          fail_frame(3'd6, 8'd34, 0);
        else if (elapsed_cycles >= MAX_CYCLES - 1 && !(state == RUN && back_valid) &&
                 !(state == RUN && front_status_valid && !numeric_valid))
          fail_frame(3'd6, 8'd3, 1);
      end
    end
  end
endmodule
