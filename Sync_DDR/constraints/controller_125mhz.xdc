# Reference ONLY for ddr_read_ctrl selected as standalone top.
# Never activate both constraint sets on the same standalone clk port.
create_clock -name controller_clk -period 8.000000 [get_ports clk]
