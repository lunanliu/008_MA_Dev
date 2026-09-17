-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
-- Date        : Thu Sep 17 04:28:53 2026
-- Host        : ROG-Lunan running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t05_mult_quality_u46x36_full82/t05_mult_quality_u46x36_full82_stub.vhdl
-- Design      : t05_mult_quality_u46x36_full82
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xcvu11p-flgb2104-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity t05_mult_quality_u46x36_full82 is
  Port ( 
    CLK : in STD_LOGIC;
    A : in STD_LOGIC_VECTOR ( 45 downto 0 );
    B : in STD_LOGIC_VECTOR ( 35 downto 0 );
    P : out STD_LOGIC_VECTOR ( 81 downto 0 )
  );

end t05_mult_quality_u46x36_full82;

architecture stub of t05_mult_quality_u46x36_full82 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "CLK,A[45:0],B[35:0],P[81:0]";
attribute x_core_info : string;
attribute x_core_info of stub : architecture is "mult_gen_v12_0_17,Vivado 2021.1";
begin
end;
