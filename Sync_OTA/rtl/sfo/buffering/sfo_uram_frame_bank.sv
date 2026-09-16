`timescale 1ns / 1ps

module sfo_uram_frame_bank #(
    parameter int unsigned BEAT_WIDTH  = 128,
    parameter int unsigned DEPTH_BEATS = 335_872,
    parameter int unsigned ADDR_WIDTH  = 19
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [BEAT_WIDTH-1:0] wr_data,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [BEAT_WIDTH-1:0] rd_data
);
  initial begin
    if ((1 << ADDR_WIDTH) < DEPTH_BEATS) $error("ADDR_WIDTH cannot address DEPTH_BEATS");
  end

  xpm_memory_sdpram #(
      .ADDR_WIDTH_A(ADDR_WIDTH),
      .ADDR_WIDTH_B(ADDR_WIDTH),
      .AUTO_SLEEP_TIME(0),
      .BYTE_WRITE_WIDTH_A(BEAT_WIDTH),
      .CASCADE_HEIGHT(0),
      .CLOCKING_MODE("common_clock"),
      .ECC_MODE("no_ecc"),
      .MEMORY_INIT_FILE("none"),
      .MEMORY_INIT_PARAM("0"),
      .MEMORY_OPTIMIZATION("true"),
      .MEMORY_PRIMITIVE("ultra"),
      .MEMORY_SIZE(BEAT_WIDTH * DEPTH_BEATS),
      .MESSAGE_CONTROL(0),
      .READ_DATA_WIDTH_B(BEAT_WIDTH),
      .READ_LATENCY_B(2),
      .READ_RESET_VALUE_B("0"),
      .RST_MODE_B("SYNC"),
      .SIM_ASSERT_CHK(1),
      .USE_EMBEDDED_CONSTRAINT(0),
      .USE_MEM_INIT(0),
      .WAKEUP_TIME("disable_sleep"),
      .WRITE_DATA_WIDTH_A(BEAT_WIDTH),
      .WRITE_MODE_B("read_first")
  ) u_frame_memory (
      .dbiterrb      (),
      .doutb         (rd_data),
      .sbiterrb      (),
      .addra         (wr_addr),
      .addrb         (rd_addr),
      .clka          (clk),
      .clkb          (clk),
      .dina          (wr_data),
      .ena           (wr_en),
      .enb           (rd_en),
      .injectdbiterra(1'b0),
      .injectsbiterra(1'b0),
      .regceb        (1'b1),
      .rstb          (rst),
      .sleep         (1'b0),
      .wea           (wr_en)
  );
endmodule
