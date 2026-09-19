# Optional procedure for ONE approved new implementation, after placement.
# Sourcing this file defines the procedure; it does not run EDA or change XPR.
# No timing exceptions, clock changes, Pblocks or data latency changes.
proc ota_optimize_fft_controls {report_dir} {
    if {[llength [current_design -quiet]] != 1} {error "Open the new placed Sync_OTA design first"}
    set part [get_property PART [current_design]]
    if {$part ne "xcvu11p-flgb2104-2-e"} {error "Unexpected part: $part"}
    file mkdir $report_dir
    set candidates [get_cells -quiet -hier -regexp {sfo/(initial_estimator/owner/fft|residual_estimator/front_stage/main/service|residual_estimator/aux_service)/u_xfft/.*/(reset_pipe_reg\[[0-9]+\]|sclr_int_reg|run_time_sel_reg\[[0-9]+\]|nfft_we_int_reg|nfft_expandedm1_reg\[[0-9]+\]|NFFT_int_tmp_reg\[[0-9]+\]|max_n_int_minus_one_ff[^/]*)}]
    set selected {}
    set f [open [file join $report_dir selected_controls.txt] w]
    foreach c $candidates {
        if {[regexp {/(reset_sync500|[^/]*syncstages[^/]*)/} $c]} {continue}
        set ref [get_property REF_NAME $c]
        # Never clone a CDC synchronizer or override an IP preservation property.
        if {$ref ni {FDRE FDSE FDCE FDPE}} {continue}
        if {[string toupper [get_property ASYNC_REG $c]] in {TRUE 1}} {continue}
        if {[string toupper [get_property DONT_TOUCH $c]] in {TRUE 1}} {continue}
        foreach n [get_nets -quiet -of_objects [get_pins -quiet -of_objects $c -filter {DIRECTION == OUT}]] {
            if {[string toupper [get_property DONT_TOUCH $n]] in {TRUE 1}} {continue}
            lappend selected $n
            puts $f "$c -> $n"
        }
    }
    close $f
    set selected [lsort -unique $selected]
    if {[llength $selected] == 0} {puts "No eligible reviewed FFT controls; standard physical optimization remains enabled"; return}
    report_timing_summary -max_paths 20 -file [file join $report_dir timing_before.rpt]
    # This option is explicitly supported/recommended in this host's 2021.1
    # original implementation log (Physopt 32-572). No automatic launch here.
    phys_opt_design -force_replication_on_nets $selected
    report_timing_summary -max_paths 20 -file [file join $report_dir timing_after.rpt]
    report_utilization -hierarchical -hierarchical_depth 8 -file [file join $report_dir utilization_after.rpt]
    puts "Physical optimization completed; route and full setup/hold/CDC reports are still required."
}
