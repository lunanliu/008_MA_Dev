if {$argc != 2 || [lsearch -exact {roundtrip} [lindex $argv 0]] < 0} {error "Expected roundtrip and project path"}
set mode [lindex $argv 0]
open_project [file normalize [lindex $argv 1]]
set_param general.maxThreads 8
set_property -dict [list xsim.elaborate.mt_level {16} xsim.elaborate.xelab.more_options {} xsim.simulate.runtime {0ns}] [get_filesets sim_$mode]
launch_simulation -simset sim_$mode -mode behavioral
run all
close_sim
close_project
puts "DDR_CONTROL_SIMULATION_FINISHED_CHECK_LOG_FOR_PASS_$mode"
