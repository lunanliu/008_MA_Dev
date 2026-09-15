`timescale 1ns / 1ps
module sfo_first_resampler #(
    parameter integer NOMINAL_SAMPLES = 1336320,
    parameter integer PROCESSING_LIMIT_CYCLES = 400896
) (
    input  logic                      clk,
    input  logic                      rst,
    input  logic                      abort_request,
    input  logic                      cfg_valid,
    output logic                      cfg_ready,
    input  logic        [ 31:0]       cfg_frame_id,
    input  logic        [ 31:0]       cfg_generation,
    input  logic        [ 31:0]       cfg_estimate_frame_id,
    input  logic        [ 31:0]       cfg_estimate_generation,
    input  logic        [ 15:0]       cfg_estimate_status,
    input  logic signed [ 31:0]       cfg_ppm_q18,
    input  logic signed [ 31:0]       cfg_to,
    input  logic signed [ 31:0]       cfg_raw_first,
    input  logic signed [ 31:0]       cfg_available_first,
    input  logic signed [ 31:0]       cfg_available_last,
    input  logic signed [ 31:0]       cfg_nominal_first,
    input  logic        [ 27:0]       cfg_q0,
    input  logic        [ 31:0]       cfg_input_count,
    input  logic        [ 31:0]       cfg_nominal_count,
    input  logic                      s_valid,
    output logic                      s_ready,
    input  logic        [127:0]       s_data,
    input  logic        [ 31:0]       s_frame_id,
    input  logic        [ 31:0]       s_generation,
    input  logic        [ 31:0]       s_beat,
    input  logic signed [ 31:0]       s_raw_index,
    input  logic        [  3:0]       s_lane_valid,
    input  logic                      s_last,
    output logic                      m_valid,
    input  logic                      m_ready,
    output logic        [127:0]       m_data,
    output logic        [ 31:0]       m_frame_id,
    output logic        [ 31:0]       m_generation,
    output logic        [ 31:0]       m_beat,
    output logic signed [ 31:0]       m_sample_index,
    output logic        [  3:0]       m_lane_valid,
    output logic        [  3:0]       m_nominal_mask,
    output logic        [  3:0]       m_guard_mask,
    output logic                      m_first,
    output logic                      m_last,
    output logic                      m_nominal_first,
    output logic                      m_nominal_last,
    output logic                      completion_valid,
    input  logic                      completion_ready,
    output logic                      completion_success,
    output logic        [ 31:0]       completed_frame_id,
    output logic        [ 31:0]       completed_generation,
    output logic        [  7:0]       error_code,
    output logic                      halted,
    output logic        [ 31:0]       diagnostic_step,
    output logic signed [ 63:0]       diagnostic_phase,
    output logic        [ 31:0]       processing_cycles,
    output logic        [ 31:0]       accepted_input_beats,
    output logic        [ 31:0]       accepted_output_beats,
    output logic        [  5:0][31:0] accepted_stage_beats
);
  localparam integer TARGET = NOMINAL_SAMPLES + 72;
  typedef enum logic [2:0] {
    IDLE,
    PREPARE,
    LAUNCH,
    ACTIVE,
    HOLD_RESULT,
    HALT
  } state_t;
  state_t state;
  logic d_ready, d_valid;
  logic [7:0] d_error;
  logic [31:0] d_frame, d_gen, d_step;
  logic signed [63:0] d_phase;
  logic signed [31:0] d_raw, d_origin;
  logic engine_cfg_ready, engine_s_ready, engine_m_valid, engine_completion, engine_success;
  logic [31:0]
      engine_frame, engine_gen, engine_beat, engine_cycles, engine_packed, engine_error_cycle;
  logic [5:0][31:0] engine_stages;
  logic engine_last, engine_error, engine_poisoned;
  logic [7:0] engine_code;
  logic [31:0] active_frame, active_gen;
  logic signed [31:0] active_origin;
  logic [127:0] engine_data;
  wire abort_engine = abort_request && state == ACTIVE;
  assign cfg_ready = !rst && !abort_request && state == IDLE && d_ready;
  assign s_ready = !rst && state == ACTIVE && engine_s_ready;
  assign m_valid = !rst && state == ACTIVE && engine_m_valid;
  assign m_data = engine_data;
  assign m_frame_id = engine_frame;
  assign m_generation = engine_gen;
  assign m_beat = engine_beat;
  assign m_sample_index = active_origin - 32'sd36 + $signed(engine_beat << 2);
  assign m_lane_valid = 4'hf;
  assign m_nominal_mask = (engine_beat >= 9 && engine_beat < 9 + NOMINAL_SAMPLES / 4) ? 4'hf : 4'h0;
  assign m_guard_mask = ~m_nominal_mask;
  assign m_first = engine_beat == 0;
  assign m_last = engine_last;
  assign m_nominal_first = engine_beat == 9;
  assign m_nominal_last = engine_beat == 8 + NOMINAL_SAMPLES / 4;
  assign completion_valid = !rst && state == HOLD_RESULT;
  assign halted = !rst && (state == HALT || (state == HOLD_RESULT && !completion_success));
  assign processing_cycles = engine_cycles;
  assign accepted_stage_beats = engine_stages;
  assign accepted_input_beats = engine_stages[0];
  assign accepted_output_beats = engine_packed;
  sfo_first_pass_descriptor #(
      .NOMINAL_SAMPLES(NOMINAL_SAMPLES)
  ) descriptor (
      .clk                  (clk),
      .rst                  (rst),
      .s_valid              (cfg_valid && cfg_ready),
      .s_ready              (d_ready),
      .s_frame_id           (cfg_frame_id),
      .s_generation         (cfg_generation),
      .s_estimate_frame_id  (cfg_estimate_frame_id),
      .s_estimate_generation(cfg_estimate_generation),
      .s_estimate_status    (cfg_estimate_status),
      .s_ppm_q18            (cfg_ppm_q18),
      .s_to                 (cfg_to),
      .s_raw_first          (cfg_raw_first),
      .s_available_first    (cfg_available_first),
      .s_available_last     (cfg_available_last),
      .s_nominal_first      (cfg_nominal_first),
      .s_q0                 (cfg_q0),
      .s_input_count        (cfg_input_count),
      .s_nominal_count      (cfg_nominal_count),
      .m_valid              (d_valid),
      .m_ready              (state == LAUNCH && engine_cfg_ready),
      .m_error              (d_error),
      .m_frame_id           (d_frame),
      .m_generation         (d_gen),
      .m_step               (d_step),
      .m_phase              (d_phase),
      .m_raw_first          (d_raw),
      .m_nominal_first      (d_origin)
  );
  sfo_first_frame_scheduler #(
      .SAMPLE_COUNT(TARGET),
      .INPUT_BEATS((NOMINAL_SAMPLES + 540) / 4),
      .PROCESSING_LIMIT_CYCLES(PROCESSING_LIMIT_CYCLES)
  ) engine (
      .clk                  (clk),
      .rst                  (rst),
      .abort_request        (abort_engine),
      .cfg_valid            (state == LAUNCH && !abort_request),
      .cfg_ready            (engine_cfg_ready),
      .cfg_frame_id         (d_frame),
      .cfg_generation       (d_gen),
      .cfg_step             (d_step),
      .cfg_phase0           (d_phase),
      .cfg_raw_first        (d_raw),
      .s_valid              (s_valid && state == ACTIVE),
      .s_ready              (engine_s_ready),
      .s_data               (s_data),
      .s_frame_id           (s_frame_id),
      .s_generation         (s_generation),
      .s_beat               (s_beat),
      .s_raw_index          (s_raw_index),
      .s_lane_valid         (s_lane_valid),
      .s_last               (s_last),
      .m_valid              (engine_m_valid),
      .m_ready              (m_ready && state == ACTIVE),
      .m_data               (engine_data),
      .m_frame_id           (engine_frame),
      .m_generation         (engine_gen),
      .m_beat               (engine_beat),
      .m_last               (engine_last),
      .completion_valid     (engine_completion),
      .completion_ready     (state == ACTIVE),
      .completion_success   (engine_success),
      .completed_frame_id   (),
      .completed_generation (),
      .processing_cycles    (engine_cycles),
      .accepted_stage_beats (engine_stages),
      .accepted_packed_beats(engine_packed),
      .error_sticky         (engine_error),
      .epoch_poisoned       (engine_poisoned),
      .first_error_code     (engine_code),
      .first_error_cycle    (engine_error_cycle)
  );
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      completion_success <= 0;
      error_code <= 0;
      completed_frame_id <= 0;
      completed_generation <= 0;
      active_frame <= 0;
      active_gen <= 0;
      active_origin <= 0;
      diagnostic_step <= 0;
      diagnostic_phase <= 0;
    end else begin
      // Abort is a transaction flush. Once completion is published it is immutable.
      if (abort_request && (state == PREPARE || state == LAUNCH)) begin
        completion_success <= 0;
        error_code <= 1;
        completed_frame_id <= active_frame;
        completed_generation <= active_gen;
        state <= HOLD_RESULT;
      end else
        case (state)
          IDLE:
          if (cfg_valid && cfg_ready) begin
            active_frame <= cfg_frame_id;
            active_gen <= cfg_generation;
            completion_success <= 0;
            error_code <= 0;
            state <= PREPARE;
          end
          PREPARE:
          if (d_valid) begin
            diagnostic_step <= d_step;
            diagnostic_phase <= d_phase;
            active_origin <= d_origin;
            if (d_error != 0) begin
              completion_success <= 0;
              error_code <= d_error;
              completed_frame_id <= d_frame;
              completed_generation <= d_gen;
              state <= HOLD_RESULT;
            end else state <= LAUNCH;
          end
          LAUNCH: if (engine_cfg_ready) state <= ACTIVE;
          ACTIVE:
          if (engine_completion) begin
            completion_success <= engine_success;
            error_code <= engine_code;
            completed_frame_id <= active_frame;
            completed_generation <= active_gen;
            state <= HOLD_RESULT;
          end
          HOLD_RESULT:
          if (completion_valid && completion_ready) state <= completion_success ? IDLE : HALT;
          HALT: begin
          end
          default: begin
            completion_success <= 0;
            error_code <= 8'h18;
            state <= HOLD_RESULT;
          end
        endcase
    end
  end
endmodule
