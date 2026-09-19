# Reference for upload/capture/download selected as standalone top.
# NI integration must constrain its actual common SCTL clock and interfaces.
create_clock -name controller_clk -period 6.666667 [get_ports clk]
