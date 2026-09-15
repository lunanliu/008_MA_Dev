# Functional two-clock model; physical CDC and timing are separate gates.
create_clock -name clk_fast -period 2.000 [get_ports clk_fast]
create_clock -name clk_slow -period 6.667 [get_ports clk_slow]
# No blanket asynchronous false paths: preserve vendor XPM constraint intent.
