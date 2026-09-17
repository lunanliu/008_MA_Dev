// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:28:53 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t05_mult_quality_u46x36_full82/t05_mult_quality_u46x36_full82_stub.v
// Design      : t05_mult_quality_u46x36_full82
// Purpose     : Stub declaration of top-level module interface
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "mult_gen_v12_0_17,Vivado 2021.1" *)
module t05_mult_quality_u46x36_full82(CLK, A, B, P)
/* synthesis syn_black_box black_box_pad_pin="CLK,A[45:0],B[35:0],P[81:0]" */;
  input CLK;
  input [45:0]A;
  input [35:0]B;
  output [81:0]P;
endmodule
