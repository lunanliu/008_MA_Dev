`timescale 1ns / 1ps
// Closeout derivative: accepted guard chain arithmetic unchanged; expose accepted-stage/empty observations for autonomous frame control.
module sfo_guarded_resampling_core #(
    // Historical parameter name: this is target_count, including requested guard.
    // In053 E1 target_count=4168; the nominal payload remains4096.
    parameter integer NOMINAL_SAMPLES = 4096
) (
    input  wire                clk,
    input  wire                reset,
    input  wire                start,
    input  wire        [ 31:0] cfg_step,
    input  wire        [ 31:0] cfg_request_beats,
    input  wire signed [ 63:0] cfg_phase0,
    input  wire                s_valid,
    output wire                s_ready,
    input  wire        [127:0] s_data,
    output wire                m_valid,
    input  wire                m_ready,
    output wire        [127:0] m_data,
    output reg         [ 31:0] m_beat,
    output reg         [  3:0] m_nominal_mask,
    output wire                done,
    output wire        [  5:0] observed_valid,
    output wire        [  5:0] observed_accept,
    output wire                observed_arithmetic_empty
);
  localparam [31:0] REQUEST_BEATS = (NOMINAL_SAMPLES + 32) / 4;
  localparam [63:0] LAST_NOMINAL  = 64'd30 + NOMINAL_SAMPLES;
  wire u47_valid, u47_ready, u15_valid, u15_ready, fw_valid, fw_ready, d15_valid, d15_ready;
  wire [255:0] u47_data, d15_data;
  wire [511:0] u15_data, fw_data;
  wire [6:0] observed_credit, observed_fifo, observed_inflight;
  reg started;
  reg [31:0] request_beats;
  sfo_fir_up47 fir47_interpolator (
      .aclk              (clk),
      .aresetn           (!reset),
      .s_axis_data_tvalid(s_valid),
      .s_axis_data_tready(s_ready),
      .s_axis_data_tdata (s_data),
      .m_axis_data_tvalid(u47_valid),
      .m_axis_data_tready(u47_ready),
      .m_axis_data_tdata (u47_data),
      .debug_guarded_data(),
      .saturation        ()
  );
  sfo_fir_up15 fir15_interpolator (
      .aclk              (clk),
      .aresetn           (!reset),
      .s_axis_data_tvalid(u47_valid),
      .s_axis_data_tready(u47_ready),
      .s_axis_data_tdata (u47_data),
      .m_axis_data_tvalid(u15_valid),
      .m_axis_data_tready(u15_ready),
      .m_axis_data_tdata (u15_data),
      .debug_guarded_data(),
      .saturation        ()
  );
  wire farrow_input_empty;
  sfo_guarded_farrow_stream #(
      .NOMINAL_SAMPLES(NOMINAL_SAMPLES)
  ) stream (
      .clk              (clk),
      .reset            (reset),
      .start            (start),
      .cfg_step         (cfg_step),
      .cfg_phase0       (cfg_phase0),
      .cfg_request_beats(cfg_request_beats),
      .s_valid          (u15_valid),
      .s_ready          (u15_ready),
      .s_data           (u15_data),
      .m_valid          (fw_valid),
      .m_ready          (fw_ready),
      .m_data           (fw_data),
      .m_tag            (),
      .issue_valid      (),
      .issue_tag        (),
      .issue_window     (),
      .issue_phase0     (),
      .issue_base       (),
      .issue_mu         (),
      .credit_used      (observed_credit),
      .fifo_count       (observed_fifo),
      .inflight         (observed_inflight),
      .write_count      (),
      .input_pipeline_empty(farrow_input_empty),
      .done             ()
  );
  sfo_fir_down15 fir15_decimator (
      .aclk              (clk),
      .aresetn           (!reset),
      .s_axis_data_tvalid(fw_valid),
      .s_axis_data_tready(fw_ready),
      .s_axis_data_tdata (fw_data),
      .m_axis_data_tvalid(d15_valid),
      .m_axis_data_tready(d15_ready),
      .m_axis_data_tdata (d15_data),
      .debug_guarded_data(),
      .saturation        ()
  );
  sfo_fir_down47 fir47_decimator (
      .aclk              (clk),
      .aresetn           (!reset),
      .s_axis_data_tvalid(d15_valid),
      .s_axis_data_tready(d15_ready),
      .s_axis_data_tdata (d15_data),
      .m_axis_data_tvalid(m_valid),
      .m_axis_data_tready(m_ready),
      .m_axis_data_tdata (m_data),
      .debug_guarded_data(),
      .saturation        ()
  );
  assign observed_valid = {m_valid, d15_valid, fw_valid, u15_valid, u47_valid, s_valid};
  assign observed_accept = {
    m_valid && m_ready,
    d15_valid && d15_ready,
    fw_valid && fw_ready,
    u15_valid && u15_ready,
    u47_valid && u47_ready,
    s_valid && s_ready
  };
  assign observed_arithmetic_empty = (observed_credit == 0) && (observed_fifo == 0) &&
      (observed_inflight == 0) && farrow_input_empty;
  integer lane;
  reg [63:0] physical;
  always @* begin
    m_nominal_mask = 4'b0000;
    physical = 64'd0;
    for (lane = 0; lane < 4; lane = lane + 1) begin
      physical = ({32'd0, m_beat} << 2) + lane;
      if (physical >= 64'd31 && physical <= LAST_NOMINAL) m_nominal_mask[lane] = 1'b1;
    end
  end
  always @(posedge clk) begin
    if (reset) begin
      m_beat <= 0;
      started <= 0;
      request_beats <= 0;
    end else begin
      if (start && !started) begin
        started <= 1;
        request_beats <= cfg_request_beats;
      end
      if (m_valid && m_ready) m_beat <= m_beat + 32'd1;
    end
  end
  assign done = !reset && started && m_beat == request_beats;
  // synthesis translate_off
  initial
    if (NOMINAL_SAMPLES != 4096 && NOMINAL_SAMPLES != 4168 && NOMINAL_SAMPLES != 5120 &&
        NOMINAL_SAMPLES != 5192 && NOMINAL_SAMPLES != 1336320 && NOMINAL_SAMPLES != 1336392)
      $fatal(1, "Unsupported target sample count");
  always @(posedge clk)
    if (!reset) begin
      if (start && (started || cfg_request_beats != REQUEST_BEATS))
        $fatal(1, "Finite chain configuration contract");
      if (m_valid && m_ready && m_beat >= request_beats) $fatal(1, "Extra chain output");
    end
  // synthesis translate_on
endmodule
