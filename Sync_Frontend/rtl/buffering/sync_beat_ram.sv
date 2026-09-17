`timescale 1ns/1ps
// Owned wrapper around the vendor XPM, one read and one write per cycle.
module sync_beat_ram #(
    parameter int ADDR_BITS = 11,
    parameter int DATA_BITS = 128,
    parameter int READ_LATENCY = 2
) (
    input logic clk, rst_n,
    input logic wr_valid,
    input logic [ADDR_BITS-1:0] wr_addr,
    input logic [DATA_BITS-1:0] wr_data,
    input logic rd_valid,
    input logic [ADDR_BITS-1:0] rd_addr,
    output logic rsp_valid,
    output logic [DATA_BITS-1:0] rsp_data
);
    logic [READ_LATENCY-1:0] read_pipe;
    always_ff @(posedge clk) begin
        if (!rst_n) read_pipe <= '0;
        else begin
            read_pipe[0] <= rd_valid;
            for (int k=1; k<READ_LATENCY; k++) read_pipe[k] <= read_pipe[k-1];
        end
    end
    assign rsp_valid = read_pipe[READ_LATENCY-1];
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_BITS), .ADDR_WIDTH_B(ADDR_BITS),
        .AUTO_SLEEP_TIME(0), .BYTE_WRITE_WIDTH_A(DATA_BITS),
        .CASCADE_HEIGHT(0), .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"), .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"), .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"), .MEMORY_SIZE(DATA_BITS*(1<<ADDR_BITS)),
        .MESSAGE_CONTROL(0), .READ_DATA_WIDTH_B(DATA_BITS),
        .READ_LATENCY_B(READ_LATENCY), .READ_RESET_VALUE_B("0"),
        .RST_MODE_B("SYNC"), .SIM_ASSERT_CHK(1),
        .USE_EMBEDDED_CONSTRAINT(0), .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"), .WRITE_DATA_WIDTH_A(DATA_BITS),
        .WRITE_MODE_B("read_first")
    ) memory (
        .dbiterrb(), .doutb(rsp_data), .sbiterrb(),
        .addra(wr_addr), .addrb(rd_addr), .clka(clk), .clkb(clk),
        .dina(wr_data), .ena(wr_valid), .enb(rd_valid),
        .injectdbiterra(1'b0), .injectsbiterra(1'b0),
        .regceb(1'b1), .rstb(!rst_n), .sleep(1'b0), .wea(wr_valid)
    );
endmodule
