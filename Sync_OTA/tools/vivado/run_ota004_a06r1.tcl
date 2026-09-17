# Complete real project, short control smoke, then one core synthesis/export.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc != 2} {error "usage: -tclargs smoke|synth <new-attempt-directory>"}
set stage [lindex $argv 0]
set out [file normalize [lindex $argv 1]]
if {$stage ni {smoke synth} || ![file isdirectory $out]} {error "stage/attempt"}
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
 global root out stage
 if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e" || [get_property TOP [get_filesets sources_1]] ne "sync_ota_top"} {error "wrong core project identity"}
 set f [open [file join $out actual_xpm_registration.txt] w]
 puts $f $stage;puts $f [join [lsort [get_property XPM_LIBRARIES [current_project]]] ,];close $f
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
 set f [open [file join $out audit_generation_state.txt] w];puts $f $generated;close $f
 set f [open [file join $out actual_mif_files.txt] w]
 if {$generated} {
  foreach p [get_files -all] {
   if {[string tolower [file extension $p]] eq ".mif"} {puts $f [file normalize $p]}
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
 puts [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_ota004_a06r1_project.py] $out]
}
proc verify_prior_core_sources {prior} {
 global root out
 set actual {};set command ""
 foreach line [split $prior "\n"] {
  if {$command eq "" && ([string trim $line] eq "" || [string match "#*" [string trimleft $line]])} {continue}
  append command $line "\n"
  if {![info complete $command]} {continue}
  if {[regexp {^read_verilog(?:\s|$)} [string trimleft $command]]} {
   # A generated read_verilog command is parsed as data, never evaluated.
   foreach source [lindex [string trim $command] end] {
    set path [file normalize $source]
    if {[file extension $path] eq ".sv" && [string first "$root/rtl/" $path]==0 && [string first "$root/rtl/vendor/" $path]!=0} {lappend actual $path}
   }
  }
  set command ""
 }
 if {[string trim $command] ne ""} {error "truncated completed-core generated script"}
 set expected {}
 foreach rel [read_lines [file join $root rtl/sources_a06.f]] {lappend expected [file normalize [file join $root $rel]]}
 # Vivado omits this unreferenced standalone front-end port wrapper from the
 # actual core compile order. All 128 remain registered/audited in the project.
 set unused [file normalize [file join $root rtl/frontend/timing/to_coarse_ports.sv]]
 set expected_used {}
 foreach path $expected {if {$path ne $unused} {lappend expected_used $path}}
 if {[llength $expected]!=128 || [llength $actual]!=127 || [lsort $actual] ne [lsort $expected_used]} {error "completed core actual=[llength $actual] must match the 127 used A06 production sources; preserve and review, do not resynthesize blindly"}
 set compiled {}
 foreach source [read_lines [file join $out compile_order_synthesis.txt]] {
  set path [file normalize $source]
  if {[file extension $path] eq ".sv" && [string first "$root/rtl/" $path]==0 && [string first "$root/rtl/vendor/" $path]!=0} {lappend compiled $path}
 }
 if {$actual ne $compiled} {error "completed core production compile order differs from current audited project"}
 set f [open [file join $out reused_core_actual_production_order.txt] w]
 foreach path $actual {puts $f $path};close $f
 puts "OTA004_A06R1_COMPLETED_CORE_EXACT_SOURCE_ORDER_VERIFIED registered_rtl=128 compiled_rtl=127"
}
proc audit_reused_ips {phase} {
 global out
 set f [open [file join $out reused_ip_runs_${phase}.tsv] w]
 puts $f "ip\trun\tstatus\tneeds_refresh\tip_locked"
 set problems {};set count 0
 foreach ip [lsort [get_ips]] {
  incr count
  set name [get_property NAME $ip];set run ${name}_synth_1
  set locked [get_property IS_LOCKED $ip]
  set status MISSING;set refresh UNKNOWN
  set obj [get_runs -quiet $run]
  if {[llength $obj]==1} {
   set status [get_property STATUS $obj]
   if {"NEEDS_REFRESH" in [list_property $obj]} {set refresh [get_property NEEDS_REFRESH $obj]}
  }
  puts $f "$name\t$run\t$status\t$refresh\t$locked";flush $f
  if {![string match "*synth_design Complete*" $status] || [string tolower $refresh] ni {0 false} || [string tolower $locked] ni {0 false}} {lappend problems $run}
 }
 close $f
 if {$count!=45 || [llength $problems]} {error "45 unchanged completed IPs required; phase=$phase count=$count invalid=$problems; no dependency rebuild authorized"}
 puts "OTA004_A06R1_REUSED_IPS_READY phase=$phase count=45 needs_refresh=false"
}


set memories {ip/rom/fine_ps1_reference_16lane.mem ip/rom/residual_pilot_phase.mem ip/cfo/cfo_rot_lut.mem ip/cfo/fft2048_twiddle.mem ip/cfo/front2048_coefficient_index.mem ip/cfo/front2048_coefficient_table.mem ip/cfo/fft256_twiddle.mem ip/cfo/phase74_atan_q31.mem}
if {![file exists $xpr]} {error "reuse of accepted A04 prepare requires the existing root project"}
open_project $xpr
if {$stage eq "smoke"} {
 file copy $xpr [file join $out project_before_source_update.xpr]
 foreach spec {{sources_1 rtl/control/sync_ota_top_a05.sv rtl/control/sync_ota_top_a06.sv} {sources_1 rtl/cfo/ota_cfo_chain_a02.sv rtl/cfo/ota_cfo_chain_a06.sv} {sources_1 rtl/common/ota_async_fifo.sv rtl/common/ota_async_fifo_a06.sv} {sources_1 rtl/cfo/cfo_estimator_link_v2.sv rtl/cfo/cfo_estimator_link_a06.sv} {sim_1 sim/tb/sync_ota_smoke_tb_a05.sv sim/tb/sync_ota_smoke_tb_a06.sv}} {
  lassign $spec fs oldrel newrel
  set oldp [file join $root $oldrel];set newp [file join $root $newrel]
  set oldmember [get_files -quiet $oldp]
  if {[llength $oldmember]} {remove_files $oldmember}
  if {![llength [get_files -quiet $newp]]} {add_files -fileset $fs -norecurse $newp}
  set_property LIBRARY ota_xpm [get_files $newp]
 }
 set_property top sync_ota_top [get_filesets sources_1]
 set_property top sync_ota_smoke_tb [get_filesets sim_1]
}
# Retain pinned copies for provenance; exactly one official synthesis mechanism.
foreach name {xpm_cdc xpm_fifo xpm_memory} {
 set p [get_files [file join $root rtl/vendor/xpm/${name}.sv]]
 set_property USED_IN_SYNTHESIS false $p
 set_property USED_IN_SIMULATION false $p
}
if {$stage eq "synth"} {
 set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
}

source $hook
hooks
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
audit_project
audit_reused_ips before_stage
puts "OTA004_IDENTITY stage=$stage vivado=[version -short] part=[get_property PART [current_project]] top=[get_property TOP [get_filesets sources_1]] ip_count=[llength [get_ips]] xelab=[get_property xsim.elaborate.mt_level [get_filesets sim_1]]"
set failed [catch {
switch -- $stage {
 smoke {
  set simdir [file join $root Sync_OTA.sim sim_1 behav xsim];file mkdir $simdir
  foreach rel $memories {
   set dst [file join $simdir [file tail $rel]]
   if {![file exists $dst]} {file copy [file join $root $rel] $dst}
  }
  launch_simulation
  puts [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_ota004_a06r1_project.py] $out $simdir]
  set binding [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_ota004_a06_binding.py] $simdir]
  puts $binding;set f [open [file join $out binding_verified.json] w];puts $f $binding;close $f
  run all
  set f [open [file join $simdir result.txt] r];set marker [string trim [read $f]];close $f
  if {$marker ne "OTA004_REAL_TOP_SMOKE_PASS"} {error "real top smoke marker missing"}
  close_sim
  puts [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_ota004_a06_sim_result.py] $simdir $out]
 }
 synth {
  # The 45 successful IP OOC checkpoints are frozen inputs; never relaunch them.
  audit_reused_ips before_core_decision
  set reuse_core 0
  set prior_script [file join $root Sync_OTA.runs synth_1 sync_ota_top.tcl]
  if {[string match "*synth_design Complete*" [get_property STATUS [get_runs synth_1]]] && [file exists $prior_script]} {
   set f [open $prior_script r];set prior [read $f];close $f
   set seen_a06 0
   foreach rel {rtl/control/sync_ota_top_a06.sv rtl/cfo/ota_cfo_chain_a06.sv rtl/common/ota_async_fifo_a06.sv rtl/cfo/cfo_estimator_link_a06.sv} {
    if {[string first [file normalize [file join $root $rel]] $prior]>=0} {incr seen_a06}
   }
   if {$seen_a06>0} {
    if {$seen_a06!=4 || [get_property NEEDS_REFRESH [get_runs synth_1]]} {error "completed A06-like core has partial/stale identity; preserve and review before any retry"}
    verify_prior_core_sources $prior
    set reuse_core 1
   }
  }
  if {!$reuse_core} {
   puts [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/archive_ota004_a06_previous_core.py] $out]
   reset_run synth_1
   set_property -dict [list {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context} STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none] [get_runs synth_1]
   hooks
   puts "OTA004_BUILD_PARALLELISM ip_jobs=0_reuse45 core_launch_jobs=16 per_process_general=8 per_process_synth=8"
   audit_reused_ips immediately_before_core_launch
   launch_runs synth_1 -jobs 16
   wait_on_run synth_1
  } else {puts "OTA004_REUSE_COMPLETED_A06_CORE report/export recovery only"}
  if {![string match "*synth_design Complete*" [get_property STATUS [get_runs synth_1]]]} {error "core synthesis failed"}
  audit_reused_ips after_core
  open_run synth_1
  set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
  if {[llength $blackboxes]} {error "algorithm/IP black boxes remain: $blackboxes"}
  foreach cell {frontend sfo cfo control ddr cfo/first_rotation cfo/second_rotation cfo/observation_front cfo/observation_backend busy_sync/src_ff_reg fault_sync/src_ff_reg cancel_request125_reg cfo/compute_cancel150_reg} {
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
  report_exceptions -file [file join $out synth_exceptions.txt]
  write_xdc [file join $out synth_applied_constraints.xdc]
  source [file join $root tools/vivado/audit_ota004_a06r1_gray.tcl]
  ota_a06r1_gray_audit $out
  set f [open [file join $out cdc_report_completed.txt] w];puts $f "Vivado2021.1 sync_ota_top report_cdc -details completed";close $f
  set f [open [file join $out synth_identity.txt] w]
  puts $f "TOP=sync_ota_top PART=xcvu11p-flgb2104-2-e BLACKBOX=0 CLOCKS=125/150/500MHz MODE=out_of_context PHYSICAL_TIMING=NOT_RUN"
  close $f
  close_design
  puts [exec C:/Python314/python.exe -I -B -X utf8 [file join $root tools/verify_ota004_a06r1_synth_result.py] $out]
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
