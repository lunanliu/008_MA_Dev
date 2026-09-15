# Root clock declarations only; NOT complete I/O/CDC/NI implementation qualification.
create_clock -name clk125 -period 8.000 [get_ports clk125]
create_clock -name clk150 -period 6.666666667 [get_ports clk150]
create_clock -name clk500 -period 2.000 [get_ports clk500]
