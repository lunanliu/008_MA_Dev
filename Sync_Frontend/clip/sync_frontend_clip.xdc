# NI owns the real clk125 net and its 8 ns constraint via the CLIP clock port.
# There is no generated clock, MMCM, or asynchronous data-domain crossing.
# This assertion checks inherited timing; it does not create a fictitious clock.
set sync_frontend_clock_pin [get_pins -quiet {%ClipInstancePath%/implementation/clk}]
if {[llength $sync_frontend_clock_pin] != 1} {error "Cannot locate frontend inherited clock pin"}
set sync_frontend_clocks [get_clocks -quiet -of_objects $sync_frontend_clock_pin]
if {[llength $sync_frontend_clocks] != 1} {error "Frontend must inherit one NI 125 MHz clock"}
if {abs([get_property PERIOD $sync_frontend_clocks]-8.0)>0.001} {error "Frontend NI clock must be 125 MHz"}
# ASYNC_REG attributes for the reset release chain are retained in the EDIF.
# Deliberately no OOC I/O budgets, LOC constraints, blanket false paths, or CDC cuts.
