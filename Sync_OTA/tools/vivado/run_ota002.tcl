set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc != 2} {error "usage: -tclargs context|backend74|cfo_control <new-attempt-directory>"}
set stage [lindex $argv 0]
set attempt [file normalize [lindex $argv 1]]
if {![file isdirectory $attempt]} {error "attempt directory must already exist"}
set backend {rtl/cfo/cfo_estimator_link_v2.sv rtl/cfo/cfo_estimate74_backend.sv rtl/cfo/cfo_fft74_quality_v2.sv rtl/cfo/cfo_divide_rne64wide.sv rtl/cfo/cfo_fft256_core.sv rtl/cfo/cfo_phase74_core_v2.sv rtl/cfo/cfo_divide_rne64.sv}
set memories {ip/cfo/fft256_twiddle.mem ip/cfo/phase74_atan_q31.mem}
set vectors {}
switch -- $stage {
 context {
  set dut ota_sfo_context_join;set tb ota_context_boundary_tb;set marker OTA002_CONTEXT_PASS
  set design {rtl/control/ota_sfo_context_join.sv rtl/common/ota_async_fifo.sv rtl/sfo/first_resampling/sfo_first_pass_descriptor.sv rtl/sfo/second_resampling/sfo_second_pass_descriptor.sv}
  set memories {}
 }
 backend74 {
  set dut cfo_estimator_link;set tb ota_backend74_tb;set marker OTA002_BACKEND74_PASS
  set design $backend
  set vectors {sim/data/link010_input.mem sim/data/link010_read.mem sim/data/link010_result.mem}
 }
 cfo_control {
  set dut ota_cfo_chain;set tb ota_cfo_control_tb;set marker OTA002_CFO_CONTROL_PASS
  set design [concat {rtl/cfo/ota_cfo_chain.sv rtl/buffer/ota_frame_store.sv rtl/common/ota_async_fifo.sv rtl/cfo/cfo_rotate4.sv rtl/cfo/cfo_coordinate_control.sv rtl/cfo/cfo_front2048_window.sv rtl/cfo/cfo_fft2048_core.sv} $backend]
  set memories [concat $memories {ip/cfo/cfo_rot_lut.mem ip/cfo/fft2048_twiddle.mem ip/cfo/front2048_coefficient_index.mem ip/cfo/front2048_coefficient_table.mem}]
 }
 default {error "unknown stage"}
}
set proj [file join $attempt project]
if {[file exists $proj]} {error "preserve previous attempt"}
create_project OTA002_${stage} $proj -part xcvu11p-flgb2104-2-e
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
puts "OTA002_IDENTITY vivado=[version -short] part=[get_property PART [current_project]] top=$dut sim=$tb xelab=[get_property xsim.elaborate.mt_level [get_filesets sim_1]]"
set simdir [file join $proj OTA002_${stage}.sim sim_1 behav xsim]
file mkdir $simdir
foreach rel [concat $memories $vectors] {file copy [file join $root $rel] [file join $simdir [file tail $rel]]}
launch_simulation
puts [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_ota002_binding.py] $simdir]
run all
set result [file join $simdir result.txt]
if {![file isfile $result]} {error "no TB result; preserve first failure"}
set f [open $result r];set contents [read $f];close $f
if {[string trim $contents] ne $marker} {error "wrong TB result"}
close_sim
file copy $result [file join $attempt result.txt]
file copy [file join $simdir binding_verified.json] [file join $attempt binding_verified.json]
close_project
puts "OTA002_NATIVE_DONE stage=$stage"
exit 0
