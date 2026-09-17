# Complete real project, short control smoke, then one core synthesis/export.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc != 2} {error "usage: -tclargs prepare|smoke|synth <new-attempt-directory>"}
set stage [lindex $argv 0]
set out [file normalize [lindex $argv 1]]
if {$stage ni {prepare smoke synth} || ![file isdirectory $out]} {error "stage/attempt"}
set xpr [file join $root Sync_OTA.xpr]
set hook [file join $root tools/vivado/run_threads.tcl]
proc read_lines {p} {
 set f [open $p r];set t [read $f];close $f;set values {}
 foreach s [split $t "\n"] {set s [string trim $s "\r\n\ufeff "];if {$s ne ""} {lappend values $s}}
 return $values
}
proc hooks {} {
 global hook
 foreach run [get_runs] {
  foreach p [list_property $run] {
   if {![regexp {^STEPS\..+\.TCL\.PRE$} $p]} {continue}
   set old [get_property $p $run]
   if {$old ne "" && [file normalize $old] ne [file normalize $hook]} {error "preserve unrelated PRE: $run $p"}
   set_property $p $hook $run
  }
 }
}
proc audit_project {{generated 1}} {
 global root out
 if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e" || [get_property TOP [get_filesets sources_1]] ne "sync_ota_top"} {error "wrong core project identity"}
 set f [open [file join $out actual_sources.tsv] w]
 foreach fs {sources_1 sim_1 constrs_1 utils_1} {
  foreach p [get_files -of_objects [get_filesets $fs]] {
   puts $f "$fs\t[file normalize $p]\t[get_property LIBRARY [get_files $p]]\t[get_property USED_IN_SYNTHESIS [get_files $p]]\t[get_property USED_IN_SIMULATION [get_files $p]]"
  }
 }
 close $f
 set f [open [file join $out actual_include_dirs.tsv] w]
 foreach fs {sources_1 sim_1} {
  foreach dir [get_property INCLUDE_DIRS [get_filesets $fs]] {
   puts $f "$fs\t[file normalize $dir]"
  }
 }
 close $f
 set f [open [file join $out actual_headers.tsv] w]
 foreach p [get_files -of_objects [get_filesets sources_1]] {
  if {[string tolower [file extension $p]] eq ".svh"} {
   puts $f "[file normalize $p]\t[get_property FILE_TYPE [get_files $p]]\t[get_property USED_IN_SYNTHESIS [get_files $p]]\t[get_property USED_IN_SIMULATION [get_files $p]]"
  }
 }
 close $f
 set f [open [file join $out actual_ips.tsv] w]
 foreach ip [lsort [get_ips]] {puts $f "[get_property NAME $ip]\t[file normalize [get_property IP_FILE $ip]]\t[get_property IS_LOCKED $ip]"}
 close $f
 foreach usage {simulation synthesis} {
  set cf [open [file join $out compile_order_${usage}.txt] w]
  if {$generated} {foreach file [get_files -compile_order sources -used_in $usage] {puts $cf [file normalize $file]}}
  close $cf
 }
 puts [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_ota004_a03_project.py] $out]
}
set memories {ip/rom/fine_ps1_reference_16lane.mem ip/rom/residual_pilot_phase.mem ip/cfo/cfo_rot_lut.mem ip/cfo/fft2048_twiddle.mem ip/cfo/front2048_coefficient_index.mem ip/cfo/front2048_coefficient_table.mem ip/cfo/fft256_twiddle.mem ip/cfo/phase74_atan_q31.mem}
if {$stage eq "prepare" && ![file exists $xpr]} {
 create_project Sync_OTA $root -part xcvu11p-flgb2104-2-e
 set_property target_language Verilog [current_project]
 set_property simulator_language Mixed [current_project]
 set_property target_simulator XSim [current_project]
 set_property default_lib ota_xpm [current_project]
 set_property XPM_LIBRARIES {} [current_project]
 foreach rel [read_lines [file join $root rtl/sources.f]] {
  set p [file join $root $rel];add_files -norecurse $p;set_property LIBRARY ota_xpm [get_files $p]
 }
 foreach rel [read_lines [file join $root rtl/headers_ota004_a02.f]] {
  set p [file join $root $rel];add_files -norecurse $p
  set_property FILE_TYPE {Verilog Header} [get_files $p]
  set_property LIBRARY ota_xpm [get_files $p]
  set_property USED_IN_SYNTHESIS true [get_files $p]
  set_property USED_IN_SIMULATION true [get_files $p]
 }
 foreach fs {sources_1 sim_1} {
  set_property INCLUDE_DIRS [list [file join $root rtl/include]] [get_filesets $fs]
 }
 foreach n {xpm_cdc xpm_memory xpm_fifo} {
  set p [file join $root rtl/vendor/xpm/${n}.sv];add_files -norecurse $p
  set_property LIBRARY ota_xpm [get_files $p];set_property USED_IN_SIMULATION false [get_files $p]
  set p [file join $root sim/vendor/link010r1/${n}.sv];add_files -fileset sim_1 -norecurse $p
  set_property LIBRARY ota_xpm [get_files $p];set_property USED_IN_SYNTHESIS false [get_files $p];set_property USED_IN_IMPLEMENTATION false [get_files $p]
 }
 foreach rel $memories {add_files -norecurse [file join $root $rel]}
 set ipfiles {};foreach rel [read_lines [file join $root ip/sources.f]] {lappend ipfiles [file join $root $rel]}
 # Official import produces owned managed copies; never mutate frozen baseline XCIs.
 import_ip -files $ipfiles
 add_files -fileset constrs_1 -norecurse [file join $root constraints/sync_ota_clocks.xdc]
 add_files -fileset sim_1 -norecurse [file join $root sim/tb/sync_ota_smoke_tb.sv]
 set_property LIBRARY ota_xpm [get_files [file join $root sim/tb/sync_ota_smoke_tb.sv]]
 add_files -fileset utils_1 -norecurse $hook
 set_property top sync_ota_top [get_filesets sources_1]
 set_property top sync_ota_smoke_tb [get_filesets sim_1]
 set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]
 set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
 set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
} else {
 if {![file exists $xpr]} {error "prepare has not created the project"}
 open_project $xpr
}
source $hook
hooks
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
if {$stage eq "prepare"} {audit_project 0} else {audit_project}
puts "OTA004_IDENTITY stage=$stage vivado=[version -short] part=[get_property PART [current_project]] top=[get_property TOP [get_filesets sources_1]] ip_count=[llength [get_ips]] xelab=[get_property xsim.elaborate.mt_level [get_filesets sim_1]]"
set failed [catch {
switch -- $stage {
 prepare {
  report_ip_status -file [file join $out ip_status_before.txt]
  # No force: completed targets are reused when continuing a failed setup.
  generate_target all [get_ips]
  export_ip_user_files -of_objects [get_ips] -no_script -sync
  update_compile_order -fileset sources_1
  update_compile_order -fileset sim_1
  audit_project
  set cwd [pwd];set checkdir [file join $out wrapper_syntax];file mkdir $checkdir;cd $checkdir
  set code [catch {exec C:/NIFPGA/programs/Vivado2021_1/bin/xvhdl.bat --2008 [file join $root wrapper/sync_ota_wrapper.vhd] 2>@1} output]
  set f [open [file join $out wrapper_syntax.txt] w];puts $f $output;close $f;puts $output;cd $cwd
  if {$code} {error "independent VHDL wrapper syntax failed"}
  set marker OTA004_PROJECT_PREPARE_PASS
 }
 smoke {
  set simdir [file join $root Sync_OTA.sim sim_1 behav xsim];file mkdir $simdir
  foreach rel $memories {
   set dst [file join $simdir [file tail $rel]]
   if {![file exists $dst]} {file copy [file join $root $rel] $dst}
  }
  launch_simulation
  set binding [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_ota004_binding.py] $simdir]
  puts $binding;set f [open [file join $out binding_verified.json] w];puts $f $binding;close $f
  run all
  set f [open [file join $simdir result.txt] r];set marker [string trim [read $f]];close $f
  if {$marker ne "OTA004_REAL_TOP_SMOKE_PASS"} {error "real top smoke marker missing"}
  close_sim
 }
 synth {
  # Aggregate budget: four simultaneous IP synthesis children at most; each
  # requests 8 threads. 16 IP children may exceed current ~12GiB free memory.
  set ip_jobs 4
  set pending {}
  foreach ip [get_ips] {
   if {[get_property IS_LOCKED $ip]} {error "locked IP"}
   set run [get_property NAME $ip]_synth_1
   if {![llength [get_runs -quiet $run]]} {create_ip_run $ip}
   if {![llength [get_runs -quiet $run]]} {error "missing IP OOC run $run"}
   if {![string match "*synth_design Complete*" [get_property STATUS [get_runs $run]]]} {lappend pending $run}
  }
  set_property -dict [list {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context} STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none] [get_runs synth_1]
  hooks
  puts "OTA004_BUILD_PARALLELISM ip_jobs=$ip_jobs core_launch_jobs=16 per_process_general=8 per_process_synth=8"
  if {[llength $pending]} {
   launch_runs $pending -jobs $ip_jobs
   foreach run $pending {
    wait_on_run $run
    if {![string match "*synth_design Complete*" [get_property STATUS [get_runs $run]]]} {error "IP failed: $run"}
   }
  }
  if {![string match "*synth_design Complete*" [get_property STATUS [get_runs synth_1]]]} {
   launch_runs synth_1 -jobs 16
   wait_on_run synth_1
  }
  if {![string match "*synth_design Complete*" [get_property STATUS [get_runs synth_1]]]} {error "core synthesis failed"}
  open_run synth_1
  set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
  if {[llength $blackboxes]} {error "algorithm/IP black boxes remain: $blackboxes"}
  foreach cell {frontend sfo cfo control ddr cfo/first_rotation cfo/second_rotation cfo/observation_front cfo/observation_backend} {
   if {[llength [get_cells -quiet $cell]]!=1} {error "required real hierarchy absent: $cell"}
  }
  write_checkpoint [file join $out sync_ota_synth.dcp]
  write_edif [file join $out sync_ota_top.edf]
  report_utilization -file [file join $out synth_utilization.txt]
  report_utilization -hierarchical -file [file join $out synth_utilization_hierarchical.txt]
  report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out synth_timing.txt]
  report_clocks -file [file join $out synth_clocks.txt]
  report_cdc -details -file [file join $out synth_cdc.txt]
  check_timing -verbose -file [file join $out synth_check_timing.txt]
  set f [open [file join $out synth_identity.txt] w]
  puts $f "TOP=sync_ota_top PART=xcvu11p-flgb2104-2-e BLACKBOX=0 CLOCKS=125/150/500MHz MODE=out_of_context PHYSICAL_TIMING=NOT_RUN"
  close $f
  close_design
  set marker OTA004_REAL_CORE_SYNTHESIS_COMPLETE
 }
}
} failure_message failure_options]
# Preserve mutable simulation products in the independent attempt even on error.
if {$stage eq "smoke"} {
 catch {close_sim}
 set simdir [file join $root Sync_OTA.sim sim_1 behav xsim]
 foreach pattern {*.log *_vlog.prj *_vhdl.prj *.bat *.tcl result.txt} {
  foreach p [glob -nocomplain [file join $simdir $pattern]] {
   set destination [file join $out [file tail $p]]
   if {![file exists $destination]} {file copy $p $destination}
  }
 }
}
if {$failed} {
 set f [open [file join $out failure.txt] w];puts $f $failure_message;puts $f $failure_options;close $f
 puts stderr "OTA004_FAILED stage=$stage $failure_message"
 catch {close_project}
 exit 1
}
set f [open [file join $out result.txt] w];puts $f $marker;close $f
if {$stage ne "smoke"} {puts $marker}
close_project
puts "OTA004_NATIVE_DONE stage=$stage"
exit 0
