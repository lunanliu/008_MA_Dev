set sync_r2_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $sync_r2_root tools physical_run_pre.tcl]
set r2_inputs [get_ports {session_start session_abort stream_gap s_valid m_ready s_data[*]}]
set r2_outputs [all_outputs]
set r2_all_sync [get_ports -filter {DIRECTION == IN && NAME != clk && NAME != reset_n}]
if {[llength $r2_inputs]!=133 || [lsort $r2_inputs] ne [lsort $r2_all_sync] || [llength $r2_outputs]!=682} {error "SF003_R2_IO_PORT_COVERAGE_FAIL"}
if {[llength [get_clocks]]!=1 || abs([get_property PERIOD [get_clocks]]-8.0)>0.001} {error "SF003_R2_CLOCK_FAIL"}
if {[llength [get_cells -quiet -hier -filter {REF_NAME =~ BUFG* || REF_NAME =~ MMCME* || REF_NAME =~ PLLE*}]]} {error "SF003_R2_UNEXPECTED_SYNTH_CLOCK_RESOURCES"}
# Execute the same IO constraints directly as well, so any command error is fatal here.
source [file join $sync_r2_root constraints standalone_io_budget_r2.xdc]
write_xdc -force [file join [pwd] sf003_r2_applied_constraints.xdc]
puts "SF003_R2_IO_COVERAGE inputs=133 outputs=682 max_ns=1.000 min_ns=0.000"
