// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:25:45 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t03_xfft_16384_aux/t03_xfft_16384_aux_stub.v
// Design      : t03_xfft_16384_aux
// Purpose     : Stub declaration of top-level module interface
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "xfft_v9_1_6,Vivado 2021.1" *)
module t03_xfft_16384_aux(aclk, aresetn, s_axis_config_tdata, 
  s_axis_config_tvalid, s_axis_config_tready, s_axis_data_tdata, s_axis_data_tvalid, 
  s_axis_data_tready, s_axis_data_tlast, m_axis_data_tdata, m_axis_data_tuser, 
  m_axis_data_tvalid, m_axis_data_tlast, m_axis_status_tdata, m_axis_status_tvalid, 
  event_frame_started, event_tlast_unexpected, event_tlast_missing, event_fft_overflow, 
  event_data_in_channel_halt)
/* synthesis syn_black_box black_box_pad_pin="aclk,aresetn,s_axis_config_tdata[23:0],s_axis_config_tvalid,s_axis_config_tready,s_axis_data_tdata[31:0],s_axis_data_tvalid,s_axis_data_tready,s_axis_data_tlast,m_axis_data_tdata[31:0],m_axis_data_tuser[7:0],m_axis_data_tvalid,m_axis_data_tlast,m_axis_status_tdata[7:0],m_axis_status_tvalid,event_frame_started,event_tlast_unexpected,event_tlast_missing,event_fft_overflow,event_data_in_channel_halt" */;
  input aclk;
  input aresetn;
  input [23:0]s_axis_config_tdata;
  input s_axis_config_tvalid;
  output s_axis_config_tready;
  input [31:0]s_axis_data_tdata;
  input s_axis_data_tvalid;
  output s_axis_data_tready;
  input s_axis_data_tlast;
  output [31:0]m_axis_data_tdata;
  output [7:0]m_axis_data_tuser;
  output m_axis_data_tvalid;
  output m_axis_data_tlast;
  output [7:0]m_axis_status_tdata;
  output m_axis_status_tvalid;
  output event_frame_started;
  output event_tlast_unexpected;
  output event_tlast_missing;
  output event_fft_overflow;
  output event_data_in_channel_halt;
endmodule
