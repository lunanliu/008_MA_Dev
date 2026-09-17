// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:29:30 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t06_dds_phase_s32_sincos18/t06_dds_phase_s32_sincos18_stub.v
// Design      : t06_dds_phase_s32_sincos18
// Purpose     : Stub declaration of top-level module interface
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "dds_compiler_v6_0_21,Vivado 2021.1" *)
module t06_dds_phase_s32_sincos18(aclk, aresetn, s_axis_phase_tvalid, 
  s_axis_phase_tready, s_axis_phase_tdata, s_axis_phase_tuser, m_axis_data_tvalid, 
  m_axis_data_tready, m_axis_data_tdata, m_axis_data_tuser)
/* synthesis syn_black_box black_box_pad_pin="aclk,aresetn,s_axis_phase_tvalid,s_axis_phase_tready,s_axis_phase_tdata[31:0],s_axis_phase_tuser[32:0],m_axis_data_tvalid,m_axis_data_tready,m_axis_data_tdata[47:0],m_axis_data_tuser[32:0]" */;
  input aclk;
  input aresetn;
  input s_axis_phase_tvalid;
  output s_axis_phase_tready;
  input [31:0]s_axis_phase_tdata;
  input [32:0]s_axis_phase_tuser;
  output m_axis_data_tvalid;
  input m_axis_data_tready;
  output [47:0]m_axis_data_tdata;
  output [32:0]m_axis_data_tuser;
endmodule
