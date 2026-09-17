# Independent identity-only proposal; separate explicit grant required.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc!=2 || [lindex $argv 0] ne "identity"} {error "usage: -tclargs identity <new-attempt>"}
set out [file normalize [lindex $argv 1]]
if {![file isdirectory $out] || [file dirname $out] ne [file join $root work OTA004] || ![regexp {^identity_a06r2i1(?:_[A-Za-z0-9-]+)?$} [file tail $out]]} {error "wrong independent identity attempt"}
if {[version -short] ne "2021.1"} {error "frozen Vivado version required"}
set checker [file join $root tools/verify_ota004_a06r2i1_inputs.py]
puts [exec C:/Python314/python.exe -I -B -X utf8 $checker $out]
set_param general.maxThreads 8
set_param synth.maxThreads 8
set dcp [file join $root work/OTA004/synth_a06r1/sync_ota_synth.dcp]
set f [open [file join $out runtime_identity.txt] {WRONLY CREAT EXCL}]
puts $f "VERSION=[version -short] GENERAL_THREADS=[get_param general.maxThreads] SYNTH_THREADS=[get_param synth.maxThreads] MODE=IDENTITY_ONLY NEW_SYNTH=0 IP_JOBS=0 DCP=$dcp";close $f
source [file join $root tools/vivado/audit_ota004_a06r2i1_identity.tcl]
set failed [catch {
 open_checkpoint $dcp
 set diagnostic [ota_a06r2i1_identity $out]
 puts "OTA004_IDENTITY_DIAGNOSTIC $diagnostic"
} message options]
if {$failed} {
 set f [open [file join $out failure.txt] {WRONLY CREAT EXCL}]
 puts $f $message;puts $f $options;close $f
 puts stderr "OTA004_A06R2I1_IDENTITY_HOLD $message"
}
set closeCode [catch {close_design} closeMessage closeOptions]
set f [open [file join $out close_status.txt] {WRONLY CREAT EXCL}]
puts $f [list code $closeCode message $closeMessage options $closeOptions];close $f
# Recheck immutable files after close; no native rerun for an offline failure.
set postCode [catch {exec C:/Python314/python.exe -I -B -X utf8 $checker $out --post} postMessage]
puts $postMessage
if {$failed || $closeCode || $postCode} {exit 1}
puts "OTA004_A06R2I1_IDENTITY_ONLY_COMPLETE NOT_REPORT_RECOVERY NOT_QUALIFICATION"
exit 0
