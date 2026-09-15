# Vivado 2021.1: source <repo>/tools/vivado/create_project.tcl
# Only creates/opens the GUI project. Canonical IP sources stay under ip/config.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {[llength [get_projects -quiet]]} {error "Use an empty session; preserve any open GUI project."}
set target xcvu11p-flgb2104-2-e
if {[version -short] ne "2021.1"} {error "Vivado 2021.1 required"}
source [file join $root tools vivado run_threads.tcl]
set projdir $root
set projectfile [file join $projdir Sync_SFO.xpr]
proc read_list {path} {
    set h [open $path r]; set content [read $h]; close $h
    set result {}; foreach line [split $content "\n"] {set line [string trim $line]; if {$line ne ""} {lappend result $line}}
    return $result
}
if {[file exists $projectfile]} {
    open_project $projectfile
    if {[get_property PART [current_project]] ne $target} {error "Existing project target mismatch"}
    source [file join $root tools vivado configure_parallel_jobs.tcl]
    puts "Opened existing Sync_SFO; no simulation started."
    return
}
create_project Sync_SFO $projdir -part $target
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]
set_property XPM_LIBRARIES {} [current_project]
foreach n {xpm_cdc.sv xpm_memory.sv xpm_fifo.sv} {add_files -norecurse [list [file join $root rtl vendor xpm $n]]}
set rtlpaths {}; foreach rel [read_list [file join $root rtl sources.f]] {
    set path [file normalize [file join $root $rel]]
    if {![file isfile $path]} {error "Missing declared source: $rel"}
    lappend rtlpaths $path
}
if {[llength $rtlpaths]!=74 || [llength [lsort -unique $rtlpaths]]!=74} {error "Expected exactly 74 unique production core SV files"}
add_files -norecurse $rtlpaths
set ips [read_list [file join $root ip ip_names.txt]]
if {[llength $ips]!=34 || [llength [lsort -unique $ips]]!=34} {error "Expected 34 unique IP definitions"}
foreach n $ips {
    set path [file join $root ip config $n ${n}.xci]
    if {![file isfile $path]} {error "Missing canonical XCI: $path"}
    read_ip [list $path]
}
set_property include_dirs [list [file join $root rtl include]] [get_filesets sources_1]
set_property include_dirs [list [file join $root rtl include]] [get_filesets sim_1]
add_files -norecurse [list [file join $root sim data residual_pilot_phase.mem]]
add_files -fileset sim_1 -norecurse [list [file join $root sim tb sync_sfo_full_frame_tb.sv] [file join $root sim tb sfo_fifo_history_observer.sv]]
foreach n {raw.mem r1.mem r2.mem delay.mem delta.mem} {add_files -fileset sim_1 -norecurse [list [file join $root sim data $n]]}
set_property top sync_sfo_top [get_filesets sources_1]
set_property top sync_sfo_full_frame_tb [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
add_files -fileset constrs_1 -norecurse [list [file join $root constraints sync_sfo_clocks.xdc]]
update_compile_order -fileset sim_1
source [file join $root tools vivado configure_parallel_jobs.tcl]
puts "PROJECT_CREATED: $projectfile"
puts "Canonical IP: ip/config. No output generation, synthesis, implementation or simulation started."
