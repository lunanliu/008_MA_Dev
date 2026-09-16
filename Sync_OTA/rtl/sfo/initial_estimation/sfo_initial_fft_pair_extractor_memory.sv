`timescale 1ns / 1ps
module sfo_initial_fft_pair_extractor_memory (
    input  logic         clk,
    input  logic         rst,
    input  logic         wr_en,
    input  logic         rd_en,
    input  logic [  8:0] wr_addr,
    input  logic [  8:0] rd_addr,
    input  logic [127:0] wr_data,
    output wire  [127:0] rd_data
);
  xpm_memory_sdpram #(
      .ADDR_WIDTH_A(9),
      .ADDR_WIDTH_B(9),
      .AUTO_SLEEP_TIME(0),
      .BYTE_WRITE_WIDTH_A(128),
      .CLOCKING_MODE("common_clock"),
      .ECC_MODE("no_ecc"),
      .MEMORY_INIT_FILE("none"),
      .MEMORY_INIT_PARAM("0"),
      .MEMORY_OPTIMIZATION("true"),
      .MEMORY_PRIMITIVE("block"),
      .MEMORY_SIZE(65536),
      .MESSAGE_CONTROL(0),
      .READ_DATA_WIDTH_B(128),
      .READ_LATENCY_B(1),
      .READ_RESET_VALUE_B("0"),
      .RST_MODE_B("SYNC"),
      .SIM_ASSERT_CHK(1),
      .USE_EMBEDDED_CONSTRAINT(0),
      .USE_MEM_INIT(0),
      .WAKEUP_TIME("disable_sleep"),
      .WRITE_DATA_WIDTH_A(128),
      .WRITE_MODE_B("read_first")
  ) memory (
      .clka          (clk),
      .ena           (wr_en),
      .wea           (wr_en),
      .addra         (wr_addr),
      .dina          (wr_data),
      .injectsbiterra(1'b0),
      .injectdbiterra(1'b0),
      .clkb          (clk),
      .rstb          (rst),
      .enb           (rd_en),
      .regceb        (1'b1),
      .addrb         (rd_addr),
      .doutb         (rd_data),
      .sbiterrb      (),
      .dbiterrb      (),
      .sleep         (1'b0)
  );
  // synthesis translate_off
  always @(posedge clk) begin
    if (rst && (wr_en || rd_en)) $fatal(1, "PAIR memory access during reset");
    if (wr_en && rd_en && wr_addr == rd_addr) $fatal(1, "PAIR memory same-address alias");
  end
  // synthesis translate_on
endmodule
