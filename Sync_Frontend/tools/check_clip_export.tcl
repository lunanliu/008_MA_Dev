# Re-read the complete EDIF independently; compile only the pure VHDL wiring wrapper.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 2} {error "args: successful physical attempt, fresh export-check directory"}
set physical [file normalize [lindex $argv 0]]
set check [file normalize [lindex $argv 1]]
if {[file exists $check]} {error "Fresh export check directory required"}
file mkdir $check
set package [file join $check package]
file mkdir $package
foreach name {sync_frontend_clip.vhd sync_frontend_clip.xml sync_frontend_clip.xdc ports.json} {file copy [file join $root clip $name] [file join $package $name]}
file copy [file join $physical sync_frontend_top.edf] [file join $package sync_frontend_top.edf]
create_project export_core_check [file join $check core_project] -part xcvu11p-flgb2104-2-e
source [file join $root tools run_threads.tcl]
read_edif [file join $package sync_frontend_top.edf]
link_design -top sync_frontend_top -part xcvu11p-flgb2104-2-e
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "Export contains black boxes"}
report_utilization -file [file join $check core_utilization.txt]
set f [open [file join $check core_ports.txt] w]
foreach p [lsort [get_ports]] {puts $f "[get_property NAME $p] [get_property DIRECTION $p]"}
close $f
read_xdc [file join $root constraints clk125.xdc]
report_clocks -file [file join $check core_clocks.txt]
write_checkpoint -force [file join $check core_relinked.dcp]
close_project
create_project export_wrapper_check [file join $check wrapper_project] -part xcvu11p-flgb2104-2-e
source [file join $root tools run_threads.tcl]
read_edif [file join $package sync_frontend_top.edf]
read_vhdl [file join $package sync_frontend_clip.vhd]
synth_design -mode out_of_context -top sync_frontend_clip -part xcvu11p-flgb2104-2-e
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "VHDL/EDIF wrapper has black boxes"}
create_clock -name ni_clk125_check -period 8.0 [get_ports clk125]
set f [open [file join $package sync_frontend_clip.xdc] r]; set scoped [read $f]; close $f
# Emulate NI's documented hierarchy placeholder using the independent wrapper root.
set scoped [string map [list {%ClipInstancePath%/} {}] $scoped]
set f [open [file join $check scoped_clock_check.xdc] w]; puts $f $scoped; close $f
read_xdc [file join $check scoped_clock_check.xdc]
report_utilization -file [file join $check wrapper_utilization.txt]
report_clocks -file [file join $check wrapper_clocks.txt]
set f [open [file join $check wrapper_ports.txt] w]
foreach p [lsort [get_ports]] {puts $f "[get_property NAME $p] [get_property DIRECTION $p]"}
close $f
set generators [get_cells -quiet -hier -filter {REF_NAME =~ MMCME* || REF_NAME =~ PLLE* || REF_NAME =~ BUFG*}]
if {[llength $generators]} {error "Clock-resource declaration mismatch; inspect wrapper/core"}
write_checkpoint -force [file join $check wrapper_linked.dcp]
close_project
set f [open [file join $check export_check_complete.txt] w]
puts $f "SF003_EDIF_ROUNDTRIP_PASS CORE_AND_VHDL_BLACKBOX=0 PART=xcvu11p-flgb2104-2-e CLOCK_RESOURCES=0"
close $f
puts "SF003_EDIF_ROUNDTRIP_PASS"
