# SF003: project-mode synthesis/implementation, run PRE hooks affect actual children.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc < 1} {error "Pass an independent output/attempt directory"}
set out [file normalize [lindex $argv 0]]
file mkdir $out
set ip_jobs 4
if {$argc > 1} {set ip_jobs [lindex $argv 1]}
if {![string is integer -strict $ip_jobs] || $ip_jobs<1 || $ip_jobs>16} {error "IP jobs range 1..16"}
proc require_run_complete {run step} {
    set status [get_property STATUS [get_runs $run]]
    puts "SYNC_RUN_STATUS $run $status"
    if {![string match "*$step Complete*" $status]} {error "Run $run not complete: $status"}
}
proc install_thread_hooks {root} {
    foreach run [get_runs] {
        foreach p [list_property $run] {
            if {[regexp {^STEPS\..+\.TCL\.PRE$} $p]} {
                set previous [get_property $p $run]
                set hook [file normalize [file join $root tools physical_run_pre.tcl]]
                if {$previous ne "" && [file normalize $previous] ne $hook && [file normalize $previous] ne [file normalize [file join $root tools run_threads.tcl]]} {error "Unrelated PRE preserved: $run $p"}
                set_property $p $hook $run
                if {[file normalize [get_property $p $run]] ne $hook} {error "PRE readback mismatch"}
            }
        }
    }
}
open_project [file join $root vivado Sync_Frontend Sync_Frontend.xpr]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e" || [get_property TOP [get_filesets sources_1]] ne "sync_frontend_top"} {error "Wrong project/top/part"}
source [file join $root tools run_threads.tcl]
set io_budget [file join $root constraints standalone_io_budget.xdc]
if {![llength [get_files -quiet $io_budget]]} {add_files -fileset constrs_1 -norecurse $io_budget}
set_property USED_IN_SIMULATION false [get_files $io_budget]
set_property -dict [list {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context} STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt] [get_runs synth_1]
# Work only with explicitly selected project IP. Do not rebuild completed IP runs.
set ip_pending {}
foreach ip [get_ips] {
    if {[get_property IS_LOCKED $ip]} {error "Locked managed IP $ip"}
    set name [get_property NAME $ip]
    set run ${name}_synth_1
    if {![llength [get_runs -quiet $run]]} {create_ip_run $ip}
    if {![llength [get_runs -quiet $run]]} {error "Missing OOC run $run"}
    if {![string match "*synth_design Complete*" [get_property STATUS [get_runs $run]]]} {lappend ip_pending $run}
}
install_thread_hooks $root
set f [open [file join $out actual_sources.txt] w]
foreach fs {sources_1 constrs_1 sim_autonomous} {
    puts $f "FILESET $fs"
    foreach p [get_files -of_objects [get_filesets $fs]] {puts $f $p}
}
close $f
set expected {}
set f [open [file join $root tools sf003_rtl_sources.txt] r]
foreach p [split [read $f] "\n"] {set p [string trim $p "\r\n\ufeff "]; if {$p ne ""} {lappend expected [file normalize [file join $root $p]]}}
close $f
set actual {}
foreach p [get_files -of_objects [get_filesets sources_1]] {if {[file extension $p] eq ".sv"} {lappend actual [file normalize $p]}}
if {[lsort $expected] ne [lsort $actual]} {error "Actual source set mismatch"}
puts "SF003_RESOURCE_REQUEST ip_jobs=$ip_jobs ceiling=16 general=8 synth=8"
if {[llength $ip_pending]} {
    launch_runs $ip_pending -jobs $ip_jobs
    foreach run $ip_pending {wait_on_run $run; require_run_complete $run synth_design}
}
if {![string match "*synth_design Complete*" [get_property STATUS [get_runs synth_1]]]} {
    launch_runs synth_1 -jobs 16
    wait_on_run synth_1
}
require_run_complete synth_1 synth_design
open_run synth_1
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "Synthesis contains black boxes"}
write_checkpoint -force [file join $out sync_frontend_synth.dcp]
write_edif -force [file join $out sync_frontend_top.edf]
set rf [open [file join $out reference_rom_init.txt] w]
set rom_nonzero 0
foreach cell [get_cells -quiet -hier -filter {NAME =~ *u_reference_rom*}] {
    foreach property [list_property $cell] {
        if {[regexp {^INIT_[0-9A-Fa-f]+$} $property]} {
            set value [get_property $property $cell]
            puts $rf "$cell $property $value"
            if {[regexp -nocase {'h[0]*[1-9a-f]} $value]} {incr rom_nonzero}
        }
    }
}
close $rf
puts "SF003_REFERENCE_ROM_NONZERO_INIT_FIELDS=$rom_nonzero"
report_utilization -hierarchical -file [file join $out synth_utilization.txt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out synth_timing.txt]
set f [open [file join $out synthesis_complete.txt] w]; puts $f "SF003_SYNTHESIS_COMPLETE PART=xcvu11p-flgb2104-2-e TOP=sync_frontend_top BLACKBOX=0"; close $f
close_design
if {![string match "*route_design Complete*" [get_property STATUS [get_runs impl_1]]]} {
    launch_runs impl_1 -to_step route_design -jobs 16
    wait_on_run impl_1
}
require_run_complete impl_1 route_design
open_run impl_1
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
if {$wns<0 || $whs<0 || $blacks!=0 || [llength $clks]!=1 || [llength $generators]!=0 || abs([get_property PERIOD $clks]-8.0)>0.001} {error "SF003_PHYSICAL_GATE_FAIL; preserve completed stages"}
puts "SF003_PHYSICAL_PASS WNS_NS=$wns WHS_NS=$whs; route/check_timing/DRC require Astra review"
close_project
