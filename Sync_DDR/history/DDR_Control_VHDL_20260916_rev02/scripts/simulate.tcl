set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 1 || [lsearch -exact {write read} [lindex $argv 0]] < 0} {
  error "Specify exactly one simulation: write or read"
}
set mode [lindex $argv 0]
open_project [file join $root project DDR_Control.xpr]
set_param general.maxThreads 8
set_property xsim.elaborate.xelab.more_options {-mt 16} [get_filesets sim_$mode]
launch_simulation -simset sim_$mode -mode behavioral
run all
close_sim
close_project
puts "DDR_CONTROL_SIMULATION_FINISHED_CHECK_LOG_FOR_PASS_${mode}"