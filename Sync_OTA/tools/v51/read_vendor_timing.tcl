# Only evaluates the installed vendor's static GUI timing functions.
# No project open, HDL elaboration/execution, IP generation or EDA run.
set out [file normalize [lindex $argv 0]]
file mkdir $out
set f [open [file join $out timing.txt] w]
puts $f "VERSION=[version -short]"
# Load installed utility implementation; no behavioral substitute.
foreach rel {common_tcl/common.tcl common_tcl/iptypes.tcl common_tcl/vip.tcl xgui/xbip_utils_v3_0.tcl} {
 set full [file join {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx/xbip_utils_v3_0} $rel]
 puts $f "UTILITY_SOURCE=$full STATUS=[catch {source $full} r] RESULT=$r"
}
proc show_utility {n f} {
 foreach p [info procs ${n}::*] {
  if {[string match *supports_dsp48* $p]} {puts $f "UTILITY_PROC=$p ARGS=[info args $p]"}
 }
 foreach child [namespace children $n] {show_utility $child $f}
}
show_utility :: $f
source {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx/xfft_v9_1/xgui/xfft_v9_1_helpers.tcl}
source {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx/xfft_v9_1/xgui/xfft_v9_1_utils_timing.tcl}
source {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx/mult_gen_v12_0/xgui/mult_gen_v12_0_utils.tcl}
source {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx/cmpy_v6_0/xgui/cmpy_v6_0_utils.tcl}
set utility_ns {}
foreach n [namespace children ::] {if {[regexp {xbip_utils|mult_gen|cmpy|xfft} $n]} {lappend utility_ns $n}}
foreach n $utility_ns {set others {};foreach x $utility_ns {if {$x ne $n} {lappend others $x}};namespace eval $n [list namespace path $others]}
puts $f "UTILITY_NS=$utility_ns"
puts $f "IP=t03_xfft_2048_main RUNTIME_NFFT=11"
array unset p
array set p {{c_arch} {3} {c_bfly_type} {0} {c_bram_stages} {4} {c_channels} {1} {c_cmpy_type} {1} {c_data_mem_type} {1} {c_has_aclken} {0} {c_has_aresetn} {1} {c_has_bfp} {0} {c_has_cyclic_prefix} {0} {c_has_natural_input} {1} {c_has_natural_output} {1} {c_has_nfft} {0} {c_has_ovflo} {1} {c_has_rounding} {1} {c_has_scaling} {1} {c_has_xk_index} {0} {c_input_width} {16} {c_m_axis_data_tdata_width} {32} {c_m_axis_data_tuser_width} {8} {c_m_axis_status_tdata_width} {8} {c_nfft_max} {11} {c_optimize_goal} {0} {c_output_width} {16} {c_part} {xcvu11p-flgb2104-2-e} {c_reorder_mem_type} {1} {c_s_axis_config_tdata_width} {16} {c_s_axis_data_tdata_width} {32} {c_throttle_scheme} {0} {c_twiddle_mem_type} {1} {c_twiddle_width} {16} {c_use_flt_pt} {0} {c_use_hybrid_ram} {0} {c_xdevicefamily} {virtexuplus} {nfft} {11}}
foreach leaf {gui_get_transform_latency get_extra_latency_r22 get_output_order_latency_r22 get_unload_delay get_run_latency} {
 set procname ::xfft_v9_1_utils_timing::$leaf
 set vals {}; set missing {}
 foreach arg [info args $procname] {
  if {[info exists p($arg)]} {lappend vals $p($arg)} else {lappend missing $arg}
 }
 if {[llength $missing]} {puts $f "$leaf MISSING=$missing";continue}
 puts $f "$leaf INPUTS=$vals"
 set status [catch {$procname {*}$vals} result]
 puts $f "$leaf STATUS=$status RESULT=$result"
}
puts $f "IP=t03_xfft_16384_aux RUNTIME_NFFT=11"
array unset p
array set p {{c_arch} {3} {c_bfly_type} {0} {c_bram_stages} {7} {c_channels} {1} {c_cmpy_type} {1} {c_data_mem_type} {1} {c_has_aclken} {0} {c_has_aresetn} {1} {c_has_bfp} {0} {c_has_cyclic_prefix} {0} {c_has_natural_input} {1} {c_has_natural_output} {1} {c_has_nfft} {1} {c_has_ovflo} {1} {c_has_rounding} {1} {c_has_scaling} {1} {c_has_xk_index} {0} {c_input_width} {16} {c_m_axis_data_tdata_width} {32} {c_m_axis_data_tuser_width} {8} {c_m_axis_status_tdata_width} {8} {c_nfft_max} {14} {c_optimize_goal} {0} {c_output_width} {16} {c_part} {xcvu11p-flgb2104-2-e} {c_reorder_mem_type} {1} {c_s_axis_config_tdata_width} {24} {c_s_axis_data_tdata_width} {32} {c_throttle_scheme} {0} {c_twiddle_mem_type} {1} {c_twiddle_width} {16} {c_use_flt_pt} {0} {c_use_hybrid_ram} {0} {c_xdevicefamily} {virtexuplus} {nfft} {11}}
foreach leaf {gui_get_transform_latency get_extra_latency_r22 get_output_order_latency_r22 get_unload_delay get_run_latency} {
 set procname ::xfft_v9_1_utils_timing::$leaf
 set vals {}; set missing {}
 foreach arg [info args $procname] {
  if {[info exists p($arg)]} {lappend vals $p($arg)} else {lappend missing $arg}
 }
 if {[llength $missing]} {puts $f "$leaf MISSING=$missing";continue}
 puts $f "$leaf INPUTS=$vals"
 set status [catch {$procname {*}$vals} result]
 puts $f "$leaf STATUS=$status RESULT=$result"
}
proc source_subcore_ipfile {vlnv relpath} {
 set parts [split $vlnv :]
 set name [lindex $parts 2]; set ver [string map {. _} [lindex $parts 3]]
 set full [file join {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx} ${name}_v${ver} $relpath]
 puts $::f "DEPENDENCY_SOURCE=$full"
 if {![file exists $full]} {error "Installed dependency does not exist: $full"}
 uplevel 1 [list source $full]
}
foreach path {fir_compiler_v7_2_global.tcl fir_compiler_v7_2_utils.tcl fir_compiler_v7_2_defn.tcl fir_compiler_v7_2_shared.tcl} {
 set full [file join {C:/NIFPGA/programs/Vivado2021_1/data/ip/xilinx/fir_compiler_v7_2/xgui} $path]
 puts $f "FIR_SOURCE=$path STATUS=[catch {source $full} r] RESULT=$r"
}
proc list_fir {n f} {
 foreach p [info procs ${n}::*] {
  if {[regexp -nocase {fir_compiler|fircompiler} $p] && [regexp -nocase {latency|rate|summary|param|init|calculate|get_.*lat} $p]} {puts $f "FIR_PROC=$p ARGS=[info args $p]"}
 }
 foreach child [namespace children $n] {list_fir $child $f}
}
list_fir :: $f
close $f
puts STATIC_VENDOR_TIMING_COMPLETE
exit
