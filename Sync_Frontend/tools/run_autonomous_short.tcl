set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root vivado Sync_Frontend Sync_Frontend.xpr]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
source [file join $root tools run_threads.tcl]
set additions {rtl/buffering/sync_beat_ram.sv rtl/timing/sync_rolling_metric.sv rtl/frontend/sync_continuous_detector.sv rtl/frontend/sync_frontend_top.sv}
foreach rel $additions {
    set p [file normalize [file join $root $rel]]
    if {![llength [get_files -quiet $p]]} {add_files -norecurse $p}
}
if {![llength [get_filesets -quiet sim_autonomous]]} {create_fileset -simset sim_autonomous}
foreach rel {sim/tb/sync_passive_checker.sv sim/tb/sync_frontend_tb.sv} {
    set p [file normalize [file join $root $rel]]
    if {![llength [get_files -quiet -of_objects [get_filesets sim_autonomous] $p]]} {add_files -fileset sim_autonomous -norecurse $p}
}
set_property top sync_frontend_top [get_filesets sources_1]
set_property top sync_frontend_tb [get_filesets sim_autonomous]
set_property xsim.elaborate.mt_level 16 [get_filesets sim_autonomous]
set_property xsim.elaborate.debug_level all [get_filesets sim_autonomous]
set_property xsim.simulate.runtime all [get_filesets sim_autonomous]
set opts "-testplusarg STREAM_BEATS=15081 -testplusarg STREAM_MEM=[file join $root sim data autonomous_stream.mem] -testplusarg TRUTH_MEM=[file join $root sim data autonomous_truth.mem]"
set_property -dict [list xsim.simulate.xsim.more_options $opts] [get_filesets sim_autonomous]
set simdir [file join $root vivado Sync_Frontend Sync_Frontend.sim sim_autonomous behav xsim]
file mkdir $simdir
file copy -force [file join $root ip rom fine_ps1_reference_16lane.mem] [file join $simdir fine_ps1_reference_16lane.mem]
foreach run [get_runs] {
    foreach p [list_property $run] {
        if {[regexp {^STEPS\..+\.TCL\.PRE$} $p]} {set_property $p [file join $root tools run_threads.tcl] $run}
    }
}
update_compile_order -fileset sources_1
update_compile_order -fileset sim_autonomous
set expected {}
set f [open [file join $root tools rtl_sources.txt] r]
foreach line [split [read $f] "\n"] {
    set line [string trim $line "\r\n\ufeff "]
    if {$line ne ""} {lappend expected [file normalize [file join $root $line]]}
}
close $f
foreach rel $additions {lappend expected [file normalize [file join $root $rel]]}
set actual {}
foreach p [get_files -of_objects [get_filesets sources_1]] {if {[file extension $p] eq ".sv"} {lappend actual [file normalize $p]}}
if {[lsort $expected] ne [lsort $actual]} {error "SF002 actual RTL mismatch"}
set f [open [file join $root reports SF002_actual_sources.txt] w]
foreach fs {sources_1 sim_autonomous constrs_1} {
    puts $f "FILESET $fs"
    foreach p [get_files -of_objects [get_filesets $fs]] {puts $f $p}
}
close $f
report_ip_status -file [file join $root reports SF002_ip_status.txt]
launch_simulation -simset sim_autonomous -mode behavioral
close_sim
close_project
puts "SF002_SIMULATION_RETURNED_REQUIRE_PASSIVE_AND_MAIN_AND_SESSION_MARKERS"
