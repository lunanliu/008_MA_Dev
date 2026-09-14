# PHASE004R1: reuse the existing successful project; replace one frozen source.
# This file never creates a project or changes test vectors.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 1} {error "Usage: -tclargs <attempt-directory>"}
set evidence [file normalize [lindex $argv 0]]
if {![file isdirectory $evidence]} {error "Evidence directory must already exist"}
set project_dir [file join $root vivado CFO_PHASE74]
set xpr [file join $project_dir CFO_PHASE74.xpr]
if {![file isfile $xpr]} {error "The previously created CFO_PHASE74 project is required"}
set old_core [file join $root rtl cfo_phase74_core.sv]
set new_core [file join $root rtl cfo_phase74_core_v2.sv]
proc phase74_expected {root core} {
 set pairs [list [list sources_1 $core] [list sources_1 [file join $root rtl cfo_divide_rne64.sv]] [list sources_1 [file join $root ip phase74_atan_q31.mem]] [list constrs_1 [file join $root constraints cfo_phase74.xdc]] [list sim_1 [file join $root sim tb cfo_phase74_tb.sv]] [list sim_1 [file join $root sim vectors phase74_config.svh]] [list utils_1 [file join $root vivado run_threads.tcl]]]
 foreach suffix {z angle pred center result} {lappend pairs [list sim_1 [file join $root sim vectors phase74_${suffix}.mem]]}
 set result {}
 foreach pair $pairs {lassign $pair fs path;lappend result "$fs|[file normalize $path]"}
 return [lsort $result]
}
proc phase74_actual {} {
 set result {}
 foreach fs {sources_1 constrs_1 sim_1 utils_1} {
  foreach f [get_files -of_objects [get_filesets $fs]] {lappend result "$fs|[file normalize $f]"}
 }
 return [lsort $result]
}
proc phase74_assert_identity {} {
 if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
 if {[get_property TOP [get_filesets sources_1]] ne "cfo_phase74_core" || [get_property TOP [get_filesets sim_1]] ne "cfo_phase74_tb"} {error "Wrong tops"}
}
proc phase74_export {evidence prefix} {
 set h [open [file join $evidence ${prefix}_actual_sources.csv] w];puts $h "fileset,path"
 foreach fs {sources_1 constrs_1 sim_1 utils_1} {
  foreach f [lsort [get_files -of_objects [get_filesets $fs]]] {puts $h "$fs,[file normalize $f]"}
 }
 close $h
}
file copy $xpr [file join $evidence CFO_PHASE74_before_source_update.xpr]
open_project $xpr
phase74_assert_identity
phase74_export $evidence before_fix
set actual [phase74_actual]
set expected_old [phase74_expected $root $old_core]
set expected_new [phase74_expected $root $new_core]
if {$actual eq $expected_old} {
 set candidates {}
 foreach f [get_files -of_objects [get_filesets sources_1]] {if {[file normalize $f] eq [file normalize $old_core]} {lappend candidates $f}}
 if {[llength $candidates] != 1} {error "Old core is not unique"}
 remove_files $candidates
 add_files -fileset sources_1 -norecurse [list $new_core]
 puts "CFO_PHASE74_SOURCE_REPAIR changed=1 old=$old_core new=$new_core"
} elseif {$actual eq $expected_new} {
 puts "CFO_PHASE74_SOURCE_REPAIR changed=0 resume_existing_v2=1"
} else {error "Unexpected source set; preserve project and stop"}
source [file join $root vivado configure_parallel_jobs.tcl]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
if {[phase74_actual] ne $expected_new} {error "Repaired source set mismatch"}
phase74_export $evidence updated
# Save and reopen the source update as a checkpoint before recompilation.
close_project
file copy $xpr [file join $evidence CFO_PHASE74_after_source_update.xpr]
open_project $xpr
phase74_assert_identity
if {[phase74_actual] ne $expected_new} {error "Reopened project did not preserve exact v2 source set"}
source [file join $root vivado configure_parallel_jobs.tcl]
phase74_export $evidence simulate
set h [open [file join $evidence simulate_project_identity.txt] w]
foreach {name value} [list part [get_property PART [current_project]] hardware_top [get_property TOP [get_filesets sources_1]] simulation_top [get_property TOP [get_filesets sim_1]] project $xpr vivado [version -short] xelab_jobs [get_property xsim.elaborate.mt_level [get_filesets sim_1]]] {puts $h "$name=$value"}
close $h
puts "CFO_PHASE74_SOURCE_REVISION PHASE004R1"
puts "CFO_PHASE74_READY action=simulate pid=[pid]"
flush stdout
set simdir [file join $project_dir CFO_PHASE74.sim sim_1 behav xsim]
file mkdir $simdir
file copy -force [file join $root ip phase74_atan_q31.mem] $simdir
foreach suffix {z angle pred center result} {file copy -force [file join $root sim vectors phase74_${suffix}.mem] $simdir}
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
launch_simulation
run all
close_sim
file copy [file join $simdir phase74_actual.txt] [file join $evidence phase74_actual.txt]
close_project
file copy $xpr [file join $evidence CFO_PHASE74_final.xpr]
puts "CFO_PHASE74_NATIVE_DONE action=simulate"
exit 0