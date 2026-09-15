# Source with XSim open. Only selected controls/data; never recursive log-all.
set cfg [current_wave_config]
if {$cfg eq ""} {create_wave_config}
foreach p {
 /t10_full023_tb/clk125 /t10_full023_tb/clk150 /t10_full023_tb/clk500
 /t10_full023_tb/reset_request /t10_full023_tb/s_valid /t10_full023_tb/s_ready
 /t10_full023_tb/s_data /t10_full023_tb/ni /t10_full023_tb/n1 /t10_full023_tb/n2
 /t10_full023_tb/nreq /t10_full023_tb/npoint /t10_full023_tb/nt06 /t10_full023_tb/nt09
 /t10_full023_tb/mv /t10_full023_tb/mr /t10_full023_tb/no /t10_full023_tb/fault
 /t10_full023_tb/e125 /t10_full023_tb/e150 /t10_full023_tb/diag
} {
    set objects [get_objects -quiet $p]
    if {[llength $objects]} {add_wave $objects;log_wave $objects}
}
