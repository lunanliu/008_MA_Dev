# Source with XSim open. Only selected controls/data; never recursive log-all.
set cfg [current_wave_config]
if {$cfg eq ""} {create_wave_config}
foreach p {
 /sync_sfo_full_frame_tb/clk125 /sync_sfo_full_frame_tb/clk150 /sync_sfo_full_frame_tb/clk500
 /sync_sfo_full_frame_tb/reset_request /sync_sfo_full_frame_tb/s_valid /sync_sfo_full_frame_tb/s_ready
 /sync_sfo_full_frame_tb/s_data /sync_sfo_full_frame_tb/ni /sync_sfo_full_frame_tb/n1 /sync_sfo_full_frame_tb/n2
 /sync_sfo_full_frame_tb/nreq /sync_sfo_full_frame_tb/npoint /sync_sfo_full_frame_tb/nt06 /sync_sfo_full_frame_tb/nt09
 /sync_sfo_full_frame_tb/mv /sync_sfo_full_frame_tb/mr /sync_sfo_full_frame_tb/no /sync_sfo_full_frame_tb/fault
 /sync_sfo_full_frame_tb/e125 /sync_sfo_full_frame_tb/e150 /sync_sfo_full_frame_tb/diag
} {
    set objects [get_objects -quiet $p]
    if {[llength $objects]} {add_wave $objects;log_wave $objects}
}
