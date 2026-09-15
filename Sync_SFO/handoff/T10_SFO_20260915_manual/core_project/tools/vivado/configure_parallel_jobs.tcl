# User policy, 2026-09-14: use the highest supported, locally sustainable parallelism.
# Source in the intended open project before the NEXT launch; no run starts here.
# No installation/global preference changes; run PRE hooks configure child processes.
if {[llength [get_projects -quiet]] != 1} {
    error "Open the intended T10 project before applying its parallel-job policy."
}
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {
    error "Expected the T10 FLGB project."
}
namespace eval ::t10_performance {}
if {![info exists ::t10_performance::elab_jobs]} {set ::t10_performance::elab_jobs 16}
proc t10_set_elaboration_jobs {jobs} {
    if {![string is integer -strict $jobs] || $jobs < 1 || $jobs > 16} {
        error "Admitted elaboration jobs must be an integer from 1 to 16."
    }
    set_property xsim.elaborate.mt_level $jobs [get_filesets sim_1]
    if {[get_property xsim.elaborate.mt_level [get_filesets sim_1]] != $jobs} {
        error "Elaboration jobs readback mismatch"
    }
    set ::t10_performance::elab_jobs $jobs
    puts "T10_XELAB_JOBS actual=$jobs ceiling=16"
}
t10_set_elaboration_jobs $::t10_performance::elab_jobs
set ::t10_performance::hook [file normalize [file join [file dirname [info script]] run_threads.tcl]]
source $::t10_performance::hook

proc t10_install_thread_hooks {} {
    set hook $::t10_performance::hook
    set assignments {}
    foreach run [get_runs -quiet] {
        foreach property [list_property $run] {
            if {![regexp {^STEPS\..+\.TCL\.PRE$} $property]} {continue}
            set previous [get_property $property $run]
            if {$previous ne "" && [file normalize $previous] ne $hook} {
                # A matching basename is not proof of ownership. Only relocate
                # an existing byte-identical hook; otherwise preserve and stop.
                set same_content 0
                if {[file isfile $previous]} {
                    set old_handle [open $previous rb]
                    set old_content [read $old_handle]
                    close $old_handle
                    set new_handle [open $hook rb]
                    set new_content [read $new_handle]
                    close $new_handle
                    set same_content [expr {$old_content eq $new_content}]
                }
                if {!$same_content} {
                    error "Existing user hook preserved: $run $property = $previous. Review chaining before launch."
                }
            }
            lappend assignments [list $run $property]
        }
    }
    # Preflight all slots before writing any; never overwrite an unrelated user hook.
    foreach assignment $assignments {
        lassign $assignment run property
        set_property $property $hook $run
        if {[file normalize [get_property $property $run]] ne $hook} {
            error "Run hook readback mismatch: $run $property"
        }
    }
    puts "T10_RUN_HOOKS installed=[llength $assignments] hook=$hook"
}

proc t10_prepare_build {} {
    # Define missing OOC runs only for IPs already configured to produce a checkpoint.
    # Do not turn OOC on, force regeneration, or launch computation here.
    foreach ip [get_ips -quiet] {
        set name [get_property NAME $ip]
        if {[llength [get_runs -quiet ${name}_synth_1]]} {continue}
        set xci [get_files -quiet -all [get_property IP_FILE $ip]]
        if {[llength $xci] != 1} {error "Cannot resolve canonical XCI for $name"}
        if {[get_property GENERATE_SYNTH_CHECKPOINT $xci]} {create_ip_run $ip}
    }
    source $::t10_performance::hook
    t10_install_thread_hooks
}

# Example: t10_launch_runs {synth_1}
# Example: t10_launch_runs {impl_1} -to_step route_design
# Resource-reviewed alternative: t10_launch_runs {synth_1} -jobs 2
# GUI: t10_prepare_build, then select the admitted jobs (ceiling 16) in Launch Runs.
proc t10_launch_runs {run_names args} {
    if {[llength $run_names] == 0} {error "Specify the intended run names."}
    set jobs 16
    foreach argument $args {
        if {$argument in {-j -jo -job} || [string match -jobs=* $argument]} {
            error "Use the full -jobs option followed by its integer value."
        }
    }
    set index [lsearch -exact $args -jobs]
    if {$index >= 0} {
        set jobs [lindex $args [expr {$index + 1}]]
        set args [lreplace $args $index [expr {$index + 1}]]
        if {[lsearch -exact $args -jobs] >= 0} {error "Duplicate -jobs option"}
    }
    if {![string is integer -strict $jobs] || $jobs < 1 || $jobs > 16} {
        error "Admitted jobs must be an integer from 1 to 16."
    }
    t10_prepare_build
    puts "T10 build launch: actual_jobs=$jobs ceiling=16; runs=$run_names; resource decision belongs in run admission."
    launch_runs {*}$run_names -jobs $jobs {*}$args
}
t10_install_thread_hooks
puts "T10 performance policy applied: requested general/synth limits=8; xelab jobs=$::t10_performance::elab_jobs; build jobs ceiling=16. No run started."
