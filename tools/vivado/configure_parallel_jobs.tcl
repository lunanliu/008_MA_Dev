# User policy, 2026-09-14: 16 build jobs and 16 xelab sub-compilation jobs.
# Source in the intended open project before the NEXT launch; no run starts here.
# This does not edit global Vivado preferences or the separate maxThreads limit.
if {[llength [get_projects -quiet]] != 1} {
    error "Open the intended T10 project before applying its parallel-job policy."
}
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {
    error "Expected the T10 FLGB project."
}
set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]

# Example: t10_launch_runs {synth_1}
# Example: t10_launch_runs {impl_1} -to_step route_design
# GUI launches: select Number of jobs = 16 in Launch Runs.
proc t10_launch_runs {run_names args} {
    if {[llength $run_names] == 0} {error "Specify the intended run names."}
    if {[lsearch -exact $args -jobs] >= 0} {
        error "The user policy fixes -jobs at 16; do not supply a second value."
    }
    puts "T10 build launch: jobs=16; runs=$run_names"
    launch_runs {*}$run_names -jobs 16 {*}$args
}
puts "T10 policy applied: xelab sub-compilation jobs=16; t10_launch_runs uses -jobs 16. No run started."
