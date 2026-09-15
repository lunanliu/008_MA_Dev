`timescale 1ns / 1ps

module sfo_initial_fft_service #(
    parameter int unsigned FIFO_WRITE_DEPTH = 64,
    parameter int unsigned PREFILL_SAMPLES  = 32
) (
    input logic clk_125,
    input logic clk_500,
    input logic rst_n,

    input  logic         s_valid,
    output logic         s_ready,
    input  logic [127:0] s_data,
    input  logic         s_transaction_end,

    output logic         m_valid,
    input  logic         m_ready,
    output logic [127:0] m_data,
    output logic         m_transaction_end,

    output logic ingress_overflow,
    output logic ingress_underflow,
    output logic egress_overflow,
    output logic egress_underflow,
    output logic xfft_protocol_error,
    output logic xfft_overflow
);
  // T10 integration derivative: reset is synchronized to the FIFO write/FFT clock.
  // The caller holds rst_n low for at least 32 clk125 cycles; both clocks run.
  // Register decoded parent reset before crossing; no combinational CDC source.
  // INIT=1 keeps startup asserted; one clk125 of additional latency is covered by
  // the caller's held reset and readiness handshake. Both clocks must run.
  (* DONT_TOUCH="TRUE" *) logic reset_source125 = 1'b1;
  always_ff @(posedge clk_125) reset_source125 <= !rst_n;
  wire reset500;
  xpm_cdc_sync_rst #(
      .DEST_SYNC_FF(4),
      .INIT(1),
      .INIT_SYNC_FF(1),
      .SIM_ASSERT_CHK(1)
  ) reset_sync500 (
      .src_rst (reset_source125),
      .dest_clk(clk_500),
      .dest_rst(reset500)
  );
  localparam int unsigned IN_WIDE_WIDTH = 132;
  localparam int unsigned IN_NARROW_WIDTH = 33;
  localparam int unsigned OUT_NARROW_WIDTH = 33;
  localparam int unsigned OUT_WIDE_WIDTH = 132;
  localparam logic [15:0] FORWARD_SCALE_CONFIG = {3'b000, 12'b01_10_10_10_10_11, 1'b1};

  logic [IN_WIDE_WIDTH-1:0] in_fifo_din;
  logic [IN_NARROW_WIDTH-1:0] in_fifo_dout;
  logic in_fifo_full;
  logic in_fifo_empty;
  logic in_fifo_wr_busy;
  logic in_fifo_rd_busy;
  logic [8:0] in_fifo_rd_count;
  logic in_fifo_rd_en;
  logic in_fifo_data_valid;
  logic in_fifo_overflow;
  logic in_fifo_underflow;

  logic configured;
  logic fft_transaction_active;
  logic xfft_config_ready;
  logic xfft_input_ready;
  logic xfft_output_valid;
  logic [31:0] xfft_output_data;
  logic xfft_output_last;
  logic event_frame_started;
  logic event_tlast_unexpected;
  logic event_tlast_missing;
  logic event_data_in_channel_halt;
  logic event_fft_overflow;

  logic [OUT_NARROW_WIDTH-1:0] out_fifo_din;
  logic [OUT_WIDE_WIDTH-1:0] out_fifo_dout;
  logic out_fifo_full;
  logic out_fifo_empty;
  logic out_fifo_overflow;
  logic out_fifo_underflow;
  logic out_fifo_wr_busy;
  logic out_fifo_rd_busy;
  logic out_fifo_rd_en;
  logic out_fifo_data_valid;

  for (genvar lane = 0; lane < 4; lane++) begin : g_pack_ingress
    always_comb begin
      in_fifo_din[lane*33+:32] = s_data[lane*32+:32];
      in_fifo_din[lane*33+32]  = s_transaction_end && (lane == 3);
    end
  end

  assign s_ready = rst_n && !in_fifo_full && !in_fifo_wr_busy;

  xpm_fifo_async #(
      .FIFO_MEMORY_TYPE("block"),
      .ECC_MODE("no_ecc"),
      .RELATED_CLOCKS(0),
      .SIM_ASSERT_CHK(0),
      .FIFO_WRITE_DEPTH(FIFO_WRITE_DEPTH),
      .WRITE_DATA_WIDTH(IN_WIDE_WIDTH),
      .WR_DATA_COUNT_WIDTH(7),
      .PROG_FULL_THRESH(FIFO_WRITE_DEPTH - 8),
      // Bit 12 enables data_valid.  The XPM default 0707 leaves that output
      // tied low, which would deadlock the FWFT read-side handshake below.
      .USE_ADV_FEATURES("1707"),
      .READ_MODE("fwft"),
      .FIFO_READ_LATENCY(0),
      .READ_DATA_WIDTH(IN_NARROW_WIDTH),
      .RD_DATA_COUNT_WIDTH(9),
      .PROG_EMPTY_THRESH(PREFILL_SAMPLES),
      .CDC_SYNC_STAGES(2),
      .DOUT_RESET_VALUE("0")
  ) u_ingress_fifo (
      .sleep        (1'b0),
      .rst          (!rst_n),
      .wr_clk       (clk_125),
      .wr_en        (s_valid && s_ready),
      .din          (in_fifo_din),
      .full         (in_fifo_full),
      .prog_full    (),
      .wr_data_count(),
      .overflow     (in_fifo_overflow),
      .wr_rst_busy  (in_fifo_wr_busy),
      .almost_full  (),
      .wr_ack       (),
      .rd_clk       (clk_500),
      .rd_en        (in_fifo_rd_en),
      .dout         (in_fifo_dout),
      .empty        (in_fifo_empty),
      .prog_empty   (),
      .rd_data_count(in_fifo_rd_count),
      .underflow    (in_fifo_underflow),
      .rd_rst_busy  (in_fifo_rd_busy),
      .almost_empty (),
      .data_valid   (in_fifo_data_valid),
      .injectsbiterr(1'b0),
      .injectdbiterr(1'b0),
      .sbiterr      (),
      .dbiterr      ()
  );

  always_ff @(posedge clk_500) begin
    if (reset500) begin
      configured <= 1'b0;
      fft_transaction_active <= 1'b0;
    end else begin
      if (!configured && xfft_config_ready) configured <= 1'b1;

      if (!fft_transaction_active && configured && !in_fifo_rd_busy && !out_fifo_wr_busy &&
          (in_fifo_rd_count >= PREFILL_SAMPLES))
        fft_transaction_active <= 1'b1;
      else if (in_fifo_rd_en && in_fifo_dout[32]) fft_transaction_active <= 1'b0;
    end
  end

  assign in_fifo_rd_en = !reset500 && !in_fifo_rd_busy && fft_transaction_active &&
      !in_fifo_empty && in_fifo_data_valid && xfft_input_ready;

  t03_xfft_2048_main u_xfft (
      .aclk(clk_500),
      .aresetn(!reset500),
      .s_axis_config_tdata(FORWARD_SCALE_CONFIG),
      .s_axis_config_tvalid(!reset500 && !configured),
      .s_axis_config_tready(xfft_config_ready),
      .s_axis_data_tdata(in_fifo_dout[31:0]),
      .s_axis_data_tvalid(!reset500 && !in_fifo_rd_busy && fft_transaction_active &&
                          !in_fifo_empty && in_fifo_data_valid),
      .s_axis_data_tready(xfft_input_ready),
      .s_axis_data_tlast(in_fifo_dout[32]),
      .m_axis_data_tdata(xfft_output_data),
      .m_axis_data_tvalid(xfft_output_valid),
      .m_axis_data_tlast(xfft_output_last),
      .event_frame_started(event_frame_started),
      .event_tlast_unexpected(event_tlast_unexpected),
      .event_tlast_missing(event_tlast_missing),
      .event_fft_overflow(event_fft_overflow),
      .event_data_in_channel_halt(event_data_in_channel_halt)
  );

  assign out_fifo_din = {xfft_output_last, xfft_output_data};

  xpm_fifo_async #(
      .FIFO_MEMORY_TYPE("block"),
      .ECC_MODE("no_ecc"),
      .RELATED_CLOCKS(0),
      .SIM_ASSERT_CHK(0),
      .FIFO_WRITE_DEPTH(256),
      .WRITE_DATA_WIDTH(OUT_NARROW_WIDTH),
      .WR_DATA_COUNT_WIDTH(9),
      .PROG_FULL_THRESH(224),
      // Keep data_valid enabled on the 33-to-132 FWFT gearbox as well.
      .USE_ADV_FEATURES("1707"),
      .READ_MODE("fwft"),
      .FIFO_READ_LATENCY(0),
      .READ_DATA_WIDTH(OUT_WIDE_WIDTH),
      .RD_DATA_COUNT_WIDTH(7),
      .PROG_EMPTY_THRESH(5),
      .CDC_SYNC_STAGES(2),
      .DOUT_RESET_VALUE("0")
  ) u_egress_fifo (
      .sleep        (1'b0),
      .rst          (reset500),
      .wr_clk       (clk_500),
      .wr_en        (!reset500 && xfft_output_valid && !out_fifo_full && !out_fifo_wr_busy),
      .din          (out_fifo_din),
      .full         (out_fifo_full),
      .prog_full    (),
      .wr_data_count(),
      .overflow     (out_fifo_overflow),
      .wr_rst_busy  (out_fifo_wr_busy),
      .almost_full  (),
      .wr_ack       (),
      .rd_clk       (clk_125),
      .rd_en        (out_fifo_rd_en),
      .dout         (out_fifo_dout),
      .empty        (out_fifo_empty),
      .prog_empty   (),
      .rd_data_count(),
      .underflow    (out_fifo_underflow),
      .rd_rst_busy  (out_fifo_rd_busy),
      .almost_empty (),
      .data_valid   (out_fifo_data_valid),
      .injectsbiterr(1'b0),
      .injectdbiterr(1'b0),
      .sbiterr      (),
      .dbiterr      ()
  );

  assign m_valid = rst_n && !out_fifo_empty && !out_fifo_rd_busy && out_fifo_data_valid;
  assign out_fifo_rd_en = m_valid && m_ready;

  for (genvar lane = 0; lane < 4; lane++) begin : g_unpack_egress
    always_comb m_data[lane*32+:32] = out_fifo_dout[lane*33+:32];
  end
  assign m_transaction_end =
      |{out_fifo_dout[131], out_fifo_dout[98], out_fifo_dout[65], out_fifo_dout[32]};

  always_ff @(posedge clk_500) begin
    if (reset500) begin
      egress_overflow <= 1'b0;
      ingress_underflow <= 1'b0;
      xfft_protocol_error <= 1'b0;
      xfft_overflow <= 1'b0;
    end else begin
      if (out_fifo_overflow || (xfft_output_valid && (out_fifo_full || out_fifo_wr_busy)))
        egress_overflow <= 1'b1;
      if (in_fifo_underflow) ingress_underflow <= 1'b1;
      if (event_tlast_unexpected || event_tlast_missing || event_data_in_channel_halt)
        xfft_protocol_error <= 1'b1;
      // XFFT v9.1 scaled fixed-point arithmetic wraps on overflow. Latch the
      // official event so wrapped data can never be accepted silently.
      if (event_fft_overflow) xfft_overflow <= 1'b1;
    end
  end

  always_ff @(posedge clk_125) begin
    if (!rst_n) begin
      ingress_overflow <= 1'b0;
      egress_underflow <= 1'b0;
    end else begin
      if (in_fifo_overflow) ingress_overflow <= 1'b1;
      if (out_fifo_underflow) egress_underflow <= 1'b1;
    end
  end
endmodule
