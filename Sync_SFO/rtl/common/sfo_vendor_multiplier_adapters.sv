`timescale 1ns / 1ps

// Multiplier Generator 12.0 native interfaces have no valid ports.  These
// thin adapters bind the measured Vivado-2021.1 latencies to ready/valid
// control used by the T05 controllers.  Arithmetic remains inside official
// AMD/Xilinx IP instances.

module sfo_square18_vendor_adapter (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               req_valid,
    input  logic signed [17:0] req_operand,
    output logic               rsp_valid,
    output logic        [35:0] rsp_square
);
  localparam int unsigned LATENCY = 3;
  logic [LATENCY-1:0] valid_pipe;
  logic signed [35:0] product;

  t05_mult_s18x18_full36 u_mult (
      .CLK(clk),
      .A  (req_operand),
      .B  (req_operand),
      .P  (product)
  );
  assign rsp_valid  = valid_pipe[LATENCY-1];
  assign rsp_square = product;

  always_ff @(posedge clk) begin
    if (!rst_n) valid_pipe <= '0;
    else begin
      valid_pipe[0] <= req_valid;
      for (int stage = 1; stage < LATENCY; stage++) valid_pipe[stage] <= valid_pipe[stage-1];
    end
  end
endmodule

module sfo_square48_vendor_adapter (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               req_valid,
    input  logic signed [47:0] req_operand,
    output logic               rsp_valid,
    output logic        [95:0] rsp_square
);
  localparam int unsigned LATENCY = 6;
  logic [LATENCY-1:0] valid_pipe;
  logic signed [95:0] product;

  t05_mult_s48x48_full96 u_mult (
      .CLK(clk),
      .A  (req_operand),
      .B  (req_operand),
      .P  (product)
  );
  assign rsp_valid  = valid_pipe[LATENCY-1];
  assign rsp_square = product;

  always_ff @(posedge clk) begin
    if (!rst_n) valid_pipe <= '0;
    else begin
      valid_pipe[0] <= req_valid;
      for (int stage = 1; stage < LATENCY; stage++) valid_pipe[stage] <= valid_pipe[stage-1];
    end
  end
endmodule

module sfo_cfo_scale_vendor_adapter (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               req_valid,
    input  logic signed [18:0] req_a,
    input  logic signed [39:0] req_b,
    output logic               rsp_valid,
    output logic signed [58:0] rsp_product
);
  localparam int unsigned LATENCY = 6;
  logic [LATENCY-1:0] valid_pipe;

  t05_mult_cfo_s19_const40_full59 u_mult (
      .CLK(clk),
      .A  (req_a),
      .B  (req_b),
      .P  (rsp_product)
  );
  assign rsp_valid = valid_pipe[LATENCY-1];

  always_ff @(posedge clk) begin
    if (!rst_n) valid_pipe <= '0;
    else begin
      valid_pipe[0] <= req_valid;
      for (int stage = 1; stage < LATENCY; stage++) valid_pipe[stage] <= valid_pipe[stage-1];
    end
  end
endmodule
