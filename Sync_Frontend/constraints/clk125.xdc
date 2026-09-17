# SF001 baseline clock only; no external false paths or platform timing claim.
create_clock -name clk125 -period 8.000 [get_ports clk]
