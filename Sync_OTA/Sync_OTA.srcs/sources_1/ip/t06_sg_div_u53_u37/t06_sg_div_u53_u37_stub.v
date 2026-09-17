// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:32:59 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t06_sg_div_u53_u37/t06_sg_div_u53_u37_stub.v
// Design      : t06_sg_div_u53_u37
// Purpose     : Stub declaration of top-level module interface
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "div_gen_v5_1_18,Vivado 2021.1" *)
module t06_sg_div_u53_u37(aclk, aclken, aresetn, s_axis_divisor_tvalid, 
  s_axis_divisor_tdata, s_axis_dividend_tvalid, s_axis_dividend_tuser, 
  s_axis_dividend_tdata, m_axis_dout_tvalid, m_axis_dout_tuser, m_axis_dout_tdata)
/* synthesis syn_black_box black_box_pad_pin="aclk,aclken,aresetn,s_axis_divisor_tvalid,s_axis_divisor_tdata[39:0],s_axis_dividend_tvalid,s_axis_dividend_tuser[127:0],s_axis_dividend_tdata[55:0],m_axis_dout_tvalid,m_axis_dout_tuser[127:0],m_axis_dout_tdata[95:0]" */;
  input aclk;
  input aclken;
  input aresetn;
  input s_axis_divisor_tvalid;
  input [39:0]s_axis_divisor_tdata;
  input s_axis_dividend_tvalid;
  input [127:0]s_axis_dividend_tuser;
  input [55:0]s_axis_dividend_tdata;
  output m_axis_dout_tvalid;
  output [127:0]m_axis_dout_tuser;
  output [95:0]m_axis_dout_tdata;
endmodule
