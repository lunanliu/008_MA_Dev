create_clock -name clk125 -period 8.000 [get_ports clk125]
create_clock -name clk150 -period 6.666666667 [get_ports clk150]
create_clock -name clk500 -period 2.000 [get_ports clk500]
set_property HD.CLK_SRC BUFGCE_X0Y0 [get_ports clk125]
set_property HD.CLK_SRC BUFGCE_X0Y1 [get_ports clk150]
set_property HD.CLK_SRC BUFGCE_X0Y2 [get_ports clk500]
# Standalone top IO excluded; no claim about shell/board IO timing.
set_false_path -from [get_ports -quiet -filter {DIRECTION == IN && NAME != clk125 && NAME != clk150 && NAME != clk500}]
set_false_path -to [get_ports -quiet -filter {DIRECTION == OUT}]
