-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
-- Date        : Thu Sep 17 04:33:51 2026
-- Host        : ROG-Lunan running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t07_g3_down15/t07_g3_down15_stub.vhdl
-- Design      : t07_g3_down15
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xcvu11p-flgb2104-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity t07_g3_down15 is
  Port ( 
    aresetn : in STD_LOGIC;
    aclk : in STD_LOGIC;
    s_axis_data_tvalid : in STD_LOGIC;
    s_axis_data_tready : out STD_LOGIC;
    s_axis_data_tdata : in STD_LOGIC_VECTOR ( 255 downto 0 );
    m_axis_data_tvalid : out STD_LOGIC;
    m_axis_data_tready : in STD_LOGIC;
    m_axis_data_tdata : out STD_LOGIC_VECTOR ( 191 downto 0 )
  );

end t07_g3_down15;

architecture stub of t07_g3_down15 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "aresetn,aclk,s_axis_data_tvalid,s_axis_data_tready,s_axis_data_tdata[255:0],m_axis_data_tvalid,m_axis_data_tready,m_axis_data_tdata[191:0]";
attribute x_core_info : string;
attribute x_core_info of stub : architecture is "fir_compiler_v7_2_16,Vivado 2021.1";
begin
end;
