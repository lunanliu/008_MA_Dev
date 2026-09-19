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
  report_utilization -hierarchical -file [file join $out utilization_hierarchical_routed.rpt]
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
    if {$i==0} {set pf [open [file join $out timing_path_properties.txt] w];foreach property $available {puts $pf "$property = [get_property $property $p]"};close $pf}
    set row {};foreach key $columns {lappend row [safe_prop $p $key $available]}
    emit_csv $fh $row
    incr i
    if {$i%500==0} {flush $fh;puts "AUDIT_EXPORTED $i [clock seconds]"}
  }
  close $fh
  # Full paths to the same failing endpoints expose primitive/net delay and fanout.
  report_timing -delay_type max -slack_lesser_than 0.0 -max_paths 20000 -nworst 1 -input_pins -significant_digits 6 -file [file join $out failing_paths_full.rpt]
  set roms [get_cells -hier -filter {NAME =~ cfo/observation_front/coefficient_page*_data_reg_* && REF_NAME =~ RAMB*}]
  set commands [get_cells -hier -filter {NAME =~ cfo/observation_front/coefficient_read_command_reg*}]
  set rows [get_cells -hier -filter {NAME =~ cfo/observation_front/coefficient_row_reg*}]
  set nf [open [file join $out coefficient_mapping.txt] w]
  puts $nf "ROM_COUNT [llength $roms] COMMAND_FFS [llength $commands] ROW_FFS [llength $rows]"
  foreach c [concat $roms $commands $rows] {
    puts $nf "$c REF_NAME=[get_property REF_NAME $c] LOC=[get_property LOC $c] DONT_TOUCH=[get_property DONT_TOUCH $c]"
  }
  close $nf
  if {[llength $roms]!=6 || [llength $commands]!=2 || [llength $rows]!=15} {error "Unexpected plan-A mapping; inspect coefficient_mapping.txt"}
  set enpins [get_pins -of_objects $roms -filter {REF_PIN_NAME == ENARDEN}]
  set addrpins [get_pins -of_objects $roms -filter {REF_PIN_NAME =~ ADDRARDADDR*}]
  report_timing -to $enpins -delay_type max -max_paths 20 -nworst 1 -significant_digits 6 -file [file join $out coefficient_enable_paths.rpt]
  report_timing -to $addrpins -delay_type max -max_paths 120 -nworst 1 -significant_digits 6 -file [file join $out coefficient_address_paths.rpt]
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
