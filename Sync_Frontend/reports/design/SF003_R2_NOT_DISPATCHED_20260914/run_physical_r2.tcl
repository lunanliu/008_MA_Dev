# SF003 R2: same XPR and completed synth_1, a new implementation run only.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 2} {error "args: preserved SF003 attempt, fresh R2 output directory"}
set preserved [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {[file exists $out]} {error "Fresh R2 output directory required"}
foreach name {synthesis_complete.txt sync_frontend_synth.dcp sync_frontend_top.edf} {
    if {![file exists [file join $preserved $name]]} {error "Missing preserved synthesis artifact $name"}
}
file mkdir $out
open_project [file join $root vivado Sync_Frontend Sync_Frontend.xpr]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e" || [get_property TOP [get_filesets sources_1]] ne "sync_frontend_top"} {error "Wrong part or top"}
source [file join $root tools run_threads.tcl]
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*synth_design Complete*" $synth_status]} {error "Reuse only completed synth_1; do not resynthesize"}
set expected {}
set f [open [file join $root tools sf003_rtl_sources.txt] r]
foreach p [split [read $f] "\n"] {set p [string trim $p "\r\n\ufeff "]; if {$p ne ""} {lappend expected [file normalize [file join $root $p]]}}
close $f
set actual {}
foreach p [get_files -of_objects [get_filesets sources_1]] {if {[file extension $p] eq ".sv"} {lappend actual [file normalize $p]}}
if {[lsort $actual] ne [lsort $expected]} {error "Actual RTL source set mismatch"}
set run impl_sf003_r2
set cs constrs_sf003_r2
if {[llength [get_runs -quiet $run]] || [llength [get_filesets -quiet $cs]]} {error "R2 run already exists: preserve it and repair/resume only necessary stage"}
create_fileset -constrset $cs
add_files -fileset $cs -norecurse [list [file join $root constraints clk125.xdc] [file join $root constraints standalone_io_budget_r2.xdc]]
create_run $run -parent_run synth_1 -part xcvu11p-flgb2104-2-e -flow {Vivado Implementation 2021} -strategy {Vivado Implementation Defaults} -constrset $cs
set_property -dict [list {STEPS.PLACE_DESIGN.ARGS.MORE OPTIONS} {-no_bufg_opt}] [get_runs $run]
foreach p [list_property [get_runs $run]] {
    if {[regexp {^STEPS\..+\.TCL\.PRE$} $p]} {set_property $p [file join $root tools physical_run_pre.tcl] [get_runs $run]}
}
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $root tools physical_r2_opt_pre.tcl] [get_runs $run]
set_property STEPS.PLACE_DESIGN.TCL.PRE [file join $root tools physical_r2_place_pre.tcl] [get_runs $run]
if {[get_property {STEPS.PLACE_DESIGN.ARGS.MORE OPTIONS} [get_runs $run]] ne "-no_bufg_opt"} {error "no_bufg_opt readback mismatch"}
set f [open [file join $out actual_sources.txt] w]
foreach fs [list sources_1 $cs sim_autonomous] {
    puts $f "FILESET $fs"
    foreach p [get_files -of_objects [get_filesets $fs]] {puts $f $p}
}
close $f
report_property [get_runs $run] -file [file join $out implementation_run_properties.txt]
puts "SF003_R2_REUSE synth_status=$synth_status parent=synth_1 run=$run general=8 synth=8 launch_jobs=16 native_resynthesis=0"
# New implementation consumes the existing synthesis DCP through the project parent.
launch_runs $run -to_step route_design -jobs 16
wait_on_run $run
set status [get_property STATUS [get_runs $run]]
if {![string match "*route_design Complete*" $status]} {error "R2 implementation incomplete: $status"}
open_run $run
write_checkpoint -force [file join $out sync_frontend_routed.dcp]
report_utilization -file [file join $out route_utilization.txt]
report_utilization -hierarchical -file [file join $out route_utilization_hierarchical.txt]
report_timing_summary -delay_type min_max -max_paths 50 -report_unconstrained -file [file join $out route_timing.txt]
report_timing -delay_type max -max_paths 30 -file [file join $out setup_paths.txt]
report_timing -delay_type min -max_paths 30 -file [file join $out hold_paths.txt]
report_route_status -file [file join $out route_status.txt]
report_clock_utilization -file [file join $out clock_utilization.txt]
report_clocks -file [file join $out clocks.txt]
report_cdc -details -file [file join $out cdc.txt]
check_timing -verbose -file [file join $out check_timing.txt]
report_drc -file [file join $out drc.txt]
report_methodology -file [file join $out methodology.txt]
report_high_fanout_nets -max_nets 50 -file [file join $out high_fanout.txt]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup]!=1 || [llength $hold]!=1} {error "Missing measured timing paths"}
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set blacks [llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]
set clks [get_clocks]
set generators [get_cells -quiet -hier -filter {REF_NAME =~ MMCME* || REF_NAME =~ PLLE*}]
set buffers [get_cells -quiet -hier -filter {REF_NAME =~ BUFG*}]
set f [open [file join $out physical_summary.txt] w]
foreach {k v} [list PART [get_property PART [current_design]] TOP [get_property NAME [current_design]] WNS_NS $wns WHS_NS $whs BLACKBOX $blacks CLOCK_COUNT [llength $clks] MMCM_PLL_COUNT [llength $generators] BUFG_COUNT [llength $buffers] IO_MAX_BUDGET_NS 1.0 PLATFORM_VERIFIED 0] {puts $f "$k=$v"}
close $f
if {$wns<0 || $whs<0 || $blacks!=0 || [llength $clks]!=1 || [llength $generators]!=0 || [llength $buffers]!=0 || abs([get_property PERIOD $clks]-8.0)>0.001} {error "SF003_R2_PHYSICAL_GATE_FAIL; preserve completed stages"}
puts "SF003_R2_PHYSICAL_NUMERIC_GATE_PASS WNS_NS=$wns WHS_NS=$whs; route/check_timing/DRC require Astra review"
write_xdc -force [file join $out applied_constraints.xdc]
close_project
