-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
-- Date        : Thu Sep 17 04:29:30 2026
-- Host        : ROG-Lunan running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t06_dds_phase_s32_sincos18/t06_dds_phase_s32_sincos18_stub.vhdl
-- Design      : t06_dds_phase_s32_sincos18
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xcvu11p-flgb2104-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity t06_dds_phase_s32_sincos18 is
  Port ( 
    aclk : in STD_LOGIC;
    aresetn : in STD_LOGIC;
    s_axis_phase_tvalid : in STD_LOGIC;
    s_axis_phase_tready : out STD_LOGIC;
    s_axis_phase_tdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s_axis_phase_tuser : in STD_LOGIC_VECTOR ( 32 downto 0 );
    m_axis_data_tvalid : out STD_LOGIC;
    m_axis_data_tready : in STD_LOGIC;
    m_axis_data_tdata : out STD_LOGIC_VECTOR ( 47 downto 0 );
    m_axis_data_tuser : out STD_LOGIC_VECTOR ( 32 downto 0 )
  );

end t06_dds_phase_s32_sincos18;

architecture stub of t06_dds_phase_s32_sincos18 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "aclk,aresetn,s_axis_phase_tvalid,s_axis_phase_tready,s_axis_phase_tdata[31:0],s_axis_phase_tuser[32:0],m_axis_data_tvalid,m_axis_data_tready,m_axis_data_tdata[47:0],m_axis_data_tuser[32:0]";
attribute x_core_info : string;
attribute x_core_info of stub : architecture is "dds_compiler_v6_0_21,Vivado 2021.1";
begin
end;
