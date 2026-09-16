`timescale 1ns / 1ps
// Official XPM storage; no custom FIFO memory. 2021.1 SVA compatibility is
// covered by explicit engine/TB reset, busy, overflow and underflow checks.
module sfo_initial_observation_engine_fifo #(
    parameter integer WIDTH = 96,
    DEPTH = 32
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             wr_en,
    input  logic             rd_en,
    input  logic [WIDTH-1:0] din,
    output wire  [WIDTH-1:0] dout,
    output wire              full,
    output wire              empty,
    output wire              wr_busy,
    output wire              rd_busy,
    output wire              overflow,
    output wire              underflow
);
  localparam integer COUNT_WIDTH = $clog2(DEPTH) + 1;
  xpm_fifo_sync #(
      .FIFO_MEMORY_TYPE("block"),
      .ECC_MODE("no_ecc"),
      .SIM_ASSERT_CHK(0),
      .FIFO_WRITE_DEPTH(DEPTH),
      .WRITE_DATA_WIDTH(WIDTH),
      .READ_DATA_WIDTH(WIDTH),
      .WR_DATA_COUNT_WIDTH(COUNT_WIDTH),
      .RD_DATA_COUNT_WIDTH(COUNT_WIDTH),
      .PROG_FULL_THRESH(DEPTH - 8),
      .PROG_EMPTY_THRESH(8),
      .READ_MODE("fwft"),
      .FIFO_READ_LATENCY(0),
      .DOUT_RESET_VALUE("0"),
      .FULL_RESET_VALUE(0),
      .USE_ADV_FEATURES("0707"),
      .WAKEUP_TIME(0)
  ) storage (
      .sleep        (1'b0),
      .rst          (rst),
      .wr_clk       (clk),
      .wr_en        (wr_en),
      .din          (din),
      .full         (full),
      .prog_full    (),
      .wr_data_count(),
      .overflow     (overflow),
      .wr_rst_busy  (wr_busy),
      .almost_full  (),
      .wr_ack       (),
      .rd_en        (rd_en),
      .dout         (dout),
      .empty        (empty),
      .prog_empty   (),
      .rd_data_count(),
      .underflow    (underflow),
      .rd_rst_busy  (rd_busy),
      .almost_empty (),
      .data_valid   (),
      .injectsbiterr(1'b0),
      .injectdbiterr(1'b0),
      .sbiterr      (),
      .dbiterr      ()
  );
`ifndef SYNTHESIS
  always @(posedge clk) begin
    if ((rst || wr_busy) && wr_en) $fatal(1, "Observation FIFO write during reset/busy");
    if ((rst || rd_busy) && rd_en) $fatal(1, "Observation FIFO read during reset/busy");
    if (!rst && ((wr_en && full) || (rd_en && empty) || overflow || underflow))
      $fatal(1, "Observation FIFO capacity/protocol invariant");
  end
`endif
endmodule
