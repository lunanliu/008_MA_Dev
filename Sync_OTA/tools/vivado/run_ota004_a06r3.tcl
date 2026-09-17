# New original-scope verification. Execution-only repairs may use a new bundle.
set root D:/008_MA_Dev/Sync_OTA
set bundle [file normalize [file join [file dirname [info script]] ../..]]
if {$argc!=2 || [lindex $argv 0] ne "report"} {error "usage: -tclargs report <new-attempt>"}
set out [file normalize [lindex $argv 1]]
if {![file isdirectory $out] || [file dirname $out] ne [file join $root work OTA004] || ![regexp {^report_a06r3(?:_[A-Za-z0-9-]+)?$} [file tail $out]]} {error "wrong independent validation attempt"}
if {[version -short] ne "2021.1"} {error "Vivado2021.1 required"}
set checker [file join $bundle tools/verify_ota004_a06r3_report.py]
puts [exec C:/Python314/python.exe -I -B -X utf8 $checker --precheck $out]
set_param general.maxThreads 8
set_param synth.maxThreads 8
set f [open [file join $out runtime_identity.txt] w]
puts $f "VERSION=[version -short] GENERAL_THREADS=[get_param general.maxThreads] SYNTH_THREADS=[get_param synth.maxThreads] MODE=REPORT_ONLY NEW_SYNTH=0 IP_JOBS=0";close $f
set dcp [file join $root work/OTA004/synth_a06r1/sync_ota_synth.dcp]
set failures {}
proc ota_collect {name command} {
 set code [catch {uplevel 1 $command} message options]
 puts $::stageFile [list STAGE $name CODE $code MESSAGE $message OPTIONS $options];flush $::stageFile
 if {$code} {lappend ::failures $name;puts stderr "OTA004_COLLECTION_STAGE_HOLD $name $message"}
 return [expr {!$code}]
}
set stageFile [open [file join $out collection_stages.tcldata] w]
set ready [ota_collect open_checkpoint {open_checkpoint $dcp}]
if {$ready} {
 source [file join $bundle tools/vivado/audit_ota004_a06r3_identity.tcl]
 set ready [ota_collect scientific_identity {ota_a06r3_identity $out}]
}
if {$ready} {
 ota_collect clocks {report_clocks -file [file join $out synth_clocks.txt]}
 if {[ota_collect cdc {report_cdc -details -file [file join $out synth_cdc.txt]}]} {
  set f [open [file join $out cdc_report_completed.txt] w];puts $f "Vivado2021.1 sync_ota_top report_cdc -details completed";close $f
 }
 ota_collect timing_summary {report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out synth_timing.txt]}
 set xdcReady [ota_collect applied_xdc {write_xdc [file join $out synth_applied_constraints.xdc]}]
 ota_collect timing_paths {
  source [file join $bundle tools/vivado/report_ota004_a06r3_timing.tcl]
  ota_a06r3_timing_coverage $out
 }
 if {$xdcReady} {
  ota_collect gray {
   source [file join $bundle tools/vivado/audit_ota004_a06r3_gray.tcl]
   ota_a06r3_gray_audit $out
  }
 }
}
ota_collect close_design {close_design}
close $stageFile
set f [open [file join $out collection_result.txt] w]
puts $f [list FAILED_STAGES $failures NATIVE_COLLECTION_FINISHED 1 QUALIFICATION NOT_DECIDED];close $f
# Strict parsing is offline; preserve every successful native stage if it fails.
set reviewCode [catch {exec C:/Python314/python.exe -I -B -X utf8 $checker --review $out} reviewMessage reviewOptions]
set f [open [file join $out offline_review_result.tcldata] w];puts $f [list CODE $reviewCode MESSAGE $reviewMessage OPTIONS $reviewOptions];close $f
puts $reviewMessage
if {[llength $failures] || $reviewCode} {
 set f [open [file join $out failure.txt] w];puts $f [list FAILED_STAGES $failures REVIEW_CODE $reviewCode REVIEW_MESSAGE $reviewMessage];close $f
 exit 1
}
set f [open [file join $out result.txt] w];puts $f OTA004_A06R3_REPORT_VERIFICATION_COMPLETE;close $f
puts "OTA004_NATIVE_DONE stage=report ORIGINAL_DCP_UNCHANGED=1"
exit 0
