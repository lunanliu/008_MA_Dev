# Independent 74-point phase-path milestone; no previous project is modified.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 2} {error "Usage: -tclargs create|simulate <attempt-directory>"}
set action [lindex $argv 0]
set evidence [file normalize [lindex $argv 1]]
if {![file isdirectory $evidence]} {error "Evidence directory must already exist"}
if {$action ni {create simulate}} {error "Unknown action"}
set project_dir [file join $root vivado CFO_PHASE74]
set xpr [file join $project_dir CFO_PHASE74.xpr]
if {$action eq "create"} {
 if {[file exists $xpr]} {error "Preserve existing CFO_PHASE74; review before recreation"}
 create_project CFO_PHASE74 $project_dir -part xcvu11p-flgb2104-2-e
 set_property target_language Verilog [current_project]
 set_property simulator_language Mixed [current_project]
 set_property target_simulator XSim [current_project]
 add_files -norecurse [list [file join $root rtl cfo_phase74_core.sv] [file join $root rtl cfo_divide_rne64.sv] [file join $root ip phase74_atan_q31.mem]]
 set_property top cfo_phase74_core [get_filesets sources_1]
 add_files -fileset constrs_1 -norecurse [file join $root constraints cfo_phase74.xdc]
 set simfiles [list [file join $root sim tb cfo_phase74_tb.sv] [file join $root sim vectors phase74_config.svh]]
 foreach suffix {z angle pred center result} {lappend simfiles [file join $root sim vectors phase74_${suffix}.mem]}
 add_files -fileset sim_1 -norecurse $simfiles
 add_files -fileset utils_1 -norecurse [file join $root vivado run_threads.tcl]
 set_property top cfo_phase74_tb [get_filesets sim_1]
 set_property include_dirs [list [file join $root sim vectors]] [get_filesets sim_1]
} else {open_project $xpr}
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
if {[get_property TOP [get_filesets sources_1]] ne "cfo_phase74_core" || [get_property TOP [get_filesets sim_1]] ne "cfo_phase74_tb"} {error "Wrong tops"}
source [file join $root vivado configure_parallel_jobs.tcl]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set h [open [file join $evidence ${action}_actual_sources.csv] w]
puts $h "fileset,path"
foreach fs {sources_1 constrs_1 sim_1 utils_1} {
 foreach f [lsort [get_files -of_objects [get_filesets $fs]]] {puts $h "$fs,[file normalize $f]"}
}
close $h
set h [open [file join $evidence ${action}_project_identity.txt] w]
foreach {name value} [list part [get_property PART [current_project]] hardware_top [get_property TOP [get_filesets sources_1]] simulation_top [get_property TOP [get_filesets sim_1]] project $xpr vivado [version -short] xelab_jobs [get_property xsim.elaborate.mt_level [get_filesets sim_1]]] {puts $h "$name=$value"}
close $h
puts "CFO_PHASE74_READY action=$action pid=[pid]"
flush stdout
if {$action eq "simulate"} {
 set simdir [file join $project_dir CFO_PHASE74.sim sim_1 behav xsim]
 file mkdir $simdir
 file copy -force [file join $root ip phase74_atan_q31.mem] $simdir
 foreach suffix {z angle pred center result} {file copy -force [file join $root sim vectors phase74_${suffix}.mem] $simdir}
 set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
 launch_simulation
 run all
 close_sim
 file copy [file join $simdir phase74_actual.txt] [file join $evidence phase74_actual.txt]
}
close_project
puts "CFO_PHASE74_NATIVE_DONE action=$action"
exit 0