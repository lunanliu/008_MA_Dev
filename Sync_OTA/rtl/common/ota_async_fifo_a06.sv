`timescale 1ns/1ps
// Record FIFO with writer-synchronous XPM reset and two-domain reset completion.
// Both clocks must run. Local async-assert/sync-release reset tails mask
// transfers immediately; raw requests never bypass these domain boundaries.
module ota_async_fifo #(
 parameter integer WIDTH=128,DEPTH=32,CW=$clog2(DEPTH)+1,CASCADE_HEIGHT=0
)(
 input wire wr_clk,rd_clk,reset_request,
 input wire s_valid,output wire s_ready,input wire [WIDTH-1:0] s_data,
 output wire m_valid,input wire m_ready,output wire [WIDTH-1:0] m_data,
 output wire wr_busy,rd_busy,output wire [CW-1:0] wr_count,rd_count,
 output wire overflow,underflow
);
 wire rw,rr,fifo_reset,wb,rb,full,empty,dv;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
  wr_reset(.src_arst(reset_request),.dest_clk(wr_clk),.dest_arst(rw));
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
  rd_reset(.src_arst(reset_request),.dest_clk(rd_clk),.dest_arst(rr));
 xpm_cdc_sync_rst #(.DEST_SYNC_FF(4),.INIT(1),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1))
  fifo_reset_sync(.src_rst(rw),.dest_clk(wr_clk),.dest_rst(fifo_reset));
 logic seen=0,complete=0,reader_ready=0;
 wire complete_rd,reader_ready_wr;
 always_ff @(posedge wr_clk or posedge rw)begin
  if(rw)begin seen<=0;complete<=0;end
  else begin
   if(fifo_reset&&wb)seen<=1;
   if(seen&&!fifo_reset&&!wb)complete<=1;
  end
 end
 xpm_cdc_single #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.SRC_INPUT_REG(0))
  completed_to_reader(.src_clk(wr_clk),.src_in(complete),.dest_clk(rd_clk),.dest_out(complete_rd));
 always_ff @(posedge rd_clk or posedge rr)begin
  if(rr)reader_ready<=0;
  else reader_ready<=complete_rd&&!rb;
 end
 xpm_cdc_single #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.SRC_INPUT_REG(0))
  ready_to_writer(.src_clk(rd_clk),.src_in(reader_ready),.dest_clk(wr_clk),.dest_out(reader_ready_wr));
 assign wr_busy=rw||fifo_reset||wb||!complete||!reader_ready_wr;
 assign rd_busy=rr||rb||!reader_ready;
 assign s_ready=!wr_busy&&!full;
 assign m_valid=!rd_busy&&!empty&&dv;
 xpm_fifo_async #(
  .FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.RELATED_CLOCKS(0),.SIM_ASSERT_CHK(1),
  .FIFO_WRITE_DEPTH(DEPTH),.WRITE_DATA_WIDTH(WIDTH),.READ_DATA_WIDTH(WIDTH),
  .WR_DATA_COUNT_WIDTH(CW),.RD_DATA_COUNT_WIDTH(CW),.PROG_FULL_THRESH(DEPTH-8),.PROG_EMPTY_THRESH(8),
  .FULL_RESET_VALUE(0),.USE_ADV_FEATURES("1707"),.READ_MODE("fwft"),.FIFO_READ_LATENCY(0),
  .DOUT_RESET_VALUE("0"),.CDC_SYNC_STAGES(2),.CASCADE_HEIGHT(CASCADE_HEIGHT)
 ) fifo(
  .sleep(1'b0),.rst(fifo_reset),.wr_clk(wr_clk),.wr_en(s_valid&&s_ready),.din(s_data),
  .full(full),.prog_full(),.wr_data_count(wr_count),.overflow(overflow),.wr_rst_busy(wb),.almost_full(),.wr_ack(),
  .rd_clk(rd_clk),.rd_en(m_valid&&m_ready),.dout(m_data),.empty(empty),.prog_empty(),.rd_data_count(rd_count),
  .underflow(underflow),.rd_rst_busy(rb),.almost_empty(),.data_valid(dv),
  .injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr()
 );
endmodule
