`timescale 1ns/1ps
// Entire records cross together. rst is synchronized to the FIFO write clock.
// Both clocks must run during reset; no transfers until both busy flags clear.
module t10_cdc_fifo #(parameter integer WIDTH=128,DEPTH=1024,CW=$clog2(DEPTH)+1)(
 input logic wr_clk,rd_clk,reset_request,
 input logic s_valid,output logic s_ready,input logic [WIDTH-1:0] s_data,
 output logic m_valid,input logic m_ready,output logic [WIDTH-1:0] m_data,
 output logic [CW-1:0] wr_level,rd_level,wr_high_water,rd_high_water,
 output logic wr_reset_active,rd_reset_active,wr_error,rd_error
);
 // Source registers isolate busy generation and give each destination one CDC launch flop.
 wire rw,rr,wb,rb,rb_w,wb_r,full,empty,dv,ov,un;
 xpm_cdc_sync_rst #(.DEST_SYNC_FF(4),.INIT(1),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) wreset(.src_rst(reset_request),.dest_clk(wr_clk),.dest_rst(rw));
 xpm_cdc_sync_rst #(.DEST_SYNC_FF(4),.INIT(1),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1)) rreset(.src_rst(reset_request),.dest_clk(rd_clk),.dest_rst(rr));
 xpm_cdc_single #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(0),.SRC_INPUT_REG(1)) b0(.src_clk(rd_clk),.src_in(rb),.dest_clk(wr_clk),.dest_out(rb_w));
 xpm_cdc_single #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(1),.SIM_ASSERT_CHK(0),.SRC_INPUT_REG(1)) b1(.src_clk(wr_clk),.src_in(wb),.dest_clk(rd_clk),.dest_out(wb_r));
 assign wr_reset_active=rw||wb||rb_w;assign rd_reset_active=rr||rb||wb_r;
 assign s_ready=!wr_reset_active&&!full;assign m_valid=!rd_reset_active&&!empty&&dv;
 xpm_fifo_async #(.CDC_SYNC_STAGES(2),.RELATED_CLOCKS(0),.FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.SIM_ASSERT_CHK(1),
 .FIFO_WRITE_DEPTH(DEPTH),.WRITE_DATA_WIDTH(WIDTH),.READ_DATA_WIDTH(WIDTH),.WR_DATA_COUNT_WIDTH(CW),.RD_DATA_COUNT_WIDTH(CW),
 .PROG_FULL_THRESH(DEPTH-8),.PROG_EMPTY_THRESH(8),.FULL_RESET_VALUE(0),.USE_ADV_FEATURES("1707"),.READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.DOUT_RESET_VALUE("0"),.WAKEUP_TIME(0)) fifo(
 .sleep(1'b0),.rst(rw),.wr_clk(wr_clk),.rd_clk(rd_clk),.wr_en(s_valid&&s_ready),.din(s_data),.full(full),.prog_full(),.wr_data_count(wr_level),.overflow(ov),.wr_rst_busy(wb),.almost_full(),.wr_ack(),
 .rd_en(m_valid&&m_ready),.dout(m_data),.empty(empty),.prog_empty(),.rd_data_count(rd_level),.underflow(un),.rd_rst_busy(rb),.almost_empty(),.data_valid(dv),.injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr());
 always_ff @(posedge wr_clk)if(rw)begin wr_high_water<=0;wr_error<=0;end else begin if(wr_level>wr_high_water)wr_high_water<=wr_level;if(ov)wr_error<=1;end
 always_ff @(posedge rd_clk)if(rr)begin rd_high_water<=0;rd_error<=0;end else begin if(rd_level>rd_high_water)rd_high_water<=rd_level;if(un)rd_error<=1;end
endmodule
