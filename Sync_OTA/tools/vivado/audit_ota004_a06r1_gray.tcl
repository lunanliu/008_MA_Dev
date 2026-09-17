# Read-only audit inside the existing open synthesized design.
# No set_* constraint is applied by this helper. A safe interpreter captures
# selected exported commands; its only aliases are read-only object queries.
namespace eval ota_gray {variable captured {};variable export_kind ""}
proc ota_gray::query {kind args} {
 set objects [uplevel #0 [linsert $args 0 $kind]]
 if {![llength $objects]} {error "unresolved exported Gray constraint: $kind $args"}
 return [get_property NAME $objects]
}
proc ota_gray::capture {kind args} {
 variable captured;variable export_kind
 set from {};set to {};set value "";set datapath 0
 for {set i 0} {$i<[llength $args]} {incr i} {
  set a [lindex $args $i]
  switch -- $a {
   -from {incr i;set from [lindex $args $i]}
   -to {incr i;set to [lindex $args $i]}
   -datapath_only {set datapath 1}
   default {
    if {![string is double -strict $a] || $value ne ""} {error "unsupported Gray constraint argument: $a"}
    set value $a
   }
  }
 }
 if {$value eq "" || $value<=0 || ![llength $from] || ![llength $to]} {error "incomplete Gray constraint"}
 lappend captured [list $export_kind $kind $value $datapath [lsort -unique $from] [lsort -unique $to]]
}
proc ota_gray::read_export {path origin kinds} {
 variable export_kind
 set export_kind $origin
 set sandbox [interp create -safe]
 # Exported Gray constraints need only these query/list commands. Hide all other
 # commands, including eval/source/current_instance, rather than apply any XDC.
 foreach c [$sandbox eval {info commands}] {
  if {$c ne "list"} {interp hide $sandbox $c}
 }
 foreach c {get_cells get_pins get_clocks get_ports get_nets} {interp alias $sandbox $c {} ota_gray::query $c}
 foreach c {set_max_delay set_bus_skew} {interp alias $sandbox $c {} ota_gray::capture $c}
 set f [open $path r];set body [read $f];close $f
 set command ""
 foreach line [split $body "\n"] {
  if {$command eq "" && ([string trim $line] eq "" || [string match "#*" [string trimleft $line]])} {continue}
  append command $line "\n"
  if {![info complete $command]} {continue}
  set trimmed [string trim $command]
  if {[regexp {^(set_max_delay|set_bus_skew)\s} $trimmed -> kind] && $kind in $kinds && [string first "src_gray_ff" $trimmed]>=0} {
   # current_instance-relative exports are unsupported: the resolved objects
   # must later exactly match complete core-rooted instance endpoint sets.
   $sandbox eval $trimmed
  }
  set command ""
 }
 interp delete $sandbox
 if {[string trim $command] ne ""} {error "truncated exported constraint command: $path"}
}
proc ota_gray::one_clock {cells} {
 set clocks [get_clocks -of_objects [get_pins -of_objects $cells -filter {REF_PIN_NAME == C}]]
 if {[llength $clocks]!=1} {error "Gray endpoint has missing/ambiguous clock: $cells $clocks"}
 return [list [get_property NAME $clocks] [get_property PERIOD $clocks]]
}
proc ota_a06r1_gray_audit {out} {
 set dir [file join $out gray_constraints];file mkdir $dir
 set groups [open [file join $dir groups.tsv] w]
 puts $groups "id\tfifo\tgray\tsource_clock\tdestination_clock\tsource_period\tdestination_period\twidth"
 set endpoints [open [file join $dir endpoints.tsv] w]
 puts $endpoints "id\trole\tcell"
 set timing [open [file join $dir effective_timing.tsv] w]
 puts $timing "id\tdestination_cell\tstartpoint_pin\tendpoint_pin\trequirement"
 set constraints [open [file join $dir constraints.tsv] w]
 puts $constraints "id\torigin\tkind\tvalue\tdatapath_only\tfrom\tto"
 # Validate max-delay from actual valid timing exceptions, not raw XDC text.
 report_exceptions -write_valid_exceptions -file [file join $dir valid_exceptions.xdc]
 set ota_gray::captured {}
 ota_gray::read_export [file join $dir valid_exceptions.xdc] VALID_EXCEPTIONS {set_max_delay}
 ota_gray::read_export [file join $out synth_applied_constraints.xdc] APPLIED_XDC {set_bus_skew}
 set roots {metadata/fifo completion/fifo ddr/requests/fifo ddr/responses/fifo cfo/window_samples/fifo cfo/observation_backend/observation_fifo}
 set all [get_cells -hierarchical -filter {NAME =~ *src_gray_ff_reg* || NAME =~ *dest_graysync_ff_reg*}]
 set expected_gray {}
 foreach fifo $roots {
  foreach type {wr_pntr_cdc_inst wr_pntr_cdc_dc_inst rd_pntr_cdc_inst rd_pntr_cdc_dc_inst} {
   lappend expected_gray $fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.$type
  }
 }
 set actual_gray {}
 foreach cell $all {
  set name [get_property NAME $cell]
  foreach fifo $roots {
   if {[string first "$fifo/" $name]==0 && [regexp {^(.*)/src_gray_ff_reg\[[0-9]+\]$} $name -> macro]} {lappend actual_gray $macro}
  }
 }
 if {[lsort -unique $actual_gray] ne [lsort $expected_gray]} {error "unexpected/missing Gray macros in required FIFO instances: $actual_gray"}
 set id 0
 foreach fifo $roots {
  # All four actual Gray pointer/count macros are expected in these frozen
  # FIFO configurations. Missing/extra macros or optimized/missing bits fail.
  foreach type {wr_pntr_cdc_inst wr_pntr_cdc_dc_inst rd_pntr_cdc_inst rd_pntr_cdc_dc_inst} {
   incr id
   set gray $fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.$type
   set src {};set dst {}
   foreach cell $all {
    set name [get_property NAME $cell]
    if {[string first "$gray/" $name]!=0} {continue}
    set tail [string range $name [expr {[string length $gray]+1}] end]
    if {[regexp {^src_gray_ff_reg\[[0-9]+\]$} $tail]} {lappend src $cell}
    if {[regexp {^dest_graysync_ff_reg\[0\]\[[0-9]+\]$} $tail]} {lappend dst $cell}
   }
   set width [expr {$fifo eq "cfo/observation_backend/observation_fifo" ? 4 : 5}]
   if {[string match "*_dc_inst" $type]} {incr width}
   if {[llength $src]!=$width || [llength $dst]!=$width} {error "Gray endpoint width mismatch: $gray expected=$width src=$src dst=$dst"}
   set srcnames [lsort -unique [get_property NAME $src]]
   set dstnames [lsort -unique [get_property NAME $dst]]
   lassign [ota_gray::one_clock $src] sc sp
   lassign [ota_gray::one_clock $dst] dc dp
   if {$sc eq $dc} {error "expected asynchronous Gray crossing: $gray"}
   puts $groups "$id\t$fifo\t$gray\t$sc\t$dc\t$sp\t$dp\t$width";flush $groups
   foreach name $srcnames {puts $endpoints "$id\tSRC\t$name"}
   foreach name $dstnames {puts $endpoints "$id\tDST\t$name"}
   set found {}
   foreach constraint $ota_gray::captured {
    lassign $constraint origin kind value datapath from to
    if {$from ne $srcnames || $to ne $dstnames} {continue}
    set expected [expr {$kind eq "set_max_delay" ? $sp : min($sp,$dp)}]
    if {abs($value-$expected)>0.0011 || ($kind eq "set_max_delay" && !$datapath)} {error "incorrect effective Gray constraint: $gray $constraint"}
    lappend found $kind
    puts $constraints "$id\t$origin\t$kind\t$value\t$datapath\t[join $from |]\t[join $to |]"
   }
   if {[lsort -unique $found] ne {set_bus_skew set_max_delay}} {error "missing exact instance/endpoint scoped constraints: $gray $found"}
   # Check every destination bit has a live timing path with the max-delay
   # requirement; a false-path/clock-group override cannot pass this check.
   foreach cell $dst {
    set d [get_pins -of_objects $cell -filter {REF_PIN_NAME == D}]
    if {[llength $d]!=1} {error "Gray D pin missing: $cell"}
    set paths [get_timing_paths -from $src -to $d -delay_type max -max_paths 1 -nworst 1]
    if {[llength $paths]!=1} {error "Gray path absent/overridden: $gray $d"}
    set requirement [get_property REQUIREMENT $paths]
    if {![string is double -strict $requirement] || abs($requirement-$sp)>0.0011} {error "effective Gray max-delay mismatch: $gray $d $requirement"}
    puts $timing "$id\t[get_property NAME $cell]\t[get_property STARTPOINT_PIN $paths]\t[get_property ENDPOINT_PIN $paths]\t$requirement"
   }
   # Native active bus-skew report scoped to this exact actual Gray hierarchy.
   # Python validates identity, scoped endpoints and a numeric requirement.
   set obj [get_cells $gray]
   if {[llength $obj]!=1} {error "missing Gray hierarchy: $gray"}
   report_bus_skew -cells $obj -no_detailed_paths -file [file join $dir bus_skew_$id.txt]
  }
 }
 foreach f [list $groups $endpoints $timing $constraints] {close $f}
 if {$id!=24} {error "expected 24 bidirectional Gray macros"}
 set f [open [file join $dir completed.txt] w]
 puts $f "OTA004_A06R1_GRAY_EXPORT_COMPLETE groups=24";close $f
}

