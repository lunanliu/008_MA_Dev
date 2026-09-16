`timescale 1ns / 1ps
module sfo_initial_observation_store_bank (
    input  logic         clk,
    input  logic         rst,
    input  logic         write_enable,
    input  logic         read_enable,
    input  logic [ 11:0] write_address,
    input  logic [ 11:0] read_address,
    input  logic [144:0] write_data,
    output wire  [144:0] read_data
);
  xpm_memory_sdpram #(
      .ADDR_WIDTH_A(12),
      .ADDR_WIDTH_B(12),
      .AUTO_SLEEP_TIME(0),
      .BYTE_WRITE_WIDTH_A(145),
      .CLOCKING_MODE("common_clock"),
      .ECC_MODE("no_ecc"),
      .MEMORY_INIT_FILE("none"),
      .MEMORY_INIT_PARAM("0"),
      .MEMORY_OPTIMIZATION("true"),
      .MEMORY_PRIMITIVE("block"),
      .MEMORY_SIZE(593920),
      .MESSAGE_CONTROL(0),
      .READ_DATA_WIDTH_B(145),
      .READ_LATENCY_B(2),
      .READ_RESET_VALUE_B("0"),
      .RST_MODE_B("SYNC"),
      .SIM_ASSERT_CHK(1),
      .USE_EMBEDDED_CONSTRAINT(0),
      .USE_MEM_INIT(0),
      .WAKEUP_TIME("disable_sleep"),
      .WRITE_DATA_WIDTH_A(145),
      .WRITE_MODE_B("read_first")
  ) memory (
      .clka          (clk),
      .ena           (write_enable),
      .wea           (write_enable),
      .addra         (write_address),
      .dina          (write_data),
      .injectsbiterra(1'b0),
      .injectdbiterra(1'b0),
      .clkb          (clk),
      .rstb          (rst),
      .enb           (read_enable),
      .regceb        (1'b1),
      .addrb         (read_address),
      .doutb         (read_data),
      .sbiterrb      (),
      .dbiterrb      (),
      .sleep         (1'b0)
  );
  // synthesis translate_off
  always @(posedge clk) begin
    if (rst && (write_enable || read_enable)) $fatal(1, "STORE bank active during reset");
    if (write_enable && write_address >= 3280) $fatal(1, "STORE write outside logical bank");
    if (read_enable && read_address >= 3280) $fatal(1, "STORE read outside logical bank");
    if (write_enable && read_enable && write_address == read_address)
      $fatal(1, "STORE same-address read/write alias");
  end
  // synthesis translate_on
endmodule
