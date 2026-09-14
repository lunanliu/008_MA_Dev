`timescale 1ns/1ps
module t06_fft_pair_extractor_fifo (
  input logic clk,rst,wr_en,rd_en,input logic [311:0] din,output wire [155:0] dout,
  output wire full,empty,wr_busy,rd_busy,data_valid,overflow,underflow,
  output wire [9:0] wr_count,output wire [10:0] rd_count
);
  xpm_fifo_sync #(
    .FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.SIM_ASSERT_CHK(0),
    .FIFO_WRITE_DEPTH(512),.WRITE_DATA_WIDTH(312),.READ_DATA_WIDTH(156),
    .WR_DATA_COUNT_WIDTH(10),.RD_DATA_COUNT_WIDTH(11),.PROG_FULL_THRESH(507),.PROG_EMPTY_THRESH(8),
    .READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.DOUT_RESET_VALUE("0"),.FULL_RESET_VALUE(0),
    .USE_ADV_FEATURES("1707"),.WAKEUP_TIME(0)
  ) fifo(
    .sleep(1'b0),.rst(rst),.wr_clk(clk),.wr_en(wr_en),.din(din),.full(full),.prog_full(),.wr_data_count(wr_count),
    .overflow(overflow),.wr_rst_busy(wr_busy),.almost_full(),.wr_ack(),.rd_en(rd_en),.dout(dout),.empty(empty),
    .prog_empty(),.rd_data_count(rd_count),.underflow(underflow),.rd_rst_busy(rd_busy),.almost_empty(),.data_valid(data_valid),
    .injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr());
  // Installed 2021.1 XPM FIFO built-in sleep/reset assertions have known
  // false startup reports at sleep=0. Keep explicit actual transaction checks.
  // synthesis translate_off
  always @(posedge clk) begin
    if((rst || wr_busy) && wr_en) $fatal(1,"PAIR FIFO write during reset/busy");
    if((rst || rd_busy) && rd_en) $fatal(1,"PAIR FIFO read during reset/busy");
    if(!rst && ((wr_en && full)||(rd_en && empty)||overflow||underflow)) $fatal(1,"PAIR FIFO overflow/underflow");
  end
  // synthesis translate_on
endmodule
