# One bounded read-only coverage pass over the existing synthesized DCP.
proc ota_a06r3_timing_coverage {out} {
 set dir [file join $out timing_coverage];file mkdir $dir
 set f [open [file join $dir paths.tsv] w]
 puts $f "query\tclock\ttarget_scope\trank\tstartpoint_pin\tendpoint_pin\tslack_ns\trequirement_ns"
 set q [open [file join $dir queries.tsv] w]
 puts $q "query\tclock\ttarget_scope\tcap\treturned"
 set queries {
  {clk125 all 4} {clk150 all 32} {clk500 all 32}
  {clk150 cfo/observation_backend 8}
  {clk150 sfo/two_pass_transport/output_buffer 8}
  {clk150 cfo 8} {clk150 sfo 8}
  {clk500 cfo/observation_front 8}
  {clk500 sfo/initial_estimator 8}
 }
 set id 0
 foreach spec $queries {
  incr id;lassign $spec clock scope cap
  set from [get_clocks $clock]
  if {[llength $from]!=1} {error "timing clock missing/ambiguous: $clock"}
  if {$scope eq "all"} {set targets $from
  } else {
   if {[llength [get_cells $scope]]!=1} {error "required timing hierarchy absent: $scope"}
   set targets [get_cells -hierarchical -filter "IS_PRIMITIVE == 1 && NAME =~ $scope/*"]
   if {![llength $targets]} {error "timing scope has no primitive endpoints: $scope"}
  }
  set paths [get_timing_paths -from $from -to $targets -delay_type max -max_paths $cap -nworst 1]
  if {![llength $paths] || [llength $paths]>$cap} {error "bounded timing query missing/exceeded: $spec"}
  puts $q "$id\t$clock\t$scope\t$cap\t[llength $paths]";flush $q
  set rank 0
  foreach path $paths {
   incr rank
   puts $f "$id\t$clock\t$scope\t$rank\t[get_property STARTPOINT_PIN $path]\t[get_property ENDPOINT_PIN $path]\t[get_property SLACK $path]\t[get_property REQUIREMENT $path]"
  }
  flush $f
  report_timing -of_objects $paths -path_type full -input_pins -file [file join $dir paths_$id.txt]
 }
 close $f;close $q
 set f [open [file join $dir completed.txt] w]
 puts $f "OTA004_A06R3_BOUNDED_TIMING_EXPORT_COMPLETE queries=9 max_paths_total=116";close $f
}

