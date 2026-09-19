# Shared definitions only; loading this file never launches an implementation.
namespace eval ota_margin20 {
    variable periods {clk125 8.0 clk150 6.666666667 clk500 2.0}
    variable state_file [file join [pwd] margin20_owned_state.tcl]
}
proc ota_margin20::signature {path} {
    set f [open $path r];set text [read $f];close $f
    set text [string map [list "\\\n" " "] $text]
    return [lsort [regexp -all -inline {(?m)^[ \t]*set_clock_uncertainty\M[^\n]*} $text]]
}
proc ota_margin20::check_clocks {} {
    variable periods
    if {[get_property PART [current_design]] ne "xcvu11p-flgb2104-2-e"} {error "Unexpected Sync_OTA device"}
    foreach {name expected} $periods {
        set c [get_clocks -quiet $name]
        if {[llength $c]!=1} {error "Missing or ambiguous clock $name"}
        # Vivado checkpoints serialize clock periods on a 1 ps grid.
        # Accept only the requested value or its exact nearest-ps representation;
        # this does not alter the clock, the margin target, or timing exceptions.
        set actual [get_property PERIOD $c]
        set quantized [expr {round($expected*1000.0)/1000.0}]
        if {abs($actual-$expected)>1.0e-8 && abs($actual-$quantized)>1.0e-8} {
            error "Clock period changed: $name actual=$actual expected=$expected (checkpoint=$quantized)"
        }
    }
}
proc ota_margin20::apply {} {
    variable periods;variable state_file
    check_clocks
    set out [file normalize [file join [pwd] margin20_[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]]]
    file mkdir $out
    set baseline [file join $out nominal_before_overlay.xdc]
    write_xdc -type timing -constraints all $baseline
    if {[llength [signature $baseline]]!=0} {
        error "Existing explicit clock uncertainty preserved. Review/merge it before applying margin20; never add margin twice. Snapshot: $baseline"
    }
    foreach {name period} $periods {
        set c [get_clocks $name]
        set_clock_uncertainty -setup -from $c -to $c [expr {0.2*$period}]
    }
    set guarded [file join $out tightened_after_overlay.xdc]
    write_xdc -type timing -constraints all $guarded
    set sig [signature $guarded]
    if {[llength $sig]!=3} {error "Unexpected overlay serialization; preserve evidence and inspect $guarded"}
    set f [open $state_file w]
    puts $f [list set ::ota_margin20::owned [dict create version 1 output $out uncertainty_signature $sig periods $periods]]
    close $f
    puts "MARGIN20: same-clock setup overlay applied; real clocks, jitter, hold and CDC max-delay unchanged. $out"
}
proc ota_margin20::validate_owned {} {
    variable state_file;variable periods;variable owned
    check_clocks
    if {![file exists $state_file]} {error "Missing margin20 ownership; start a fresh implementation from opt_design"}
    source $state_file
    if {[dict get $owned version]!=1 || [dict get $owned periods] ne $periods} {error "Overlay ownership mismatch"}
    set path [file join [dict get $owned output] controls_preflight_[clock clicks].xdc]
    write_xdc -type timing -constraints all $path
    if {[signature $path] ne [dict get $owned uncertainty_signature]} {error "Current design does not have the reviewed margin20 overlay; refusing physical optimization"}
}
proc ota_margin20::finish {} {
    variable state_file;variable periods;variable owned
    check_clocks
    if {![file exists $state_file]} {error "Missing owned overlay state; do not remove unknown uncertainty"}
    source $state_file
    if {[dict get $owned version]!=1 || [dict get $owned periods] ne $periods} {error "Overlay ownership mismatch"}
    set out [dict get $owned output]
    if {[file exists [file join $out nominal_summary.rpt]]} {error "This margin20 view was already finalized; preserve prior evidence"}
    set current [file join $out tightened_before_restore.xdc]
    write_xdc -type timing -constraints all $current
    if {[signature $current] ne [dict get $owned uncertainty_signature]} {
        error "Explicit uncertainty changed after overlay; refusing to replace user constraints"
    }
    write_checkpoint [file join $out routed_tightened.dcp]
    report_timing_summary -max_paths 100 -file [file join $out tightened_summary.rpt]
    foreach {name period} $periods {
        set c [get_clocks $name]
        set_clock_uncertainty -setup -from $c -to $c 0.0
    }
    write_checkpoint [file join $out routed_nominal.dcp]
    write_xdc -type timing -constraints all [file join $out nominal_after_restore.xdc]
    report_timing_summary -max_paths 100 -report_unconstrained -file [file join $out nominal_summary.rpt]
    report_utilization -hierarchical -hierarchical_depth 10 -file [file join $out nominal_utilization_hierarchical.rpt]
    report_clock_interaction -file [file join $out nominal_clock_interaction.rpt]
    report_cdc -file [file join $out nominal_cdc.rpt]
    report_exceptions -file [file join $out nominal_exceptions.rpt]
    check_timing -file [file join $out nominal_check_timing.rpt]
    set f [open [file join $out margin20_candidates.tsv] w]
    puts $f "FROM_CLOCK\tTO_CLOCK\tREQUIREMENT\tSLACK\tTARGET\tSTARTPOINT\tENDPOINT"
    set setup_fail 0;set hold_fail 0;set capped 0;set mixed 0;set cross_count 0
    set summary [open [file join $out margin20_gate.txt] w]
    puts $summary "constraint_view=NOMINAL\nqualification=NOT_INTEGRATION_QUALIFICATION"
    foreach {from period} $periods {
        foreach {to to_period} $periods {
            # Partition by source/destination clock before selecting worst endpoints.
            # CDC scopes with different actual max-delay still require explicit review.
            set ceiling [expr {0.2*max($period,$to_period)}]
            set paths [get_timing_paths -delay_type max -from [get_clocks $from] -to [get_clocks $to] -slack_lesser_than $ceiling -nworst 1 -max_paths 200000]
            if {[llength $paths]>=200000} {set capped 1}
            set local_fail 0
            foreach p $paths {
                set req [get_property REQUIREMENT $p];set slack [get_property SLACK $p]
                set target [expr {0.2*$req}]
                puts $f "$from\t$to\t$req\t$slack\t$target\t[get_property STARTPOINT_PIN $p]\t[get_property ENDPOINT_PIN $p]"
                if {$from eq $to && abs($req-$period)>0.001} {set mixed 1}
                if {$from ne $to} {incr cross_count}
                if {$req<=0} {set mixed 1}
                if {$slack<$target} {incr local_fail;incr setup_fail}
            }
            set holds [get_timing_paths -delay_type min -from [get_clocks $from] -to [get_clocks $to] -slack_lesser_than 0 -nworst 1 -max_paths 200000]
            if {[llength $holds]>=200000} {set capped 1}
            incr hold_fail [llength $holds]
            puts $summary "$from->$to below_margin=$local_fail hold_failures=[llength $holds]"
        }
    }
    close $f
    puts $summary "setup_failures=$setup_fail\nhold_failures=$hold_fail\nquery_capped=$capped\nmixed_requirements=$mixed\ncross_clock_candidates=$cross_count"
    # Do not issue overall PASS from endpoint samples: mixed exception scopes,
    # pulse-width and unconstrained integration ports require report review.
    set gate [expr {$setup_fail>0 || $hold_fail>0 ? "FAIL" : "REVIEW_CDC_PULSE_WIDTH_AND_UNCONSTRAINED"}]
    if {$capped || $mixed} {append gate "_SCOPE_OR_QUERY_REVIEW"}
    puts $summary "gate=$gate\nrule=0.20*actual_requirement; hold unchanged\nCDC exceptions were not changed. Review exception coverage and unconstrained paths before acceptance."
    close $summary
    puts "MARGIN20 $gate: $out/nominal_summary.rpt"
}
