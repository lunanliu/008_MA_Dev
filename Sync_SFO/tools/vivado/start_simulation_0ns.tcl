# Explicit user/native-operator step after IP target/config review. Compiles/elaborates; runtime stays 0 ns.
# Does not continue an old simulation, and refuses existing output to prevent false completion reuse.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Expected FLGB target"}
set simdir [file join $root vivado T10_SFO T10_SFO.sim sim_1 behav xsim]
foreach n {result.txt data.csv events.csv points.csv xpm_trace.csv} {
    if {[file exists [file join $simdir $n]]} {error "Preserve prior simulation outputs before starting a fresh attempt: $n"}
}
foreach ip [get_ips] {
    if {[get_property IS_LOCKED $ip]} {error "IP still locked: $ip; complete native retarget/config review first"}
}
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
source [file join $root tools vivado configure_parallel_jobs.tcl]
launch_simulation -simset sim_1 -mode behavioral -step compile
launch_simulation -simset sim_1 -mode behavioral -step elaborate
file mkdir $simdir
foreach n {raw.mem r1.mem r2.mem delay.mem delta.mem t09_pilot_phase.mem} {
    file copy -force [file join $root sim data $n] [file join $simdir $n]
}
set h [open [file join $simdir compile_order.txt] w]
foreach f [get_files -compile_order sources -used_in simulation] {
    if {[regexp -nocase {(sim_netlist|post_synth|post_route|_stub\.(v|vhd)|\.dcp$|\.sdf$)} $f]} {close $h;error "Non-behavioral source in compile order: $f"}
    puts $h [file normalize $f]
}
close $h
launch_simulation -simset sim_1 -mode behavioral -step simulate
source [file join $root tools vivado setup_waves.tcl]
puts "Simulation opened at 0 ns. Advance manually; preserve xsim.log and CSV evidence. No runtime Python/MATLAB."
