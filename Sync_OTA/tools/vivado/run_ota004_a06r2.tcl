# A06R2 report recovery only: no open_project, reset/launch_run or synthesis.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc!=2 || [lindex $argv 0] ne "report"} {error "usage: -tclargs report <new-attempt>"}
set out [file normalize [lindex $argv 1]]
if {![file isdirectory $out] || [file dirname $out] ne [file join $root work OTA004] || ![regexp {^report_a06r2(?:_[A-Za-z0-9-]+)?$} [file tail $out]]} {error "wrong independent recovery attempt"}
if {[version -short] ne "2021.1"} {error "frozen Vivado version required"}
set dcp [file join $root work/OTA004/synth_a06r1/sync_ota_synth.dcp]
set checker [file join $root tools/verify_ota004_a06r2_report.py]
puts [exec C:/Python314/python.exe -I -B -X utf8 $checker --precheck $out]
set_param general.maxThreads 8
set_param synth.maxThreads 8
set f [open [file join $out runtime_identity.txt] w]
puts $f "VERSION=[version -short] GENERAL_THREADS=[get_param general.maxThreads] SYNTH_THREADS=[get_param synth.maxThreads] MODE=REPORT_ONLY NEW_SYNTH=0 IP_JOBS=0 DCP=$dcp";close $f
set failed [catch {
 open_checkpoint $dcp
 if {[get_property NAME [current_design]] ne "sync_ota_top" || [get_property PART [current_design]] ne "xcvu11p-flgb2104-2-e"} {error "wrong existing DCP design identity"}
 set blackboxes [get_cells -hierarchical -filter {IS_BLACKBOX == 1}]
 if {[llength $blackboxes]} {error "DCP contains blackboxes: $blackboxes"}
 set f [open [file join $out report_identity.txt] w]
 puts $f "TOP=sync_ota_top PART=xcvu11p-flgb2104-2-e BLACKBOX=0 MODE=OPEN_EXISTING_A06R1_DCP REPORT_ONLY=1";close $f
 report_clocks -file [file join $out synth_clocks.txt]
 report_cdc -details -file [file join $out synth_cdc.txt]
 set f [open [file join $out cdc_report_completed.txt] w];puts $f "Vivado2021.1 sync_ota_top report_cdc -details completed";close $f
 report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out synth_timing.txt]
 write_xdc [file join $out synth_applied_constraints.xdc]
 # Bound path coverage first, so an audit-format failure does not lose the
 # source evidence needed for the authorized subsequent minimal RTL repair.
 source [file join $root tools/vivado/report_ota004_a06r2_timing.tcl]
 ota_a06r2_timing_coverage $out
 source [file join $root tools/vivado/audit_ota004_a06r2_gray.tcl]
 ota_a06r2_gray_audit $out
 close_design
 puts [exec C:/Python314/python.exe -I -B -X utf8 $checker --review $out]
} message options]
if {$failed} {
 set f [open [file join $out failure.txt] w];puts $f $message;puts $f $options;close $f
 puts stderr "OTA004_A06R2_REPORT_FAILED $message"
 catch {close_design}
 exit 1
}
set f [open [file join $out result.txt] w];puts $f OTA004_A06R2_REPORT_RECOVERY_COMPLETE;close $f
puts "OTA004_NATIVE_DONE stage=report ORIGINAL_DCP_UNCHANGED=1"
exit 0

