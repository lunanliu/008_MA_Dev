// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:25:05 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t04_cordic_translate_48/t04_cordic_translate_48_stub.v
// Design      : t04_cordic_translate_48
// Purpose     : Stub declaration of top-level module interface
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "cordic_v6_0_17,Vivado 2021.1" *)
module t04_cordic_translate_48(aclk, aresetn, s_axis_cartesian_tvalid, 
  s_axis_cartesian_tready, s_axis_cartesian_tdata, m_axis_dout_tvalid, m_axis_dout_tdata)
/* synthesis syn_black_box black_box_pad_pin="aclk,aresetn,s_axis_cartesian_tvalid,s_axis_cartesian_tready,s_axis_cartesian_tdata[95:0],m_axis_dout_tvalid,m_axis_dout_tdata[95:0]" */;
  input aclk;
  input aresetn;
  input s_axis_cartesian_tvalid;
  output s_axis_cartesian_tready;
  input [95:0]s_axis_cartesian_tdata;
  output m_axis_dout_tvalid;
  output [95:0]m_axis_dout_tdata;
endmodule
