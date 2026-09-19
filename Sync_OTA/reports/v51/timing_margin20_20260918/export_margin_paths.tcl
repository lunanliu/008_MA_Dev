# Read-only query of existing routed design. No constraint or netlist mutation.
set_param general.maxThreads 8
set out [file normalize [lindex $argv 0]]
set dcp [file normalize [lindex $argv 1]]
proc csv {value} {return "\"[string map [list \" \"\"] $value]\""}
proc main {out dcp} {
 open_checkpoint $dcp
 set counts [open [file join $out margin_counts.csv] w]
 puts $counts "clock,period_ns,minimum_wns_ns,endpoint_count,worst_slack_ns"
 foreach {clk period limit} {clk125 8.0 1.6 clk150 6.666666667 1.333333334 clk500 2.0 0.4} {
  puts "MARGIN_QUERY_BEGIN $clk [clock seconds]"
  set paths [get_timing_paths -group $clk -delay_type max -slack_lesser_than $limit -max_paths 200000 -nworst 1]
  set n [llength $paths]
  if {$n>=200000} {error "Path cap reached for $clk"}
  set fh [open [file join $out ${clk}_below_margin.csv] w]
  puts $fh "GROUP,SLACK,REQUIREMENT,STARTPOINT_PIN,ENDPOINT_PIN,DATAPATH_DELAY,LOGIC_LEVELS"
  set i 0
  foreach p $paths {
   set row {}
   foreach key {GROUP SLACK REQUIREMENT STARTPOINT_PIN ENDPOINT_PIN DATAPATH_DELAY LOGIC_LEVELS} {lappend row [csv [get_property $key $p]]}
   puts $fh [join $row ,]
   incr i
   if {$i%2000==0} {flush $fh;puts "MARGIN_EXPORTED $clk $i [clock seconds]"}
  }
  close $fh
  set worst ""
  if {$n>0} {set worst [get_property SLACK [lindex $paths 0]]}
  puts $counts "$clk,$period,$limit,$n,$worst"
  flush $counts
  report_timing -group $clk -delay_type max -slack_lesser_than $limit -max_paths 100 -nworst 1 -input_pins -significant_digits 3 -file [file join $out ${clk}_worst100.rpt]
  puts "MARGIN_QUERY_COMPLETE $clk $n [clock seconds]"
 }
 close $counts
 close_design
 set f [open [file join $out COMPLETE.txt] w];puts $f "READ_ONLY_MARGIN_ANALYSIS_COMPLETE [clock seconds]";close $f
}
if {[catch {main $out $dcp} e opts]} {
 set f [open [file join $out FAILED.txt] w];puts $f $e;puts $f [dict get $opts -errorinfo];close $f
 puts stderr $e
 exit 1
}
exit 0
