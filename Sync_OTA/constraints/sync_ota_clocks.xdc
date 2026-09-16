# NI supplies all three clocks. Core OOC timing estimate only.
# No blanket asynchronous clock groups or false paths: XPM emits its scoped CDC constraints.
create_clock -name clk125 -period 8.000 [get_ports clk125]
create_clock -name clk150 -period 6.666666667 [get_ports clk150]
create_clock -name clk500 -period 2.000 [get_ports clk500]
