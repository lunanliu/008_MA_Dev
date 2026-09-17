# SF003 R2: same 1 ns max / 0 ns min independent interface budget.
# Use a Vivado-native collection; original frozen XDC is preserved.
set sync_data_inputs [get_ports {session_start session_abort stream_gap s_valid m_ready s_data[*]}]
set_input_delay -clock clk125 -max 1.000 $sync_data_inputs
set_input_delay -clock clk125 -min 0.000 $sync_data_inputs
set_output_delay -clock clk125 -max 1.000 [all_outputs]
set_output_delay -clock clk125 -min 0.000 [all_outputs]
# Async reset_n has no synchronous IO delay. No false paths.
# OOC ports have no NI physical boundary routing; this is not platform IO timing.
