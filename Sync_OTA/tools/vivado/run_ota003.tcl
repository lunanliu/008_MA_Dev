set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc != 2} {error "usage: -tclargs bridge|capture|dual_rotation <new-attempt-directory>"}
set stage [lindex $argv 0]
set attempt [file normalize [lindex $argv 1]]
if {![file isdirectory $attempt]} {error "attempt directory must already exist"}
set memories {};set vectors {};set binding_requirement none
switch -- $stage {
 bridge {
  set dut ota_ddr_bridge;set tb ota_ddr_bridge_tb;set marker OTA003_DDR_BRIDGE_PASS
  set design {rtl/buffer/ota_ddr_bridge.sv rtl/common/ota_async_fifo.sv}
  set binding_requirement fifo
 }
 capture {
  set dut ota_capture_controller;set tb ota_capture_controller_tb;set marker OTA003_CAPTURE_CONTROL_PASS
  set design {rtl/control/ota_capture_controller.sv rtl/buffer/ota_frame_store.sv rtl/control/ota_frontend_descriptor.sv}
 }
 dual_rotation {
  set dut cfo_rotate4;set tb ota_dual_rotation_tb;set marker OTA003_DUAL_ROTATION_PASS
  set design {rtl/cfo/cfo_rotate4.sv rtl/cfo/cfo_coordinate_control.sv}
  set memories {ip/cfo/cfo_rot_lut.mem}
  set vectors {sim/data/ota_dual_input.mem sim/data/ota_dual_coarse.mem sim/data/ota_dual_final.mem sim/data/ota_dual_config.svh}
 }
 default {error "unknown stage"}
}
set proj [file join $attempt project]
if {[file exists $proj]} {error "preserve previous attempt"}
create_project OTA003_${stage} $proj -part xcvu11p-flgb2104-2-e
set_property target_simulator XSim [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib ota_xpm [current_project]
set_property XPM_LIBRARIES {} [current_project]
set expected {}
proc add_expected {fs rel} {
 global root expected
 set path [file normalize [file join $root $rel]]
 add_files -fileset $fs -norecurse $path
 lappend expected "$fs\t$path"
 return $path
}
foreach name {xpm_cdc xpm_memory xpm_fifo} {
 set official [add_expected sources_1 rtl/vendor/xpm/${name}.sv]
 set_property used_in_simulation false [get_files $official]
 set private [add_expected sim_1 sim/vendor/link010r1/${name}.sv]
 set_property used_in_synthesis false [get_files $private]
 set_property used_in_implementation false [get_files $private]
}
foreach rel $design {add_expected sources_1 $rel}
foreach rel $memories {add_expected sources_1 $rel}
foreach rel $vectors {add_expected sim_1 $rel}
add_expected sim_1 sim/tb/${tb}.sv
add_expected utils_1 tools/vivado/run_threads.tcl
foreach f [get_files -all -filter {FILE_TYPE == SystemVerilog}] {set_property library ota_xpm $f}
set_property top $dut [get_filesets sources_1]
set_property top $tb [get_filesets sim_1]
set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]
set_property xsim.elaborate.debug_level all [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
source [file join $root tools/vivado/run_threads.tcl]
foreach run [get_runs] {
 foreach property [list_property $run] {
  if {[regexp {^STEPS\..+\.TCL\.PRE$} $property]} {set_property $property [file join $root tools/vivado/run_threads.tcl] $run}
 }
}
set_property include_dirs [list [file join $root sim/data]] [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set actual {}
set f [open [file join $attempt actual_sources.tsv] w]
foreach fs {sources_1 sim_1 utils_1} {
 foreach path [get_files -of_objects [get_filesets $fs]] {
  set path [file normalize $path]
  lappend actual "$fs\t$path"
  puts $f "$fs\t$path\t[get_property LIBRARY [get_files $path]]\t[get_property USED_IN_SYNTHESIS [get_files $path]]\t[get_property USED_IN_SIMULATION [get_files $path]]"
 }
}
close $f
if {[lsort $actual] ne [lsort $expected]} {error "actual project source membership mismatch"}
puts "OTA003_IDENTITY vivado=[version -short] part=[get_property PART [current_project]] top=$dut sim=$tb xelab=[get_property xsim.elaborate.mt_level [get_filesets sim_1]]"
set simdir [file join $proj OTA003_${stage}.sim sim_1 behav xsim]
file mkdir $simdir
foreach rel [concat $memories $vectors] {file copy [file join $root $rel] [file join $simdir [file tail $rel]]}
launch_simulation
set binding [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_xpm_binding.py] $simdir $binding_requirement]
puts $binding
set bf [open [file join $simdir binding_verified.json] w];puts $bf $binding;close $bf
run all
set result [file join $simdir result.txt]
if {![file isfile $result]} {error "no TB result; preserve first failure"}
set f [open $result r];set contents [read $f];close $f
if {[string trim $contents] ne $marker} {error "wrong TB result"}
close_sim
file copy $result [file join $attempt result.txt]
file copy [file join $simdir binding_verified.json] [file join $attempt binding_verified.json]
close_project
puts "OTA003_NATIVE_DONE stage=$stage"
exit 0
