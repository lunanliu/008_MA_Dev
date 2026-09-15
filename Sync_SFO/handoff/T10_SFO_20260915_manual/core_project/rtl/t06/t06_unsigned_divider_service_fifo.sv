`timescale 1ns/1ps
// Official XPM BRAM FIFO, explicit protocol assertions retained.
module t06_unsigned_divider_service_fifo #(parameter integer WIDTH=79)(
    input logic clk,rst,wr_en,rd_en,
    input logic [WIDTH-1:0] din,output wire [WIDTH-1:0] dout,
    output wire full,empty,wr_busy,rd_busy,overflow,underflow
);
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.SIM_ASSERT_CHK(0),
        .FIFO_WRITE_DEPTH(32),.WRITE_DATA_WIDTH(WIDTH),.READ_DATA_WIDTH(WIDTH),
        .WR_DATA_COUNT_WIDTH(6),.RD_DATA_COUNT_WIDTH(6),.PROG_FULL_THRESH(24),.PROG_EMPTY_THRESH(8),
        .READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.DOUT_RESET_VALUE("0"),.FULL_RESET_VALUE(0),
        .USE_ADV_FEATURES("0707"),.WAKEUP_TIME(0)
    ) storage (
        .sleep(1'b0),.rst(rst),.wr_clk(clk),.wr_en(wr_en),.din(din),
        .full(full),.prog_full(),.wr_data_count(),.overflow(overflow),.wr_rst_busy(wr_busy),.almost_full(),.wr_ack(),
        .rd_en(rd_en),.dout(dout),.empty(empty),.prog_empty(),.rd_data_count(),.underflow(underflow),
        .rd_rst_busy(rd_busy),.almost_empty(),.data_valid(),.injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr());
    // synthesis translate_off
    always @(posedge clk) begin
        if ((rst || wr_busy) && wr_en) $fatal(1,"DIV FIFO write during reset/busy");
        if ((rst || rd_busy) && rd_en) $fatal(1,"DIV FIFO read during reset/busy");
        if (!rst && ((wr_en && full) || (rd_en && empty) || overflow || underflow))
            $fatal(1,"DIV FIFO overflow/underflow invariant");
    end
    // synthesis translate_on
endmodule
