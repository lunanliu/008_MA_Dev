// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:22:50 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/farrow_add_28/farrow_add_28_stub.v
// Design      : farrow_add_28
// Purpose     : Stub declaration of top-level module interface
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "c_addsub_v12_0_14,Vivado 2021.1" *)
module farrow_add_28(A, B, CLK, ADD, SCLR, S)
/* synthesis syn_black_box black_box_pad_pin="A[27:0],B[27:0],CLK,ADD,SCLR,S[27:0]" */;
  input [27:0]A;
  input [27:0]B;
  input CLK;
  input ADD;
  input SCLR;
  output [27:0]S;
endmodule
