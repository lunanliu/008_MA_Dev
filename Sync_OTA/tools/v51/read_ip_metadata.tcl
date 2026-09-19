# Read-only IP GUI metadata query. No HDL compilation, simulation, generation,
# synthesis, implementation or launch_runs command is present.
set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir
set f [open [file join $output_dir metadata.txt] w]
puts $f "VERSION=[version -short]"
set_param general.maxThreads 8
open_project -read_only {D:/008_MA_Dev/Sync_OTA/Sync_OTA.xpr}
foreach name {t03_xfft_2048_main t03_xfft_16384_aux t07_g3_up47 t07_g3_up15 t07_g3_down15 t07_g3_down47} {
 set ip [get_ips $name]
 puts $f "IP=$name"
 foreach prop [lsort [list_property $ip]] {
  if {[regexp -nocase {latency|^CONFIG\.|^MODELPARAM} $prop]} {
   if {![catch {get_property $prop $ip} value]} {puts $f "$prop=$value"}
  }
 }
}
set timing_file {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx/xfft_v9_1/xgui/xfft_v9_1_utils_timing.tcl}
set helpers_file {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx/xfft_v9_1/xgui/xfft_v9_1_helpers.tcl}
foreach path [list $helpers_file $timing_file] {
 puts $f "READ_VENDOR_CALLBACK=$path"
 puts $f "SOURCE_STATUS=[catch {source $path} result] $result"
}
proc list_timing_procs {n f} {
 foreach p [info procs ${n}::*] {
  if {[regexp -nocase {fft|latency|timing|fir_compiler} $p]} {
   puts $f "PROC=$p ARGS=[info args $p]"
  }
 }
 foreach child [namespace children $n] {list_timing_procs $child $f}
}
list_timing_procs :: $f
close $f
close_project
puts STATIC_METADATA_QUERY_COMPLETE
exit
