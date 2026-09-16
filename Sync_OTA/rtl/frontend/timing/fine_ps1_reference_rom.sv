`timescale 1ns/1ps

module fine_ps1_reference_rom #(
  parameter string MEMORY_INIT_FILE = "fine_ps1_reference_16lane.mem",
  parameter int unsigned READ_LATENCY = 2
) (
  input  logic clk,
  input  logic rst_n,

  input  logic req_valid,
  output logic req_ready,
  input  logic [6:0] req_group,

  output logic rsp_valid,
  input  logic rsp_ready,
  output logic [6:0] rsp_group,
  output logic [15:0][15:0] rsp_i,
  output logic [15:0][15:0] rsp_q,
  output logic backpressure_error_sticky
);
  localparam int unsigned ROW_COUNT = 128;
  localparam int unsigned ROW_WIDTH = 512;

  logic [ROW_WIDTH-1:0] rom_row;
  logic [READ_LATENCY-1:0] valid_pipe;
  logic [6:0] group_pipe [0:READ_LATENCY-1];
  logic req_accept;

  initial begin
    if (READ_LATENCY != 2)
      $error("T05 PS1 reference ROM requires READ_LATENCY=2");
    if (MEMORY_INIT_FILE == "")
      $error("T05 PS1 reference ROM requires a production init file");
  end

  always_comb begin
    // Production correlation consumes one group every clock.  No output
    // storage is allowed to reduce this initiation interval.
    req_ready = rst_n;
    req_accept = req_valid && req_ready;
  end

  xpm_memory_sprom #(
    .ADDR_WIDTH_A(7),
    .AUTO_SLEEP_TIME(0),
    .CASCADE_HEIGHT(0),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE(MEMORY_INIT_FILE),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(ROW_COUNT*ROW_WIDTH),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_A(ROW_WIDTH),
    .READ_LATENCY_A(READ_LATENCY),
    .READ_RESET_VALUE_A("0"),
    .RST_MODE_A("SYNC"),
    .SIM_ASSERT_CHK(1),
    .USE_MEM_INIT(1),
    .WAKEUP_TIME("disable_sleep")
  ) u_ps1_reference_rom (
    .dbiterra(),.douta(rom_row),.sbiterra(),
    .addra(req_group),.clka(clk),.ena(req_accept),
    .injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regcea(1'b1),.rsta(!rst_n),.sleep(1'b0)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_pipe <= '0;
      for (int stage = 0; stage < READ_LATENCY; stage++)
        group_pipe[stage] <= '0;
      rsp_valid <= 1'b0;
      rsp_group <= '0;
      rsp_i <= '0;
      rsp_q <= '0;
      backpressure_error_sticky <= 1'b0;
    end else begin
      valid_pipe[0] <= req_accept;
      group_pipe[0] <= req_group;
      for (int stage = 1; stage < READ_LATENCY; stage++) begin
        valid_pipe[stage] <= valid_pipe[stage-1];
        group_pipe[stage] <= group_pipe[stage-1];
      end

      rsp_valid <= valid_pipe[READ_LATENCY-1];
      if (rsp_valid && !rsp_ready)
        backpressure_error_sticky <= 1'b1;

      if (valid_pipe[READ_LATENCY-1]) begin
        rsp_group <= group_pipe[READ_LATENCY-1];
        for (int unsigned lane = 0; lane < 16; lane++) begin
          rsp_i[lane] <= rom_row[lane*32 +: 16];
          rsp_q[lane] <= rom_row[lane*32+16 +: 16];
        end
      end
    end
  end
endmodule
