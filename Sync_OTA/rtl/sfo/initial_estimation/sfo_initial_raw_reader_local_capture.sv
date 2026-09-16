`timescale 1ns / 1ps
// T06 private ingress observer window. No T03 owned-bank access or CDC.
// The tap is the existing 125 MHz four-sample stream with base_sample mod4=0.
module sfo_initial_raw_reader_local_capture (
    input  logic                clk,
    input  logic                rst,
    input  logic                tap_fire,
    input  logic        [127:0] tap_data,
    input  logic        [ 31:0] tap_frame,
    input  logic signed [ 31:0] tap_abs,
    input  logic        [  3:0] tap_lane_valid,
    input  logic                lease_valid,
    output logic                lease_ready,
    input  logic        [ 31:0] lease_frame,
    input  logic                lease_release,
    output logic                capture_complete,
    output logic                lease_active,
    output logic        [ 31:0] active_frame,
    output logic        [ 31:0] active_generation,
    input  logic                s_valid,
    output logic                s_ready,
    input  logic        [ 31:0] s_frame,
    input  logic        [ 31:0] s_tag,
    input  logic signed [ 31:0] s_abs,
    input  logic        [  3:0] s_symbol,
    input  logic        [  8:0] s_beat,
    input  logic        [127:0] s_phase,
    input  logic                s_end,
    output logic                m_valid,
    input  logic                m_ready,
    output logic        [ 63:0] m_i,
    output logic        [ 63:0] m_q,
    output logic        [ 31:0] m_frame,
    output logic        [ 31:0] m_generation,
    output logic        [ 31:0] m_tag,
    output logic signed [ 31:0] m_abs,
    output logic        [  3:0] m_symbol,
    output logic        [  8:0] m_beat,
    output logic        [127:0] m_phase,
    output logic                m_end,
    output logic        [  4:0] pending_count,
    output logic                error_sticky
);
  localparam integer FIRST_SAMPLE = 5272, LAST_SAMPLE = 25959;
  logic capture_valid, capture_context_valid, capture_release;
  logic [31:0] capture_frame, capture_generation, next_generation, last_frame;
  logic frame_history_valid, local_error;
  logic capture_protocol_error, capture_overwrite_error, capture_read_error;
  logic reader_range_error, reader_context_error, reader_protocol_error;
  logic bank_valid, bank_ready, bank_rsp_valid, reader_ready, reader_valid;
  logic [12:0] bank_addr, rsp_addr_pipe[0:1];
  logic [31:0] bank_frame, bank_generation, rsp_frame_pipe[0:1], rsp_generation_pipe[0:1];
  logic [127:0] bank_data;
  logic first_tap, unexpected_frame;
  assign first_tap = tap_fire && tap_abs == FIRST_SAMPLE;
  assign unexpected_frame = first_tap && frame_history_valid && tap_frame != (last_frame + 32'd1);
  assign error_sticky = local_error || capture_protocol_error || capture_overwrite_error ||
      capture_read_error || reader_range_error || reader_context_error || reader_protocol_error;
  assign capture_complete = capture_valid && capture_context_valid && !error_sticky && !rst;
  assign lease_ready = capture_complete && !lease_active;
  assign capture_release = lease_release && lease_active && pending_count == 0 && !error_sticky;
  assign s_ready = reader_ready && lease_active && !lease_release && !error_sticky;
  assign m_valid = reader_valid && !error_sticky && !rst;
  sfo_training_capture_buffer #(
      .FIRST_SAMPLE(FIRST_SAMPLE),
      .LAST_SAMPLE (LAST_SAMPLE),
      .ADDR_WIDTH  (13)
  ) u_capture (
      .clk                           (clk),
      .rst_n                         (!rst),
      .tap_fire                      (tap_fire && !error_sticky && !unexpected_frame),
      .tap_data                      (tap_data),
      .tap_frame_id                  (tap_frame),
      .tap_base_sample_index         (tap_abs),
      .tap_lane_valid                (tap_lane_valid),
      .capture_valid                 (capture_valid),
      .capture_context_valid         (capture_context_valid),
      .capture_frame_id              (capture_frame),
      .capture_release               (capture_release),
      .read_req_valid                (bank_valid),
      .read_req_ready                (bank_ready),
      .read_req_addr                 (bank_addr),
      .read_rsp_valid                (bank_rsp_valid),
      .read_rsp_data                 (bank_data),
      .capture_protocol_error_sticky (capture_protocol_error),
      .capture_overwrite_error_sticky(capture_overwrite_error),
      .read_protocol_error_sticky    (capture_read_error)
  );
  sfo_initial_raw_reader_4lane #(
      .DEPTH_BEATS(5172),
      .ADDR_WIDTH (13)
  ) u_reader (
      .clk                  (clk),
      .rst                  (rst),
      .context_valid        (lease_active && capture_complete),
      .context_frame        (active_frame),
      .context_generation   (active_generation),
      .context_origin       (32'sd5272),
      .context_sample_count (32'd20688),
      .s_valid              (s_valid && lease_active && !lease_release && !error_sticky),
      .s_ready              (reader_ready),
      .s_frame              (s_frame),
      .s_tag                (s_tag),
      .s_abs                (s_abs),
      .s_symbol             (s_symbol),
      .s_beat               (s_beat),
      .s_phase              (s_phase),
      .s_end                (s_end),
      .bank_req_valid       (bank_valid),
      .bank_req_ready       (bank_ready),
      .bank_req_addr        (bank_addr),
      .bank_req_frame       (bank_frame),
      .bank_req_generation  (bank_generation),
      .bank_rsp_valid       (bank_rsp_valid),
      .bank_rsp_addr        (rsp_addr_pipe[1]),
      .bank_rsp_frame       (rsp_frame_pipe[1]),
      .bank_rsp_generation  (rsp_generation_pipe[1]),
      .bank_rsp_data        (bank_data),
      .m_valid              (reader_valid),
      .m_ready              (m_ready && !error_sticky),
      .m_i                  (m_i),
      .m_q                  (m_q),
      .m_frame              (m_frame),
      .m_generation         (m_generation),
      .m_tag                (m_tag),
      .m_abs                (m_abs),
      .m_symbol             (m_symbol),
      .m_beat               (m_beat),
      .m_phase              (m_phase),
      .m_end                (m_end),
      .pending_count        (pending_count),
      .range_error_sticky   (reader_range_error),
      .context_error_sticky (reader_context_error),
      .protocol_error_sticky(reader_protocol_error)
  );
  always_ff @(posedge clk) begin
    if (rst) begin
      local_error <= 0;
      lease_active <= 0;
      active_frame <= 0;
      active_generation <= 0;
      capture_generation <= 0;
      next_generation <= 0;
      last_frame <= 0;
      frame_history_valid <= 0;
      for (int p = 0; p < 2; p++) begin
        rsp_addr_pipe[p] <= 0;
        rsp_frame_pipe[p] <= 0;
        rsp_generation_pipe[p] <= 0;
      end
    end else begin
      rsp_addr_pipe[0] <= bank_addr;
      rsp_addr_pipe[1] <= rsp_addr_pipe[0];
      rsp_frame_pipe[0] <= bank_frame;
      rsp_frame_pipe[1] <= rsp_frame_pipe[0];
      rsp_generation_pipe[0] <= bank_generation;
      rsp_generation_pipe[1] <= rsp_generation_pipe[0];
      if (unexpected_frame) local_error <= 1;
      if (first_tap && !error_sticky && !unexpected_frame) begin
        capture_generation <= next_generation;
        next_generation <= next_generation + 1'b1;
        last_frame <= tap_frame;
        frame_history_valid <= 1;
      end
      if (lease_valid && lease_ready) begin
        if (lease_frame != capture_frame) local_error <= 1;
        else begin
          lease_active <= 1;
          active_frame <= capture_frame;
          active_generation <= capture_generation;
        end
      end
      if (lease_release) begin
        if (!lease_active || pending_count != 0) local_error <= 1;
        else lease_active <= 0;
      end
    end
  end
endmodule
