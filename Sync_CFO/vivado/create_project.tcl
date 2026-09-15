# This is the sole rotation-milestone project entry. No old project is sourced.
set root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $root vivado CFO_SYNC]
set xpr [file join $project_dir CFO_SYNC.xpr]
if {[file exists $xpr]} {error "Project already exists; preserve it and use run_rotator.tcl."}
create_project CFO_SYNC $project_dir -part xcvu11p-flgb2104-2-e
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]
add_files -norecurse [list [file join $root rtl cfo_rotate4.sv] [file join $root ip cfo_rot_lut.mem]]
set_property top cfo_rotate4 [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $root constraints cfo_rotate4.xdc]
set simulations [list [file join $root sim tb cfo_rotate4_tb.sv] [file join $root sim vectors rotator_configs.svh]]
for {set i 0} {$i < 4} {incr i} {foreach suffix {input expected sat} {lappend simulations [file join $root sim vectors rot_case${i}_${suffix}.mem]}}
add_files -fileset sim_1 -norecurse $simulations
set_property top cfo_rotate4_tb [get_filesets sim_1]
set_property include_dirs [list [file join $root sim vectors]] [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
source [file join $root vivado configure_parallel_jobs.tcl]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
source [file join $root vivado export_sources.tcl]
close_project
puts "CFO_PROJECT_CREATED xpr=$xpr part=xcvu11p-flgb2104-2-e top=cfo_rotate4 sim=cfo_rotate4_tb"
exit 0