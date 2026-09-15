set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root vivado CFO_SYNC CFO_SYNC.xpr]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
if {[get_property TOP [get_filesets sources_1]] ne "cfo_rotate4" || [get_property TOP [get_filesets sim_1]] ne "cfo_rotate4_tb"} {error "Wrong top"}
source [file join $root vivado configure_parallel_jobs.tcl]
source [file join $root vivado export_sources.tcl]
# Use a stable, project-local runtime directory. Explicitly stage read-only data.
set simdir [file join $root vivado CFO_SYNC CFO_SYNC.sim sim_1 behav xsim]
file mkdir $simdir
file copy -force [file join $root ip cfo_rot_lut.mem] $simdir
for {set i 0} {$i < 4} {incr i} {foreach suffix {input expected sat} {file copy -force [file join $root sim vectors rot_case${i}_${suffix}.mem] $simdir}}
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
launch_simulation
run all
close_sim
close_project
puts "CFO_NATIVE_RETURNED: completion and numeric evidence still require independent checking"
exit 0