set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root vivado Sync_Frontend Sync_Frontend.xpr]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Wrong part"}
if {[get_property TOP [get_filesets sim_1]] ne "coarse_baseline_equivalence_tb"} {error "Wrong testbench"}
source [file join $root tools run_threads.tcl]
set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]
# No reuse of historical FLGC DCP. Generate official managed-IP products for this project.
generate_target all [get_ips]
report_ip_status -file [file join $root reports SF001_ip_status_after.txt]
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
puts "SF001_SIMULATION_RETURNED_CHECK_NATIVE_PASS_MARKER"
