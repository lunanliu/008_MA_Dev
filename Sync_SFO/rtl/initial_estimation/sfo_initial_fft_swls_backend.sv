`timescale 1ns / 1ps
module sfo_initial_fft_swls_backend #(
    parameter integer MAX_CYCLES = 65024
) (
    input  logic                clk,
    input  logic                rst,
    input  logic                frame_start_valid,
    output logic                frame_start_ready,
    input  logic        [ 31:0] frame_start_id,
    input  logic                s_valid,
    output logic                s_ready,
    input  logic        [127:0] s_data,
    input  logic                s_last,
    input  logic                s_fft_error,
    output logic                m_valid,
    input  logic                m_ready,
    output logic        [ 31:0] m_frame_id,
    output logic signed [ 31:0] m_sfo_ppm,
    output logic        [ 15:0] m_quality,
    output logic signed [ 47:0] m_slope,
    output logic                m_error,
    output logic        [  2:0] m_error_code,
    output logic        [  7:0] m_error_stage,
    output logic        [ 31:0] elapsed_cycles,
    output logic        [ 12:0] accepted_fft_beats,
    output logic        [ 12:0] accepted_observations,
    output logic        [ 12:0] weighted_observations
);
  typedef enum logic [2:0] {
    IDLE,
    FLUSH,
    START,
    RUN,
    CANCEL,
    HOLD_RESULT
  } state_t;
  state_t state;
  logic [3:0] reset_count;
  logic [31:0] active_frame;
  logic local_rst, active, atomic_start, ext_start_ready, obs_start_ready, back_start_ready;
  logic ext_s_ready, ext_valid, ext_ready, ext_pair_last, ext_last, ext_halted;
  logic [31:0] ext_frame;
  logic [ 1:0] ext_pair;
  logic [10:0] ext_index0, ext_index1;
  logic [63:0] ext_first, ext_second;
  logic ext_status_valid, ext_status_error;
  logic [31:0] ext_status_frame;
  logic [ 7:0] ext_status_code;
  logic [12:0] ext_fft_count, ext_popped, ext_active_bins;
  logic [11:0] ext_second_count, ext_emitted;
  logic [10:0] ext_reserved, ext_max_reserved, ext_discarded;
  logic [9:0] ext_max_fifo;
  logic ext_discarded_carry;
  logic [31:0] ext_stalls;
  logic obs_s_ready, obs_valid, obs_ready, obs_pair_last, obs_last, obs_halted, obs_error_sticky;
  logic [31:0] obs_frame, obs_tag0, obs_tag1;
  logic [1:0] obs_pair, obs_zero, obs_axis;
  logic [10:0] obs_index0, obs_index1;
  logic signed [47:0] obs_phase0, obs_phase1, obs_native0, obs_native1;
  logic [63:0] obs_nw0, obs_nw1;
  logic [32:0] obs_dw0, obs_dw1;
  logic [31:0] obs_p10, obs_p11, obs_p20, obs_p21;
  logic obs_status_valid, obs_status_error;
  logic [31:0] obs_status_frame;
  logic [ 7:0] obs_status_code;
  logic [12:0] obs_accepted, obs_emitted, obs_cancelled;
  logic [8:0] obs_pending;
  logic back_s_ready, back_valid, back_error;
  logic [31:0] back_frame, back_cycles;
  logic signed [31:0] back_ppm;
  logic signed [47:0] back_slope;
  logic [15:0] back_quality;
  logic [2:0] back_error_code, back_sealed;
  logic [7:0] back_error_stage;
  logic [12:0] back_accepted, back_weighted;
  logic extractor_done, observation_done;
  assign active = state == FLUSH || state == START || state == RUN;
  assign local_rst = rst || state == FLUSH || state == CANCEL || (state == HOLD_RESULT && m_error);
  assign frame_start_ready = !rst && state == IDLE && !s_fft_error;
  assign m_valid = !rst && state == HOLD_RESULT;
  assign atomic_start = !rst && state == START && ext_start_ready && obs_start_ready &&
      back_start_ready;
  assign s_ready = !local_rst && state == RUN && ext_s_ready;
  assign ext_ready = state == RUN && obs_s_ready;
  assign obs_ready = state == RUN && back_s_ready;
  sfo_initial_fft_pair_extractor extractor (
      .clk                   (clk),
      .rst                   (local_rst),
      .frame_start_valid     (atomic_start),
      .frame_start_ready     (ext_start_ready),
      .frame_start_id        (active_frame),
      .s_valid               (state == RUN && s_valid),
      .s_ready               (ext_s_ready),
      .s_data                (s_data),
      .s_last                (s_last),
      .s_fft_error           (state == RUN && s_fft_error),
      .m_valid               (ext_valid),
      .m_ready               (ext_ready),
      .m_frame_id            (ext_frame),
      .m_pair                (ext_pair),
      .m_index0              (ext_index0),
      .m_index1              (ext_index1),
      .m_first_iq            (ext_first),
      .m_second_iq           (ext_second),
      .m_pair_last           (ext_pair_last),
      .m_last                (ext_last),
      .status_valid          (ext_status_valid),
      .status_ready          (state == RUN),
      .status_frame_id       (ext_status_frame),
      .status_error          (ext_status_error),
      .status_error_code     (ext_status_code),
      .halted                (ext_halted),
      .accepted_fft_beats    (ext_fft_count),
      .popped_halfwords      (ext_popped),
      .accepted_active_bins  (ext_active_bins),
      .accepted_second_beats (ext_second_count),
      .emitted_pair_beats    (ext_emitted),
      .reserved_halfwords    (ext_reserved),
      .max_reserved_halfwords(ext_max_reserved),
      .max_fifo_write_words  (ext_max_fifo),
      .discarded_halfwords   (ext_discarded),
      .discarded_carry       (ext_discarded_carry),
      .input_stall_cycles    (ext_stalls)
  );
  sfo_initial_observation_engine_2lane observations (
      .clk(clk),
      .rst(local_rst),
      .frame_start_valid(atomic_start),
      .frame_start_ready(obs_start_ready),
      .frame_start_id(active_frame),
      .s_valid(state == RUN && ext_valid),
      .s_ready(obs_s_ready),
      .s_frame_id(ext_frame),
      .s_pair(ext_pair),
      .s_index0(ext_index0),
      .s_index1(ext_index1),
      .s_first_iq(ext_first),
      .s_second_iq(ext_second),
      .s_pair_last(ext_pair_last),
      .s_last(ext_last),
      .s_upstream_error(state == RUN &&
                        (s_fft_error || ext_halted || (ext_status_valid && ext_status_error))),
      .m_valid(obs_valid),
      .m_ready(obs_ready),
      .m_frame_id(obs_frame),
      .m_pair(obs_pair),
      .m_index0(obs_index0),
      .m_index1(obs_index1),
      .m_phase0(obs_phase0),
      .m_phase1(obs_phase1),
      .m_native_phase0(obs_native0),
      .m_native_phase1(obs_native1),
      .m_nw0(obs_nw0),
      .m_nw1(obs_nw1),
      .m_dw0(obs_dw0),
      .m_dw1(obs_dw1),
      .m_power_first0(obs_p10),
      .m_power_first1(obs_p11),
      .m_power_second0(obs_p20),
      .m_power_second1(obs_p21),
      .m_tag0(obs_tag0),
      .m_tag1(obs_tag1),
      .m_zero_power(obs_zero),
      .m_axis_mapped(obs_axis),
      .m_pair_last(obs_pair_last),
      .m_last(obs_last),
      .status_valid(obs_status_valid),
      .status_ready(state == RUN),
      .status_frame_id(obs_status_frame),
      .status_error(obs_status_error),
      .status_error_code(obs_status_code),
      .halted(obs_halted),
      .error_sticky(obs_error_sticky),
      .accepted_observations(obs_accepted),
      .emitted_observations(obs_emitted),
      .cancelled_engine_observations(obs_cancelled),
      .pending_pair_beats(obs_pending)
  );
  sfo_initial_swls_weighted_backend backend (
      .clk                  (clk),
      .rst                  (local_rst),
      .frame_start_valid    (atomic_start),
      .frame_start_ready    (back_start_ready),
      .frame_start_id       (active_frame),
      .s_valid              (state == RUN && obs_valid),
      .s_ready              (back_s_ready),
      .s_pair               (obs_pair),
      .s_index0             (obs_index0),
      .s_index1             (obs_index1),
      .s_phase0             (obs_phase0),
      .s_phase1             (obs_phase1),
      .s_nw0                (obs_nw0),
      .s_nw1                (obs_nw1),
      .s_dw0                (obs_dw0),
      .s_dw1                (obs_dw1),
      .m_valid              (back_valid),
      .m_ready              (state == RUN),
      .m_frame_id           (back_frame),
      .m_sfo_ppm            (back_ppm),
      .m_quality            (back_quality),
      .m_slope              (back_slope),
      .m_error              (back_error),
      .m_error_code         (back_error_code),
      .m_error_stage        (back_error_stage),
      .elapsed_cycles       (back_cycles),
      .accepted_observations(back_accepted),
      .weighted_observations(back_weighted),
      .sealed_pair_count    (back_sealed)
  );
  function automatic logic [2:0] child_code(input logic [7:0] code);
    child_code = (code == 0 || code > 7) ? 3'd7 : code[2:0];
  endfunction
  task automatic fail_frame(input logic [2:0] code, input logic [7:0] stage);
    begin
      state <= CANCEL;
      m_error <= 1;
      m_error_code <= code;
      m_error_stage <= stage;
      m_sfo_ppm <= 0;
      m_slope <= 0;
      m_quality <= 0;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      reset_count <= 0;
      active_frame <= 0;
      m_frame_id <= 0;
      elapsed_cycles <= 0;
      extractor_done <= 0;
      observation_done <= 0;
      m_sfo_ppm <= 0;
      m_slope <= 0;
      m_quality <= 0;
      m_error <= 0;
      m_error_code <= 0;
      m_error_stage <= 0;
      accepted_fft_beats <= 0;
      accepted_observations <= 0;
      weighted_observations <= 0;
    end else begin
      if (active) elapsed_cycles <= elapsed_cycles + 1'b1;
      case (state)
        IDLE:
        if (frame_start_valid && frame_start_ready) begin
          state <= FLUSH;
          reset_count <= 0;
          active_frame <= frame_start_id;
          m_frame_id <= frame_start_id;
          elapsed_cycles <= 0;
          extractor_done <= 0;
          observation_done <= 0;
          accepted_fft_beats <= 0;
          accepted_observations <= 0;
          weighted_observations <= 0;
          m_sfo_ppm <= 0;
          m_slope <= 0;
          m_quality <= 0;
          m_error <= 0;
          m_error_code <= 0;
          m_error_stage <= 0;
        end
        FLUSH:
        if (reset_count == 7) state <= START;
        else reset_count <= reset_count + 1'b1;
        START: if (atomic_start) state <= RUN;
        RUN: begin
          if (s_valid && s_ready) accepted_fft_beats <= accepted_fft_beats + 1'b1;
          accepted_observations <= back_accepted;
          weighted_observations <= back_weighted;
          if (ext_status_valid && !ext_status_error) extractor_done <= 1;
          if (obs_status_valid && !obs_status_error) observation_done <= 1;
          if (back_valid) begin
            state <= HOLD_RESULT;
            m_sfo_ppm <= back_ppm;
            m_slope <= back_slope;
            m_quality <= back_quality;
            m_error <= back_error;
            m_error_code <= back_error_code;
            m_error_stage <= back_error ? 8'd64 + back_error_stage : 0;
          end
        end
        // Fault-edge handshakes already updated the child's counters.
        // Reset blocks new internal work throughout CANCEL. At this
        // edge sample those old register values before reset's NBA,
        // then publish a stable result including the last real fire.
        CANCEL: begin
          accepted_observations <= back_accepted;
          weighted_observations <= back_weighted;
          state <= HOLD_RESULT;
        end
        HOLD_RESULT: if (m_ready) state <= IDLE;
        default: fail_frame(3'd6, 8'd255);
      endcase
      if (active && s_fft_error) fail_frame(3'd7, 8'd1);
      else if (state == RUN) begin
        if (ext_halted || (ext_status_valid && ext_status_error))
          fail_frame(child_code(ext_status_code), 8'd16);
        else if ((ext_status_valid && ext_status_frame != active_frame) ||
                 (ext_valid && ext_frame != active_frame))
          fail_frame(3'd6, 8'd17);
        else if (obs_halted || obs_error_sticky || (obs_status_valid && obs_status_error))
          fail_frame(child_code(obs_status_code), 8'd32);
        else if ((obs_status_valid && obs_status_frame != active_frame) ||
                 (obs_valid && obs_frame != active_frame))
          fail_frame(3'd6, 8'd33);
        else if (back_valid && back_error)
          fail_frame(back_error_code == 0 ? 3'd7 : back_error_code, 8'd64 + back_error_stage);
        else if (back_valid &&
                 (back_frame != active_frame || !extractor_done || !observation_done ||
                  accepted_fft_beats != 4096 || ext_fft_count != 4096 || ext_active_bins != 6560 ||
                  obs_accepted != 6560 || obs_emitted != 6560 || back_accepted != 6560 ||
                  back_weighted != 6560 || back_sealed != 4))
          fail_frame(3'd6, 8'd80);
      end
      if (active && elapsed_cycles >= MAX_CYCLES - 1 && !(state == RUN && back_valid))
        fail_frame(3'd6, 8'd96);
    end
  end
endmodule
