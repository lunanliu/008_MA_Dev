set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 1} {error "Expected a new output directory"}
set out [file normalize [lindex $argv 0]]
if {[file exists [file join $out project]]} {error "Preserve existing project"}
create_project DDR_Control [file join $out project] -part xcvu11p-flgb2104-2-e
set_param general.maxThreads 8
set_property target_language VHDL [current_project]
foreach name {ddr_upload_ctrl ddr_read_ctrl} {
  add_files -norecurse [list [file join $root rtl $name.vhd]]
  set_property file_type VHDL [get_files $name.vhd]
}
set_property top ddr_upload_ctrl [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [list [file join $root constraints upload_150mhz.xdc]]
foreach mode {write read} {
  set fs sim_$mode
  create_fileset -simset $fs
  if {$mode eq "write"} {set tb tb_ddr_upload_ctrl} else {set tb tb_ddr_read_ctrl}
  add_files -fileset $fs -norecurse [list [file join $root sim $tb.vhd]]
  set_property file_type VHDL [get_files $tb.vhd]
  set_property top $tb [get_filesets $fs]
  set_property -dict [list xsim.elaborate.mt_level {16} xsim.elaborate.xelab.more_options {} xsim.simulate.runtime {0ns}] [get_filesets $fs]
  update_compile_order -fileset $fs
}
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $root scripts threads_pre.tcl] [get_runs synth_1]
update_compile_order -fileset sources_1
set f [open [file join $out actual_sources.txt] w]
foreach fs {sources_1 sim_write sim_read constrs_1} {
  foreach src [get_files -of_objects [get_filesets $fs]] {puts $f "$fs\t[file normalize $src]"}
}
close $f
set f [open [file join $out actual_tops.txt] w]
foreach fs {sources_1 sim_write sim_read} {puts $f "$fs\t[get_property top [get_filesets $fs]]"}
close $f
puts "DDR_CONTROL_PROJECT_CREATED"
close_project
