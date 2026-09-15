# Run as ordinary Tcl after open_checkpoint; loops are not XDC commands.
# m_ready belongs to clk150; other functional inputs remain clk125.
# IO timing remains excluded: the zero delay below labels the CDC source domain,
# and is not a board/shell timing budget or a CDC waiver.
set ins [get_ports -quiet -filter {DIRECTION == IN && NAME != clk125 && NAME != clk150 && NAME != clk500 && NAME != reset_request && NAME != m_ready}]
set_input_delay -clock [get_clocks clk125] -max 0.0 $ins
set_input_delay -clock [get_clocks clk125] -min 0.0 $ins
set ready150 [get_ports m_ready]
if {[llength $ready150]!=1} {error "One m_ready port required"}
set_input_delay -clock [get_clocks clk150] -max 0.0 $ready150
set_input_delay -clock [get_clocks clk150] -min 0.0 $ready150
set f [open [file join $out constraint_inventory.tsv] w]
puts $f "source\tdestination\tmax_delay_ns\tbus_skew_ns"
foreach {a b limit} {clk125 clk150 6.666666667 clk150 clk125 6.666666667 clk125 clk500 2.0 clk500 clk125 2.0 clk150 clk500 2.0 clk500 clk150 2.0} {
 if {[llength [get_clocks $a]]!=1 || [llength [get_clocks $b]]!=1} {error "Clock identity missing"}
 set_max_delay $limit -datapath_only -from [get_clocks $a] -to [get_clocks $b]
 # No broad clock-pair hold false path; preserve effective XPM max-delay coverage.
 set_bus_skew $limit -from [get_clocks $a] -to [get_clocks $b]
 puts $f "$a\t$b\t$limit\t$limit"
}
close $f
