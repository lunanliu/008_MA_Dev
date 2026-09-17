# SF003 closure: reuse completed EDIF dependencies; no core RTL/IP synthesis or implementation.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 2} {error "args: prepared release directory, fresh native-check directory"}
set release [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {[file exists $out]} {error "Fresh output directory required"}
file mkdir $out
set package [file join $release clip_edif]
set dcp_package [file join $out clip_dcp]
file mkdir $dcp_package
source [file join $root tools run_threads.tcl]
proc require_core_shape {label} {
    if {[get_property PART [current_design]] ne "xcvu11p-flgb2104-2-e"} {error "$label part mismatch"}
    if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "$label blackboxes"}
    set io [get_cells -quiet -hier -filter {REF_NAME =~ IBUF* || REF_NAME =~ OBUF* || REF_NAME =~ IOBUF*}]
    if {[llength $io]} {error "$label contains device-pad I/O primitives"}
    foreach {ref expected} {DSP48E2 206 RAMB36E2 58 RAMB18E2 9 FDRE 17272 FDSE 845 FDCE 2} {
        set count [llength [get_cells -quiet -hier -filter "REF_NAME == $ref"]]
        if {$count != $expected} {error "$label resource mismatch $ref=$count expected=$expected"}
    }
    puts "SF003_DCP_SHAPE $label BLACKBOX=0 PAD_IO=0 DSP=206 RAMB36=58 RAMB18=9 FF=18119"
}
# Load exactly the list packaged from the already-verified single export attempt.
set dep [open [file join $package edn_files.txt] r]
set dependencies [split [string trim [read $dep]] "\n"]
close $dep
if {[llength $dependencies]!=43} {error "Expected the same 43 dependencies"}
create_project sf003_dcp_export [file join $out core_project] -part xcvu11p-flgb2104-2-e
foreach name $dependencies {
    set name [string trim $name "\r"]
    if {[file tail $name] ne $name || [file extension $name] ne ".edn"} {error "Invalid dependency"}
    read_edif [file join $package $name]
}
read_edif [file join $package sync_frontend_top.edf]
link_design -mode out_of_context -top sync_frontend_top -part xcvu11p-flgb2104-2-e
require_core_shape CORE
# Export without creating standalone clock or input/output delays. NI owns boundary constraints.
if {[llength [get_clocks -quiet]]} {error "Unexpected standalone clock in netlist-only core; inspect, do not silently strip"}
write_checkpoint -force [file join $dcp_package sync_frontend_top.dcp]
report_utilization -file [file join $out core_ooc_utilization.txt]
write_xdc -force [file join $out core_export_constraints.xdc]
set f [open [file join $out core_ports.txt] w]
foreach p [lsort [get_ports]] {puts $f "[get_property NAME $p] [get_property DIRECTION $p]"}
close $f
close_project
# Re-open the saved DCP in a fresh project, proving it is independently readable.
open_checkpoint [file join $dcp_package sync_frontend_top.dcp]
require_core_shape SAVED_DCP
set f [open [file join $out saved_dcp_resources.txt] w]
foreach ref {DSP48E2 RAMB36E2 RAMB18E2 FDRE FDSE FDCE BUFGCE BUFGCTRL MMCME4_ADV PLLE4_ADV} {
    set ref_count [llength [get_cells -quiet -hier -filter "REF_NAME == $ref"]]
    puts $f "$ref $ref_count"
}
close $f
close_project
# Synthesize only the pure wiring wrapper as a shell, then populate its blackbox with the DCP.
foreach name {sync_frontend_clip.vhd ports.json sync_frontend_clip.xdc} {
    file copy [file join $package $name] [file join $dcp_package $name]
}
file copy [file join $release clip_dcp_template sync_frontend_clip.xml] [file join $dcp_package sync_frontend_clip.xml]
create_project sf003_dcp_wrapper [file join $out wrapper_project] -part xcvu11p-flgb2104-2-e
read_vhdl [file join $dcp_package sync_frontend_clip.vhd]
synth_design -mode out_of_context -flatten_hierarchy none -top sync_frontend_clip -part xcvu11p-flgb2104-2-e
set black [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $black]!=1 || [get_property REF_NAME $black] ne "sync_frontend_top"} {error "Expected one frontend shell blackbox"}
set target [get_property NAME $black]
read_checkpoint -cell $target [file join $dcp_package sync_frontend_top.dcp]
require_core_shape DCP_WRAPPER
create_clock -name ni_clk125_check -period 8.000 [get_ports clk125]
set clock_pin [get_pins -quiet $target/clk]
if {[llength $clock_pin]!=1} {error "No wrapper/core clock pin"}
set inherited [get_clocks -quiet -of_objects $clock_pin]
if {[llength $inherited]!=1 || abs([get_property PERIOD $inherited]-8.0)>0.001} {error "Clock inheritance failed"}
# Ordinary Tcl checks above really execute; the distributable XDC contains no unsupported if.
read_xdc [file join $dcp_package sync_frontend_clip.xdc]
report_clocks -file [file join $out wrapper_clocks.txt]
report_utilization -file [file join $out wrapper_utilization.txt]
set f [open [file join $out wrapper_ports.txt] w]
foreach p [lsort [get_ports]] {puts $f "[get_property NAME $p] [get_property DIRECTION $p]"}
close $f
write_checkpoint -force [file join $out dcp_wrapper_linked.dcp]
set f [open [file join $out dcp_release_check_complete.txt] w]
puts $f "SF003_DCP_RELEASE_CHECK_PASS PART=xcvu11p-flgb2104-2-e BLACKBOX=0 PAD_IO=0"
puts $f "CORE_DCP_REOPEN=PASS DCP_IN_VHDL_WRAPPER=PASS CLOCK_INHERITANCE_TCL=PASS"
puts $f "NATIVE_CORE_RTL_SYNTHESIS=0 IP_SYNTHESIS=0 IMPLEMENTATION=0 NI_PLATFORM_VERIFIED=0"
close $f
close_project
puts "SF003_DCP_RELEASE_CHECK_PASS"