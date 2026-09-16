# Native execution belongs to the unique Luna after a concrete manager slot grant.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc != 2} {error "usage: -tclargs store|descriptor <new-attempt-directory>"}
set stage [lindex $argv 0]
set attempt [file normalize [lindex $argv 1]]
if {![file isdirectory $attempt]} {error "attempt directory must already exist"}
switch -- $stage {
 store {set dut ota_frame_store; set rel rtl/buffer/ota_frame_store.sv;set marker OTA001_STORE_PASS}
 descriptor {set dut ota_frontend_descriptor;set rel rtl/control/ota_frontend_descriptor.sv;set marker OTA001_DESCRIPTOR_PASS}
 default {error "unknown stage"}
}
set proj [file join $attempt project]
if {[file exists $proj]} {error "preserve existing attempt; choose a new directory"}
create_project OTA001_${stage} $proj -part xcvu11p-flgb2104-2-e
set_property target_simulator XSim [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse [file join $root $rel]
add_files -fileset sim_1 -norecurse [file join $root sim/tb ${dut}_tb.sv]
set_property top $dut [get_filesets sources_1]
set_property top ${dut}_tb [get_filesets sim_1]
set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
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
foreach fs {sources_1 sim_1} {
 puts $f "$fs\tTOP=[get_property TOP [get_filesets $fs]]"
 foreach path [get_files -of_objects [get_filesets $fs]] {
  set path [file normalize $path]
  puts $f "$fs\t$path"
  lappend actual $path
 }
}
close $f
set expected [list [file normalize [file join $root $rel]] [file normalize [file join $root sim/tb ${dut}_tb.sv]]]
if {[lsort -unique $actual] ne [lsort $expected]} {error "actual source set mismatch"}
puts "OTA001_IDENTITY vivado=[version -short] part=[get_property PART [current_project]] top=$dut sim=${dut}_tb xelab=[get_property xsim.elaborate.mt_level [get_filesets sim_1]]"
launch_simulation
run all
set simdir [file join $proj OTA001_${stage}.sim sim_1 behav xsim]
set result [file join $simdir result.txt]
if {![file isfile $result]} {error "TB did not publish PASS; preserve first failure"}
set f [open $result r];set contents [read $f];close $f
if {[string trim $contents] ne $marker} {error "unexpected TB result"}
close_sim
file copy $result [file join $attempt result.txt]
close_project
puts "OTA001_NATIVE_DONE stage=$stage"
exit 0
