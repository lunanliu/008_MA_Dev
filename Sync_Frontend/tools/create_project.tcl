# One explicit project; no recursive source collection. Run by assigned Luna only.
set root [file normalize [file join [file dirname [info script]] ..]]
proc read_lines {path} {
    set f [open $path r]; set s [read $f]; close $f
    set out {}
    foreach line [split $s "\n"] {set line [string trim $line "\r\n\ufeff "]; if {$line ne ""} {lappend out $line}}
    return $out
}
set project_dir [file join $root vivado Sync_Frontend]
if {[file exists [file join $project_dir Sync_Frontend.xpr]]} {error "Existing XPR preserved; reopen it instead of recreating"}
create_project Sync_Frontend $project_dir -part xcvu11p-flgb2104-2-e
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_MEMORY XPM_FIFO} [current_project]
set expected {}
foreach rel [read_lines [file join $root tools rtl_sources.txt]] {
    set p [file normalize [file join $root $rel]]
    if {![file isfile $p]} {error "Missing source $p"}
    add_files -norecurse $p
    lappend expected $p
}
set ipfiles {}
foreach rel [read_lines [file join $root tools ip_sources.txt]] {lappend ipfiles [file join $root $rel]}
# Official import writes managed copies; baseline XCI is immutable provenance.
import_ip -files $ipfiles
add_files -norecurse [file join $root ip rom fine_ps1_reference_16lane.mem]
add_files -fileset constrs_1 -norecurse [file join $root constraints clk125.xdc]
add_files -fileset sim_1 -norecurse [file join $root sim tb coarse_baseline_equivalence_tb.sv]
set_property top to_coarse_ports [get_filesets sources_1]
set_property top coarse_baseline_equivalence_tb [get_filesets sim_1]
set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]
set_property xsim.elaborate.debug_level all [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set opts "-testplusarg SMOKE_ONLY -testplusarg OUTAGE_CASE0_27 -testplusarg OUTAGE_CASE1_29"
foreach {arg name} {STIMULUS_MEM stimulus_beats.mem METRICS_MEM expected_metrics.mem RESULTS_MEM expected_results.mem} {
    append opts " -testplusarg $arg=[file join $root sim data $name]"
}
set_property -dict [list xsim.simulate.xsim.more_options $opts] [get_filesets sim_1]
source [file join $root tools run_threads.tcl]
foreach run [get_runs] {
    foreach property [list_property $run] {
        if {[regexp {^STEPS\..+\.TCL\.PRE$} $property]} {set_property $property [file join $root tools run_threads.tcl] $run}
    }
}
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set actual {}
foreach f [get_files -of_objects [get_filesets sources_1]] {
    if {[file extension $f] eq ".sv"} {lappend actual [file normalize $f]}
}
if {[lsort $actual] ne [lsort $expected]} {error "Actual RTL set differs from frozen list"}
set f [open [file join $root reports SF001_actual_sources.txt] w]
foreach fs {sources_1 sim_1 constrs_1} {
    puts $f "FILESET $fs"; if {$fs ne "constrs_1"} {puts $f "TOP [get_property TOP [get_filesets $fs]]"}
    foreach p [get_files -of_objects [get_filesets $fs]] {puts $f $p}
}
close $f
report_ip_status -file [file join $root reports SF001_ip_status_before.txt]
puts "SF001_PROJECT_CREATED [file join $project_dir Sync_Frontend.xpr] PART=[get_property PART [current_project]] IP_COUNT=[llength [get_ips]]"
close_project
