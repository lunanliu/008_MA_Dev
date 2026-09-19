# Exact source set for two pure VHDL-93 controllers and independent benches.
set root {D:/007 Dev/OTA_RTL_0829/output/DDR_Control_VHDL_20260916_rev02}
create_project DDR_Control [file join $root project_retry04] -part xcvu11p-flgb2104-2-e
set_property target_language VHDL [current_project]
foreach name {ddr_upload_ctrl ddr_read_ctrl} {
  add_files -norecurse [list [file join $root rtl ${name}.vhd]]
  set_property file_type VHDL [get_files ${name}.vhd]
}
set_property top ddr_upload_ctrl [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [list [file join $root constraints upload_150mhz.xdc]]
foreach mode {write read} {
  set fs sim_$mode
  create_fileset -simset $fs
  if {$mode eq "write"} {set tb tb_ddr_upload_ctrl} else {set tb tb_ddr_read_ctrl}
  add_files -fileset $fs -norecurse [list [file join $root sim ${tb}.vhd]]
  set_property file_type VHDL [get_files ${tb}.vhd]
  set_property top $tb [get_filesets $fs]
  set_property xsim.elaborate.xelab.more_options {-mt 16} [get_filesets $fs]
  set_property xsim.simulate.runtime 0ns [get_filesets $fs]
  update_compile_order -fileset $fs
}
set_param general.maxThreads 8
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $root scripts threads_pre.tcl] [get_runs synth_1]
update_compile_order -fileset sources_1
set f [open [file join $root actual_sources_retry04.txt] w]
foreach fs {sources_1 sim_write sim_read constrs_1} {
  foreach src [get_files -of_objects [get_filesets $fs]] {puts $f "$fs\t[file normalize $src]"}
}
close $f
puts "DDR_CONTROL_PROJECT_CREATED"
close_project