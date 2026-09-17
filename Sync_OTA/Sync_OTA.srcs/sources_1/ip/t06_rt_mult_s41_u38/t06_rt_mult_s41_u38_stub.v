// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:31:34 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t06_rt_mult_s41_u38/t06_rt_mult_s41_u38_stub.v
// Design      : t06_rt_mult_s41_u38
// Purpose     : Stub declaration of top-level module interface
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "mult_gen_v12_0_17,Vivado 2021.1" *)
module t06_rt_mult_s41_u38(CLK, A, B, SCLR, P)
/* synthesis syn_black_box black_box_pad_pin="CLK,A[40:0],B[37:0],SCLR,P[78:0]" */;
  input CLK;
  input [40:0]A;
  input [37:0]B;
  input SCLR;
  output [78:0]P;
endmodule
