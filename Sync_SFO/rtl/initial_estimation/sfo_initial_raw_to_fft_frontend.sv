`timescale 1ns / 1ps
// T06 private raw capture -> native CFO correction -> shared FFT input client.
// All arithmetic is reused official-IP logic. The shared FFT itself is external.
module sfo_initial_raw_to_fft_frontend #(
    parameter integer MAX_CYCLES = 65024
) (
    input  logic                clk,
    input  logic                rst,
    input  logic                tap_fire,
    input  logic        [127:0] tap_data,
    input  logic        [ 31:0] tap_frame_id,
    input  logic signed [ 31:0] tap_abs,
    input  logic        [  3:0] tap_lane_valid,
    input  logic                start_valid,
    output logic                start_ready,
    input  logic        [ 31:0] start_frame_id,
    input  logic signed [ 31:0] start_cfo_hz,
    input  logic signed [ 31:0] start_fine_start,
    input  logic                start_numeric_valid,
    output logic                m_valid,
    input  logic                m_ready,
    output logic        [127:0] m_data,
    output logic                m_last,
    output logic        [ 31:0] m_frame_id,
    output logic        [ 11:0] m_beat_index,
    output logic        [  3:0] m_scaled,
    output logic        [  3:0] m_limiting_i,
    output logic        [  3:0] m_s18_overflow,
    output logic                status_valid,
    input  logic                status_ready,
    output logic        [ 31:0] status_frame_id,
    output logic                status_numeric_valid,
    output logic                status_error,
    output logic        [  2:0] status_error_code,
    output logic        [  7:0] status_error_stage,
    output logic                halted,
    output logic        [ 31:0] elapsed_cycles,
    output logic        [ 12:0] accepted_jobs,
    output logic        [ 12:0] accepted_raw,
    output logic        [ 12:0] accepted_corrected,
    output logic        [ 31:0] output_stall_cycles,
    output logic        [  4:0] raw_pending_count,
    output logic                capture_complete,
    output logic                lease_active,
    output logic        [ 31:0] capture_generation
);
  typedef enum logic [3:0] {
    IDLE,
    FLUSH,
    WAIT_CAPTURE,
    LEASE_SETTLE,
    PINC_INPUT,
    PINC_WAIT,
    JOB_START,
    RUN,
    DRAIN,
    SKIP_RELEASE,
    SKIP_WAIT,
    HOLD_RESULT,
    HALTED
  } state_t;
  state_t state;
  logic [3:0] flush_count;
  logic [31:0] frame_id, pinc;
  logic signed [31:0] cfo_hz, fine_start;
  logic numeric_valid, local_rst, service_active;
  logic lease_valid, lease_ready, lease_release, capture_error;
  logic [31:0] leased_frame;
  logic phase_in_ready, phase_valid, phase_ready, phase_error, mul_req, mul_rsp;
  logic signed [18:0] mul_a;
  logic signed [39:0] mul_b;
  logic signed [58:0] mul_product;
  logic [31:0] phase_code;
  logic seq_start_ready, seq_valid, seq_ready, seq_busy, seq_done, seq_range_error, seq_finished;
  logic [31:0] seq_frame;
  logic signed [31:0] seq_abs;
  logic [3:0] seq_symbol;
  logic [8:0] seq_beat;
  logic [127:0] seq_phase;
  logic seq_end;
  logic [31:0] seq_tag;
  logic raw_valid, raw_ready;
  logic [63:0] raw_i, raw_q;
  logic [31:0] raw_frame, raw_generation, raw_tag;
  logic signed [31:0] raw_abs;
  logic [3:0] raw_symbol;
  logic [8:0] raw_beat;
  logic [127:0] raw_phase;
  logic raw_end;
  logic cfo_valid, cfo_ready, cfo_error;
  logic [63:0] cfo_i, cfo_q;
  logic [31:0] cfo_tag;
  logic [3:0] cfo_scaled, cfo_limiting, cfo_s18, cfo_range;
  logic [5:0] cfo_pending;
  logic raw_metadata_ok, corrected_metadata_ok, output_fire;
  initial if (MAX_CYCLES < 32) $error("MAX_CYCLES must cover local startup");
  assign service_active = state != IDLE && state != HOLD_RESULT && state != HALTED;
  assign local_rst = rst || state == FLUSH || state == HALTED ||
      (state == HOLD_RESULT && status_error);
  assign start_ready = !rst && state == IDLE;
  assign status_valid = !rst && state == HOLD_RESULT;
  assign halted = !rst && (state == HALTED || (state == HOLD_RESULT && status_error));
  assign lease_valid = !rst && state == WAIT_CAPTURE;
  assign lease_release = !rst && lease_active && raw_pending_count == 0 &&
      ((state == RUN || state == DRAIN) && accepted_raw == 4096 || state == SKIP_RELEASE);
  assign seq_tag = {20'd0, (seq_symbol[2:0] - 3'd3), seq_beat};
  assign raw_metadata_ok = raw_frame == frame_id && raw_generation == capture_generation &&
      raw_tag == {19'd0, accepted_raw} && raw_symbol >= 3 && raw_symbol <= 10 && raw_tag[11:9] ==
      (raw_symbol[2:0] - 3'd3) && raw_tag[8:0] == raw_beat && raw_end == (raw_beat == 511);
  assign corrected_metadata_ok = cfo_tag == {19'd0, accepted_corrected};
  assign raw_ready = state == RUN && cfo_ready && raw_metadata_ok && !capture_error && !cfo_error;
  assign m_valid = !rst && state == RUN && cfo_valid && corrected_metadata_ok && !(|cfo_range) &&
      !capture_error && !cfo_error;
  assign output_fire = m_valid && m_ready;
  assign m_frame_id = frame_id;
  assign m_beat_index = cfo_tag[11:0];
  assign m_last = cfo_tag[8:0] == 511;
  assign m_scaled = cfo_scaled;
  assign m_limiting_i = cfo_limiting;
  assign m_s18_overflow = cfo_s18;
  for (genvar lane = 0; lane < 4; lane++) begin : g_pack
    assign m_data[lane*32+:32] = {cfo_q[lane*16+:16], cfo_i[lane*16+:16]};
  end
  sfo_initial_raw_reader_local_capture capture (
      .clk              (clk),
      .rst              (rst),
      .tap_fire         (tap_fire),
      .tap_data         (tap_data),
      .tap_frame        (tap_frame_id),
      .tap_abs          (tap_abs),
      .tap_lane_valid   (tap_lane_valid),
      .lease_valid      (lease_valid),
      .lease_ready      (lease_ready),
      .lease_frame      (frame_id),
      .lease_release    (lease_release),
      .capture_complete (capture_complete),
      .lease_active     (lease_active),
      .active_frame     (leased_frame),
      .active_generation(capture_generation),
      .s_valid          (seq_valid && state == RUN),
      .s_ready          (seq_ready),
      .s_frame          (seq_frame),
      .s_tag            (seq_tag),
      .s_abs            (seq_abs),
      .s_symbol         (seq_symbol),
      .s_beat           (seq_beat),
      .s_phase          (seq_phase),
      .s_end            (seq_end),
      .m_valid          (raw_valid),
      .m_ready          (raw_ready),
      .m_i              (raw_i),
      .m_q              (raw_q),
      .m_frame          (raw_frame),
      .m_generation     (raw_generation),
      .m_tag            (raw_tag),
      .m_abs            (raw_abs),
      .m_symbol         (raw_symbol),
      .m_beat           (raw_beat),
      .m_phase          (raw_phase),
      .m_end            (raw_end),
      .pending_count    (raw_pending_count),
      .error_sticky     (capture_error)
  );
  sfo_cfo_phase_increment phase_conversion (
      .clk                 (clk),
      .rst_n               (!local_rst),
      .cfo_valid           (state == PINC_INPUT),
      .cfo_ready           (phase_in_ready),
      .cfo_hz              (cfo_hz),
      .mul_req_valid       (mul_req),
      .mul_req_a           (mul_a),
      .mul_req_b           (mul_b),
      .mul_rsp_valid       (mul_rsp),
      .mul_rsp_product     (mul_product),
      .phase_code_valid    (phase_valid),
      .phase_code_ready    (phase_ready),
      .phase_increment_code(phase_code),
      .conversion_error    (phase_error)
  );
  sfo_cfo_scale_vendor_adapter phase_multiplier (
      .clk        (clk),
      .rst_n      (!local_rst),
      .req_valid  (mul_req),
      .req_a      (mul_a),
      .req_b      (mul_b),
      .rsp_valid  (mul_rsp),
      .rsp_product(mul_product)
  );
  assign phase_ready = state == PINC_WAIT;
  sfo_initial_ps3_ps10_job_sequencer sequencer (
      .clk                      (clk),
      .rst_n                    (!local_rst),
      .start_valid              (state == JOB_START),
      .start_ready              (seq_start_ready),
      .start_frame_id           (frame_id),
      .start_fine_start         (fine_start),
      .start_phase_increment    (pinc),
      .read_req_valid           (seq_valid),
      .read_req_ready           (seq_ready && state == RUN),
      .read_req_frame_id        (seq_frame),
      .read_req_lane0_abs_sample(seq_abs),
      .read_req_ps_symbol       (seq_symbol),
      .read_req_beat_index      (seq_beat),
      .read_req_phase_codes     (seq_phase),
      .read_req_transaction_end (seq_end),
      .busy                     (seq_busy),
      .done_pulse               (seq_done),
      .range_error_pulse        (seq_range_error)
  );
  sfo_initial_cfo_derotate_s16_4lane correction (
      .clk(clk),
      .rst(local_rst),
      .s_valid(raw_valid && state == RUN && raw_metadata_ok && !capture_error),
      .s_ready(cfo_ready),
      .s_phase(raw_phase),
      .s_i(raw_i),
      .s_q(raw_q),
      .s_tag(raw_tag),
      .m_valid(cfo_valid),
      .m_ready(m_ready && state == RUN && corrected_metadata_ok && !(|cfo_range) && !capture_error),
      .m_i(cfo_i),
      .m_q(cfo_q),
      .m_tag(cfo_tag),
      .m_scaled(cfo_scaled),
      .m_limiting_i(cfo_limiting),
      .m_s18_overflow(cfo_s18),
      .m_range_error(cfo_range),
      .raw_pending_count(cfo_pending),
      .protocol_error_sticky(cfo_error)
  );
  task automatic fail_frame(input logic [2:0] code, input logic [7:0] stage);
    begin
      state <= HOLD_RESULT;
      status_error <= 1;
      status_error_code <= code;
      status_error_stage <= stage;
      status_numeric_valid <= 0;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      flush_count <= 0;
      frame_id <= 0;
      cfo_hz <= 0;
      fine_start <= 0;
      numeric_valid <= 0;
      pinc <= 0;
      status_frame_id <= 0;
      status_numeric_valid <= 0;
      status_error <= 0;
      status_error_code <= 0;
      status_error_stage <= 0;
      elapsed_cycles <= 0;
      accepted_jobs <= 0;
      accepted_raw <= 0;
      accepted_corrected <= 0;
      output_stall_cycles <= 0;
      seq_finished <= 0;
    end else begin
      if (service_active) elapsed_cycles <= elapsed_cycles + 1'b1;
      case (state)
        IDLE:
        if (start_valid && start_ready) begin
          frame_id <= start_frame_id;
          status_frame_id <= start_frame_id;
          cfo_hz <= start_cfo_hz;
          fine_start <= start_fine_start;
          numeric_valid <= start_numeric_valid;
          status_numeric_valid <= 0;
          status_error <= 0;
          status_error_code <= 0;
          status_error_stage <= 0;
          elapsed_cycles <= 0;
          accepted_jobs <= 0;
          accepted_raw <= 0;
          accepted_corrected <= 0;
          output_stall_cycles <= 0;
          seq_finished <= 0;
          flush_count <= 0;
          state <= FLUSH;
        end
        FLUSH:
        if (flush_count == 7) state <= WAIT_CAPTURE;
        else flush_count <= flush_count + 1'b1;
        WAIT_CAPTURE: if (lease_valid && lease_ready) state <= LEASE_SETTLE;
        LEASE_SETTLE:
        if (lease_active) begin
          if (leased_frame != frame_id) fail_frame(3'd6, 8'd2);
          else if (!numeric_valid) state <= SKIP_RELEASE;
          else if (fine_start < -360 || fine_start > 360) fail_frame(3'd4, 8'd3);
          else state <= PINC_INPUT;
        end
        PINC_INPUT: if (phase_in_ready) state <= PINC_WAIT;
        PINC_WAIT:
        if (phase_valid) begin
          if (phase_error) fail_frame(3'd7, 8'd4);
          else begin
            pinc  <= phase_code;
            state <= JOB_START;
          end
        end
        JOB_START: if (seq_start_ready) state <= RUN;
        RUN: begin
          if (seq_valid && seq_ready) accepted_jobs <= accepted_jobs + 1'b1;
          if (raw_valid && raw_ready) accepted_raw <= accepted_raw + 1'b1;
          if (seq_done) seq_finished <= 1;
          if (m_valid && !m_ready) output_stall_cycles <= output_stall_cycles + 1'b1;
          if (output_fire) begin
            accepted_corrected <= accepted_corrected + 1'b1;
            if (accepted_corrected == 4095) state <= DRAIN;
          end
        end
        DRAIN:
        if (!lease_active) begin
          if (accepted_jobs != 4096 || accepted_raw != 4096 || accepted_corrected != 4096 ||
              !seq_finished || raw_pending_count != 0 || cfo_pending != 0 || raw_valid ||
              cfo_valid || seq_busy)
            fail_frame(3'd6, 8'd8);
          else begin
            status_numeric_valid <= 1;
            state <= HOLD_RESULT;
          end
        end
        SKIP_RELEASE: if (lease_release) state <= SKIP_WAIT;
        SKIP_WAIT:
        if (!lease_active) begin
          status_numeric_valid <= 0;
          state <= HOLD_RESULT;
        end
        HOLD_RESULT:
        if (status_ready) begin
          if (status_error || capture_error) state <= HALTED;
          else state <= IDLE;
        end
        HALTED: state <= HALTED;
        default: fail_frame(3'd6, 8'd255);
      endcase
      if (service_active) begin
        if (capture_error) fail_frame(3'd6, 8'd1);
        else if (seq_range_error) fail_frame(3'd4, 8'd5);
        else if (state == RUN && raw_valid && !raw_metadata_ok) fail_frame(3'd6, 8'd6);
        else if ((state == RUN || state == DRAIN) &&
                 (cfo_error || (cfo_valid && (!corrected_metadata_ok || (|cfo_range)))))
          fail_frame((|cfo_range) ? 3'd4 : 3'd6, 8'd7);
        else if (elapsed_cycles >= MAX_CYCLES - 1 && !(state == DRAIN && !lease_active))
          fail_frame(3'd6, 8'd9);
      end
    end
  end
endmodule
