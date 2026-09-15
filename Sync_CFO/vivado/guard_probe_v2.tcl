# No synthesis, compile, RTL simulation or T10 project access in this probe.
set root [file normalize [file join [file dirname [info script]] ..]]
if {[llength $argv]!=1} {error "Specify normal, error or hold"}
set mode [lindex $argv 0]
if {$mode ni {normal error hold}} {error "Invalid guard probe mode"}
open_project [file join $root vivado CFO_SYNC CFO_SYNC.xpr]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
if {[get_property TOP [get_filesets sources_1]] ne "cfo_rotate4" || [get_property TOP [get_filesets sim_1]] ne "cfo_rotate4_tb"} {error "Wrong source scope"}
source [file join $root vivado run_threads.tcl]
puts "CFO_GUARD_READY mode=$mode pid=[pid] milliseconds=[clock milliseconds]"
flush stdout
switch -- $mode {
 normal {close_project;puts "CFO_GUARD_NORMAL_END";flush stdout;exit 0}
 error {close_project;puts stderr "CFO_GUARD_EXPECTED_ERROR";flush stderr;exit 7}
 hold {after 600000;error "Guard failed to terminate this intentionally idle probe"}
}