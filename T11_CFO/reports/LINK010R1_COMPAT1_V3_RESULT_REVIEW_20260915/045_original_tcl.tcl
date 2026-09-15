# Atomic observation CDC and unchanged 74-point estimator backend integration; no previous project is modified.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 2} {error "Usage: -tclargs create|simulate <attempt-directory>"}
set action [lindex $argv 0]
set evidence [file normalize [lindex $argv 1]]
if {![file isdirectory $evidence]} {error "Evidence directory must already exist"}
if {$action ni {create simulate}} {error "Unknown action"}
set project_dir [file join $root vivado CFO_LINK010R1]
set xpr [file join $project_dir CFO_LINK010R1.xpr]
if {$action eq "create"} {
 if {[file exists $xpr]} {error "Preserve existing CFO_LINK010R1; review before recreation"}
 create_project CFO_LINK010R1 $project_dir -part xcvu11p-flgb2104-2-e
 set_property target_language Verilog [current_project]
 set_property simulator_language Mixed [current_project]
 set_property target_simulator XSim [current_project]
 set_property default_lib cfo_xpm [current_project]
 # Compile explicit sources into a private local simulation library, never the installed xpm map.
 set_property XPM_LIBRARIES {} [current_project]
 foreach name {xpm_cdc xpm_memory xpm_fifo} {
  set official [file normalize C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/$name/hdl/${name}.sv]
  add_files -norecurse $official
  set_property used_in_simulation false [get_files $official]
  set private [file join $root sim vendor link010r1 ${name}.sv]
  add_files -fileset sim_1 -norecurse $private
  set_property library cfo_xpm [get_files $private]
  set_property used_in_synthesis false [get_files $private]
  set_property used_in_implementation false [get_files $private]
 }
 set rtl_files [list cfo_estimator_link_v2.sv cfo_estimate74_backend.sv cfo_fft74_quality_v2.sv cfo_divide_rne64wide.sv cfo_fft256_core.sv cfo_phase74_core_v2.sv cfo_divide_rne64.sv]
 foreach name $rtl_files {add_files -norecurse [file join $root rtl $name]}
 add_files -norecurse [list [file join $root ip fft256_twiddle.mem] [file join $root ip phase74_atan_q31.mem]]
 set_property top cfo_estimator_link [get_filesets sources_1]
 add_files -fileset constrs_1 -norecurse [file join $root constraints cfo_link010.xdc]
 set simfiles [list [file join $root sim tb cfo_estimator_link_r1_tb.sv] [file join $root sim vectors link010_config.svh]]
 foreach suffix {input read result error_input error_read error_result} {lappend simfiles [file join $root sim vectors link010_${suffix}.mem]}
 add_files -fileset sim_1 -norecurse $simfiles
 add_files -fileset utils_1 -norecurse [file join $root vivado run_threads.tcl]
 set_property top cfo_estimator_link_tb [get_filesets sim_1]
 set_property include_dirs [list [file join $root sim vectors]] [get_filesets sim_1]
 # Bind all design units to this project-local library. Vivado can still append
 # -L xpm automatically; actual library search order and binding are gated below.
 foreach f [get_files -all -filter {FILE_TYPE == SystemVerilog}] {set_property library cfo_xpm $f}
} else {open_project $xpr}
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
if {[get_property TOP [get_filesets sources_1]] ne "cfo_estimator_link" || [get_property TOP [get_filesets sim_1]] ne "cfo_estimator_link_tb"} {error "Wrong tops"}
source [file join $root vivado configure_parallel_jobs.tcl]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set h [open [file join $evidence ${action}_actual_sources.csv] w]
puts $h "fileset,path,library,used_in_synthesis,used_in_simulation,used_in_implementation"
foreach fs {sources_1 constrs_1 sim_1 utils_1} {
 foreach f [lsort [get_files -of_objects [get_filesets $fs]]] {
  puts $h "$fs,[file normalize $f],[get_property LIBRARY $f],[get_property USED_IN_SYNTHESIS $f],[get_property USED_IN_SIMULATION $f],[get_property USED_IN_IMPLEMENTATION $f]"
 }
}
close $h
set h [open [file join $evidence ${action}_project_identity.txt] w]
foreach {name value} [list part [get_property PART [current_project]] hardware_top [get_property TOP [get_filesets sources_1]] simulation_top [get_property TOP [get_filesets sim_1]] project $xpr vivado [version -short] xelab_jobs [get_property xsim.elaborate.mt_level [get_filesets sim_1]] xpm_libraries [lsort [get_property XPM_LIBRARIES [current_project]]]] {puts $h "$name=$value"}
close $h
puts "CFO_LINK010R1_READY action=$action pid=[pid]"
flush stdout
if {$action eq "simulate"} {
 set simdir [file join $project_dir CFO_LINK010R1.sim sim_1 behav xsim]
 file mkdir $simdir
 file copy -force [file join $root ip fft256_twiddle.mem] $simdir
 file copy -force [file join $root ip phase74_atan_q31.mem] $simdir
 foreach suffix {input read result error_input error_read error_result} {file copy -force [file join $root sim vectors link010_${suffix}.mem] $simdir}
 set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
 launch_simulation
 # Read the actual compile/elaboration products once, before numerical stimulus.
 # -I isolates Python from the inherited Vivado Python environment. This helper
 # is read-only, has no native-launch API, and performs no estimator calculation.
 set binding_report [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools verify_link010r1_binding.py] --simdir $simdir]
 puts $binding_report
 puts "CFO_LINK010R1_PRIVATE_BINDING_PASS"
 run all
 close_sim
 file copy [file join $simdir link010_actual.txt] [file join $evidence link010_actual.txt]
 file copy [file join $simdir link010r1_reset_audit.txt] [file join $evidence link010r1_reset_audit.txt]
}
close_project
puts "CFO_LINK010R1_NATIVE_DONE action=$action"
exit 0