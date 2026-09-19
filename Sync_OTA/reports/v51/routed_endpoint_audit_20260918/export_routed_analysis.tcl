# Read-only analysis of the user's completed routed checkpoint.
# Never synthesize, optimize, place, route, change constraints, or write a DCP here.
set out [file normalize [lindex $argv 0]]
set dcp [file normalize [lindex $argv 1]]
set_param general.maxThreads 8
catch {set_param synth.maxThreads 8}
proc safe_prop {object property available} {
  if {[lsearch -exact $available $property] >= 0} {return [get_property $property $object]}
  return ""
}
proc csv {value} {
  return "\"[string map [list \" \"\"] $value]\""
}
proc emit_csv {fh fields} {
  set q {};foreach x $fields {lappend q [csv $x]};puts $fh [join $q ,]
}
proc main {out dcp} {
  puts "AUDIT_OPEN_BEGIN [clock seconds]"
  open_checkpoint $dcp
  puts "AUDIT_OPEN_COMPLETE [clock seconds]"
  report_timing_summary -max_paths 1 -file [file join $out timing_summary_checkpoint.rpt]
  report_utilization -hierarchical -hierarchical_depth 8 -file [file join $out utilization_hierarchical_routed.rpt]
  puts "AUDIT_PATH_QUERY_BEGIN [clock seconds]"
  set paths [get_timing_paths -delay_type max -slack_lesser_than 0.0 -max_paths 20000 -nworst 1]
  set n [llength $paths]
  puts "AUDIT_PATH_COUNT $n"
  if {$n >= 20000} {error "Path export cap reached; completeness not established"}
  set fh [open [file join $out failing_endpoints.csv] w]
  set columns {GROUP SLACK REQUIREMENT STARTPOINT_PIN ENDPOINT_PIN STARTPOINT_CLOCK ENDPOINT_CLOCK DATAPATH_DELAY LOGIC_LEVELS SKEW UNCERTAINTY}
  emit_csv $fh $columns
  set i 0
  foreach p $paths {
    set available [list_property $p]
    if {$i==0} {redirect -file [file join $out timing_path_properties.txt] {report_property -all $p}}
    set row {};foreach key $columns {lappend row [safe_prop $p $key $available]}
    emit_csv $fh $row
    incr i
    if {$i%500==0} {flush $fh;puts "AUDIT_EXPORTED $i [clock seconds]"}
  }
  close $fh
  # Full paths to the same failing endpoints expose primitive/net delay and fanout.
  report_timing -delay_type max -slack_lesser_than 0.0 -max_paths 20000 -nworst 1 -input_pins -significant_digits 6 -file [file join $out failing_paths_full.rpt]
  report_clock_interaction -file [file join $out clock_interaction.rpt]
  report_cdc -details -file [file join $out cdc_details.rpt]
  set fh [open [file join $out COMPLETE.txt] w]
  puts $fh "READ_ONLY_ROUTED_ANALYSIS_COMPLETE paths=$n tool=[version -short] finished_epoch=[clock seconds]"
  close $fh
  close_design
}
if {[catch {main $out $dcp} e opts]} {
  set fh [open [file join $out FAILED.txt] w];puts $fh $e;puts $fh [dict get $opts -errorinfo];close $fh
  puts stderr $e
  exit 1
}
exit 0
