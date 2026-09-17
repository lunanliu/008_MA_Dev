# CLIP clock is supplied and constrained by the NI target through clk125.
# Select the same free-running 125 MHz clock for the CLIP and its SCTL.
# ASYNC_REG attributes and IP structure are preserved in the core netlist.
# No standalone IO budget, LOC, clock creation, or blanket false path belongs here.
# Runtime assertions use ordinary Tcl in check_dcp_release.tcl, not XDC if commands.
