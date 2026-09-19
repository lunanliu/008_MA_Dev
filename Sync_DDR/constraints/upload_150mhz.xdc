# Standalone reference clock only. NI integration must use the actual shared SCTL clock.
create_clock -name upload_clk -period 6.666667 [get_ports clk]
