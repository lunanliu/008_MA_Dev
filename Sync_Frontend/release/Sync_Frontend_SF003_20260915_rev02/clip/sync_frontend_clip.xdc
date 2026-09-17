# The NI target supplies and constrains the free-running 125 MHz clk125.
# Use that same clock for CLIP I/O and its LabVIEW SCTL.
# This package does not impose standalone I/O delays, pin LOCs or false paths.
# Verify real clock propagation, reset/CDC and all interface timing in the NI Target compile.
