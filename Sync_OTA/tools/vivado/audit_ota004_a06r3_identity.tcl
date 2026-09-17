# Verify scientific identity using locked DCP metadata, actual project part,
# and required core hierarchy. A design reference NAME is informational.
proc ota_a06r3_identity {out} {
 set design [current_design]
 if {[llength $design]!=1} {error "expected one opened design"}
 set project [current_project]
 if {[llength $project]!=1} {error "expected one active in-memory project"}
 set f [open [file join $out runtime_design_properties.txt] w]
 puts $f [list DESIGN_OBJECT $design PROJECT_OBJECT $project]
 puts $f [list EXPECTED_TOP sync_ota_top EXPECTED_PART xcvu11p-flgb2104-2-e TOP_SOURCE LOCKED_DCP_XML_AND_SYNTH_PROVENANCE]
 set props [list_property $design]
 puts $f [list DESIGN_PROPERTIES $props]
 foreach key {NAME CLASS PART TOP REF_NAME DESIGN_MODE} {
  if {$key in $props} {
   set code [catch {get_property $key $design} value options]
   puts $f [list DESIGN_PROPERTY $key QUERY_CODE $code VALUE $value]
  } else {puts $f [list DESIGN_PROPERTY $key UNAVAILABLE]}
 }
 flush $f
 set part [get_property PART $project]
 puts $f [list PROJECT_PART $part EXPECTED xcvu11p-flgb2104-2-e EQUAL [expr {$part eq "xcvu11p-flgb2104-2-e"}]]
 flush $f
 if {$part ne "xcvu11p-flgb2104-2-e"} {close $f;error "active project part differs from locked scientific target"}
 if {"PART" in $props} {
  set designPart [get_property PART $design]
  if {$designPart ne $part} {close $f;error "design PART conflicts with active project PART"}
 }
 set blackboxes [get_cells -hierarchical -filter {IS_BLACKBOX == 1}]
 puts $f [list BLACKBOX_COUNT [llength $blackboxes]];flush $f
 if {[llength $blackboxes]} {close $f;error "locked core contains blackboxes"}
 foreach cell {frontend sfo cfo control ddr cfo/first_rotation cfo/second_rotation cfo/observation_front cfo/observation_backend busy_sync/src_ff_reg fault_sync/src_ff_reg cancel_request125_reg cfo/compute_cancel150_reg} {
  set actual [get_cells $cell]
  puts $f [list REQUIRED_CELL $cell OBJECTS $actual];flush $f
  if {[llength $actual]!=1 || [get_property NAME $actual] ne $cell} {close $f;error "required core hierarchy absent/ambiguous: $cell"}
 }
 puts $f "IDENTITY_EVIDENCE_COMPLETE DESIGN_NAME_IS_NOT_RTL_TOP_GATE";close $f
 set f [open [file join $out report_identity.txt] w]
 puts $f "TOP=sync_ota_top PART=xcvu11p-flgb2104-2-e BLACKBOX=0 MODE=OPEN_EXISTING_A06R1_DCP REPORT_ONLY=1";close $f
}
