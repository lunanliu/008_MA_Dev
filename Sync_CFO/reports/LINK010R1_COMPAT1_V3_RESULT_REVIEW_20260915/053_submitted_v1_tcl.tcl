# LINK010R1 compat1: reuse the created project and replace only sim_1's TB.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 2} {error "Usage: -tclargs simulate <attempt-directory>"}
set action [lindex $argv 0]
set evidence [file normalize [lindex $argv 1]]
if {$action ne "simulate"} {error "compat1 is simulate-only"}
if {![file isdirectory $evidence]} {error "Evidence directory must already exist"}

set project_dir [file join $root vivado CFO_LINK010R1]
set xpr [file join $project_dir CFO_LINK010R1.xpr]
set old_tb_path [file normalize [file join $root sim tb cfo_estimator_link_r1_tb.sv]]
set new_tb_path [file normalize [file join $root sim tb cfo_estimator_link_r1_compat1_tb.sv]]
if {![file exists $xpr]} {error "Created CFO_LINK010R1 project is missing"}
if {![file exists $new_tb_path]} {error "Frozen compat1 TB is missing"}
open_project $xpr

if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
if {[get_property TOP [get_filesets sources_1]] ne "cfo_estimator_link"} {error "Wrong hardware top"}
if {[get_property TOP [get_filesets sim_1]] ne "cfo_estimator_link_tb"} {error "Wrong simulation top before replacement"}

set old_tb {}
foreach f [get_files -of_objects [get_filesets sim_1]] {
 if {[string equal -nocase [file normalize $f] $old_tb_path]} {lappend old_tb $f}
}
if {[llength $old_tb] != 1} {error "Expected exactly one original R1 TB in sim_1"}
set old_obj [lindex $old_tb 0]
set old_library [get_property LIBRARY $old_obj]
set old_synth [get_property USED_IN_SYNTHESIS $old_obj]
set old_sim [get_property USED_IN_SIMULATION $old_obj]
set old_impl [get_property USED_IN_IMPLEMENTATION $old_obj]
remove_files -fileset sim_1 $old_obj
add_files -fileset sim_1 -norecurse $new_tb_path

set new_obj {}
foreach f [get_files -of_objects [get_filesets sim_1]] {
 if {[string equal -nocase [file normalize $f] $new_tb_path]} {lappend new_obj $f}
}
if {[llength $new_obj] != 1} {error "Compat1 TB was not added exactly once"}
set new_obj [lindex $new_obj 0]
set_property library $old_library $new_obj
set_property used_in_synthesis $old_synth $new_obj
set_property used_in_simulation $old_sim $new_obj
set_property used_in_implementation $old_impl $new_obj
set_property top cfo_estimator_link_tb [get_filesets sim_1]
set_property include_dirs [list [file join $root sim vectors]] [get_filesets sim_1]
source [file join $root vivado configure_parallel_jobs.tcl]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set h [open [file join $evidence simulate_actual_sources.csv] w]
puts $h "fileset,path,library,used_in_synthesis,used_in_simulation,used_in_implementation"
foreach fs {sources_1 constrs_1 sim_1 utils_1} {
 foreach f [lsort [get_files -of_objects [get_filesets $fs]]] {
  puts $h "$fs,[file normalize $f],[get_property LIBRARY $f],[get_property USED_IN_SYNTHESIS $f],[get_property USED_IN_SIMULATION $f],[get_property USED_IN_IMPLEMENTATION $f]"
 }
}
close $h

set h [open [file join $evidence simulate_project_identity.txt] w]
foreach {name value} [list part [get_property PART [current_project]] hardware_top [get_property TOP [get_filesets sources_1]] simulation_top [get_property TOP [get_filesets sim_1]] project $xpr vivado [version -short] xelab_jobs [get_property xsim.elaborate.mt_level [get_filesets sim_1]] xpm_libraries [lsort [get_property XPM_LIBRARIES [current_project]]]] {puts $h "$name=$value"}
close $h

set compat_check [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools verify_link010r1_compat1.py] --sources [file join $evidence simulate_actual_sources.csv]]
set h [open [file join $evidence compat1_source_check_pre_simulate.json] w]
puts $h $compat_check
close $h
puts "CFO_LINK010R1_COMPAT1_READY action=simulate pid=[pid]"
flush stdout

set simdir [file join $project_dir CFO_LINK010R1.sim sim_1 behav xsim]
file mkdir $simdir
file copy -force [file join $root ip fft256_twiddle.mem] $simdir
file copy -force [file join $root ip phase74_atan_q31.mem] $simdir
foreach suffix {input read result error_input error_read error_result} {file copy -force [file join $root sim vectors link010_${suffix}.mem] $simdir}

# Force a supported full compile/elaboration for the changed sim_1 set.
reset_simulation -simset sim_1
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral

set binding_before [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools verify_link010r1_binding.py] --simdir $simdir]
set h [open [file join $evidence compat1_binding_before.json] w]
puts $h $binding_before
close $h
if {[string first {"all_checks": true} $binding_before] < 0} {error "Private XPM binding failed before stimulus"}
puts "CFO_LINK010R1_COMPAT1_PRIVATE_BINDING_PASS_BEFORE"
run all
close_sim

set binding_after [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools verify_link010r1_binding.py] --simdir $simdir]
set h [open [file join $evidence compat1_binding_after.json] w]
puts $h $binding_after
close $h
if {[string first {"all_checks": true} $binding_after] < 0} {error "Private XPM binding failed after result save"}
puts "CFO_LINK010R1_COMPAT1_PRIVATE_BINDING_PASS_AFTER"
file copy [file join $simdir link010_actual.txt] [file join $evidence link010_actual.txt]
file copy [file join $simdir link010r1_reset_audit.txt] [file join $evidence link010r1_reset_audit.txt]
puts "CFO_LINK010R1_NATIVE_DONE action=simulate"
close_project
exit 0
