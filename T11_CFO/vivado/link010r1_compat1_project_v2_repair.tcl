# LINK010R1 compat1 v2: simulate-only, frozen dependency identity is checked by the Python entrypoint.
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

proc save_sim_evidence {simdir evidence} {
 foreach name {xvlog.log compile.log elaborate.log xelab.log simulate.log xsim.log compile.bat cfo_estimator_link_tb_vlog.prj xsim.ini} {
  set src [file join $simdir $name]
  if {[file exists $src]} {file copy -force $src [file join $evidence native_$name]}
 }
 set kernel [file join $simdir xsim.dir cfo_estimator_link_tb_behav xsimkernel.log]
 if {[file exists $kernel]} {file copy -force $kernel [file join $evidence native_xsimkernel.log]}
 foreach name {link010_actual.txt link010r1_reset_audit.txt} {
  set src [file join $simdir $name]
  if {[file exists $src]} {file copy -force $src [file join $evidence $name]}
 }
}

proc invoke_binding {root simdir evidence phase} {
 set output ""
 set options {}
 set rc [catch {exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools verify_link010r1_binding.py] --simdir $simdir 2>@1} output options]
 set report [file join $evidence compat1_binding_${phase}.json]
 set h [open $report w]
 puts $h $output
 close $h
 set raw [file join $evidence compat1_binding_${phase}.raw.log]
 set h [open $raw w]
 puts $h [format "exit_code=%d\noptions=%s\noutput:\n%s" $rc $options $output]
 close $h
 return [list $rc $output]
}

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

# Force a supported full compile/elaboration for the changed sim_1 set.
reset_simulation -mode behavioral sim_1
set simdir [file join $project_dir CFO_LINK010R1.sim sim_1 behav xsim]
foreach name {link010_actual.txt link010r1_reset_audit.txt xvlog.log compile.log elaborate.log xelab.log simulate.log xsim.log compile.bat cfo_estimator_link_tb_vlog.prj xsim.ini} {
 set stale [file join $simdir $name]
 if {[file exists $stale]} {file delete -force $stale}
}
if {[file exists [file join $simdir xsim.dir]]} {file delete -force [file join $simdir xsim.dir]}
file mkdir $simdir
file copy -force [file join $root ip fft256_twiddle.mem] $simdir
file copy -force [file join $root ip phase74_atan_q31.mem] $simdir
foreach suffix {input read result error_input error_read error_result} {file copy -force [file join $root sim vectors link010_${suffix}.mem] $simdir}

set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral

set binding_before_result [invoke_binding $root $simdir $evidence before]
set binding_before_rc [lindex $binding_before_result 0]
set binding_before [lindex $binding_before_result 1]
if {$binding_before_rc != 0 || [string first {"all_checks": true} $binding_before] < 0} {
 save_sim_evidence $simdir $evidence
 error "Private XPM binding failed before stimulus: $binding_before"
}
puts "CFO_LINK010R1_COMPAT1_PRIVATE_BINDING_PASS_BEFORE"
set run_output ""
set run_options {}
set run_rc [catch {run all} run_output run_options]
if {$run_rc != 0} {
 set h [open [file join $evidence run_all.raw.log] w]
 puts $h [format "exit_code=%d\noptions=%s\noutput:\n%s" $run_rc $run_options $run_output]
 close $h
 catch {close_sim}
 save_sim_evidence $simdir $evidence
 error "run all failed: $run_output"
}
set close_output ""
set close_options {}
set close_rc [catch {close_sim} close_output close_options]
if {$close_rc != 0} {
 set h [open [file join $evidence close_sim.raw.log] w]
 puts $h [format "exit_code=%d\noptions=%s\noutput:\n%s" $close_rc $close_options $close_output]
 close $h
 save_sim_evidence $simdir $evidence
 error "close_sim failed: $close_output"
}

set binding_after_result [invoke_binding $root $simdir $evidence after]
set binding_after_rc [lindex $binding_after_result 0]
set binding_after [lindex $binding_after_result 1]
if {$binding_after_rc != 0 || [string first {"all_checks": true} $binding_after] < 0} {
 save_sim_evidence $simdir $evidence
 error "Private XPM binding failed after result save: $binding_after"
}
puts "CFO_LINK010R1_COMPAT1_PRIVATE_BINDING_PASS_AFTER"
save_sim_evidence $simdir $evidence
if {![file exists [file join $simdir link010_actual.txt]] || ![file exists [file join $simdir link010r1_reset_audit.txt]]} {error "Native trace or reset audit missing after simulation"}
puts "CFO_LINK010R1_NATIVE_DONE action=simulate"
close_project
exit 0
