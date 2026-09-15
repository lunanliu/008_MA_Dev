`timescale 1ns/1ps
// Single-clock ready/valid FIFO. Only rst cancels a pending transfer.
module t07_sync_fifo #(
  parameter int unsigned WIDTH=225,
  parameter int unsigned DEPTH=64,
  parameter int unsigned COUNT_WIDTH=$clog2(DEPTH)+1
)(
  input logic clk,rst,
  input logic s_valid,output logic s_ready,input logic [WIDTH-1:0] s_data,
  output logic m_valid,input logic m_ready,output logic [WIDTH-1:0] m_data,
  output logic [COUNT_WIDTH-1:0] level,high_water,
  output logic reset_busy,error_sticky
);
  wire full,empty,wr_busy,rd_busy,data_valid,overflow,underflow;
  assign reset_busy=rst || wr_busy || rd_busy;
  assign s_ready=!reset_busy && !full;
  assign m_valid=!reset_busy && !empty && data_valid;
  xpm_fifo_sync #(
    .FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.SIM_ASSERT_CHK(1),
    .FIFO_WRITE_DEPTH(DEPTH),.WRITE_DATA_WIDTH(WIDTH),.READ_DATA_WIDTH(WIDTH),
    .WR_DATA_COUNT_WIDTH(COUNT_WIDTH),.RD_DATA_COUNT_WIDTH(COUNT_WIDTH),
    .PROG_FULL_THRESH(DEPTH-8),.PROG_EMPTY_THRESH(8),.FULL_RESET_VALUE(0),
    .USE_ADV_FEATURES("1707"),.READ_MODE("fwft"),.FIFO_READ_LATENCY(0),
    .DOUT_RESET_VALUE("0"),.WAKEUP_TIME(0)
  ) memory(
    .sleep(1'b0),.rst(rst),.wr_clk(clk),.wr_en(s_valid && s_ready),.din(s_data),
    .full(full),.prog_full(),.wr_data_count(level),.overflow(overflow),
    .wr_rst_busy(wr_busy),.almost_full(),.wr_ack(),
    .rd_en(m_valid && m_ready),.dout(m_data),.empty(empty),.prog_empty(),
    .rd_data_count(),.underflow(underflow),.rd_rst_busy(rd_busy),.almost_empty(),
    .data_valid(data_valid),.injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr());
  always_ff @(posedge clk)begin
    if(rst)begin high_water<='0;error_sticky<=1'b0;end
    else begin
      if(level>high_water)high_water<=level;
      if(overflow || underflow)error_sticky<=1'b1;
    end
  end
  // synthesis translate_off
  initial if(DEPTH<32 || (DEPTH&(DEPTH-1))!=0)$fatal(1,"FIFO power-of-two depth >=32 required");
  // synthesis translate_on
endmodule
