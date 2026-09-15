# Vivado 2021.1 GUI: source <repo>/tools/vivado/create_project.tcl
# Creates/opens only. No IP regeneration, synthesis or simulation; no exit.
set root [file normalize [file join [file dirname [info script]] ../..]]
set target xcvu11p-flgb2104-2-e
if {[version -short] ne "2021.1"} {error "Vivado 2021.1 required"}
set projdir [file join $root vivado T10_SFO]
set projectfile [file join $projdir T10_SFO.xpr]
if {[file exists $projectfile]} {
    open_project $projectfile
    if {[get_property PART [current_project]] ne $target} {error "Existing project target mismatch"}
    puts "Opened existing T10_SFO; no simulation started."
    return
}
proc read_list {path} {
    set h [open $path r]; set content [read $h]; close $h
    set result {}; foreach line [split $content "\n"] {set line [string trim $line]; if {$line ne ""} {lappend result $line}}
    return $result
}
create_project T10_SFO $projdir -part $target
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]
set_property XPM_LIBRARIES {} [current_project]
set_param general.maxThreads 2
foreach n {xpm_cdc.sv xpm_memory.sv xpm_fifo.sv} {
    add_files -norecurse [list [file join $root rtl vendor xpm $n]]
}
set rtlpaths {}; foreach rel [read_list [file join $root rtl sources.f]] {lappend rtlpaths [file join $root $rel]}
if {[llength $rtlpaths]!=74} {error "Expected exactly 74 production core SV files"}
add_files -norecurse $rtlpaths
# Import source XCI into project-local storage. Retarget/generation is a separate native step.
set ips [read_list [file join $root ip ip_names.txt]]
if {[llength $ips]!=34} {error "Expected 34 IP definitions"}
foreach n $ips {import_ip -files [list [file join $root ip config $n ${n}.xci]]}
set_property include_dirs [list [file join $root rtl include]] [get_filesets sources_1]
set_property include_dirs [list [file join $root rtl include]] [get_filesets sim_1]
add_files -norecurse [list [file join $root sim data t09_pilot_phase.mem]]
add_files -fileset sim_1 -norecurse [list [file join $root sim tb t10_full023_tb.sv] [file join $root sim tb t10_full023_fifo_observer.sv]]
foreach n {raw.mem r1.mem r2.mem delay.mem delta.mem} {add_files -fileset sim_1 -norecurse [list [file join $root sim data $n]]}
set_property top t10_two_pass_system [get_filesets sources_1]
set_property top t10_full023_tb [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
set_property xsim.elaborate.mt_level 2 [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
add_files -fileset constrs_1 -norecurse [list [file join $root constraints t10_root_clocks.xdc]]
update_compile_order -fileset sim_1
report_ip_status -file [file join $projdir ip_status_after_import.rpt]
puts "PROJECT_CREATED: $projectfile"
puts "Target is $target. Imported source IP must be natively retargeted/checked before generate or simulate."
puts "No long simulation started. Use GUI or source tools/vivado/start_simulation_0ns.tcl after native IP review."
