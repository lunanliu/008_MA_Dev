# Independent FRONT2048 arithmetic milestone; no previous project is modified.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 2} {error "Usage: -tclargs create|simulate <attempt-directory>"}
set action [lindex $argv 0]
set evidence [file normalize [lindex $argv 1]]
if {![file isdirectory $evidence]} {error "Evidence directory must already exist"}
if {$action ni {create simulate}} {error "Unknown action"}
set project_dir [file join $root vivado CFO_FRONT2048]
set xpr [file join $project_dir CFO_FRONT2048.xpr]
if {$action eq "create"} {
 if {[file exists $xpr]} {error "Preserve existing CFO_FRONT2048; review before recreation"}
 create_project CFO_FRONT2048 $project_dir -part xcvu11p-flgb2104-2-e
 set_property target_language Verilog [current_project]
 set_property simulator_language Mixed [current_project]
 set_property target_simulator XSim [current_project]
 add_files -norecurse [list [file join $root rtl cfo_front2048_window.sv] [file join $root rtl cfo_fft2048_core.sv] [file join $root ip fft2048_twiddle.mem] [file join $root ip front2048_coefficient_index.mem] [file join $root ip front2048_coefficient_table.mem]]
 set_property top cfo_front2048_window [get_filesets sources_1]
 add_files -fileset constrs_1 -norecurse [file join $root constraints cfo_front2048.xdc]
 set simfiles [list [file join $root sim tb cfo_front2048_tb.sv] [file join $root sim vectors front2048_config.svh]]
 foreach suffix {input pilot result metadata} {lappend simfiles [file join $root sim vectors front2048_${suffix}.mem]}
 add_files -fileset sim_1 -norecurse $simfiles
 add_files -fileset utils_1 -norecurse [file join $root vivado run_threads.tcl]
 set_property top cfo_front2048_tb [get_filesets sim_1]
 set_property include_dirs [list [file join $root sim vectors]] [get_filesets sim_1]
} else {open_project $xpr}
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
if {[get_property TOP [get_filesets sources_1]] ne "cfo_front2048_window" || [get_property TOP [get_filesets sim_1]] ne "cfo_front2048_tb"} {error "Wrong tops"}
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
puts "CFO_FRONT2048_READY action=$action pid=[pid]"
flush stdout
if {$action eq "simulate"} {
 set simdir [file join $project_dir CFO_FRONT2048.sim sim_1 behav xsim]
 file mkdir $simdir
 foreach filename {fft2048_twiddle.mem front2048_coefficient_index.mem front2048_coefficient_table.mem} {file copy -force [file join $root ip $filename] $simdir}
 foreach suffix {input pilot result metadata} {file copy -force [file join $root sim vectors front2048_${suffix}.mem] $simdir}
 set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
 launch_simulation
 run all
 close_sim
 file copy [file join $simdir front2048_actual.txt] [file join $evidence front2048_actual.txt]
}
close_project
puts "CFO_FRONT2048_NATIVE_DONE action=$action"
exit 0