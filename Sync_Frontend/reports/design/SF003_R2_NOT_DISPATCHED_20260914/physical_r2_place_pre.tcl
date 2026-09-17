set sync_r2_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $sync_r2_root tools physical_run_pre.tcl]
if {[llength [get_cells -quiet -hier -filter {REF_NAME =~ BUFG* || REF_NAME =~ MMCME* || REF_NAME =~ PLLE*}]]} {error "SF003_R2_UNEXPECTED_OPT_CLOCK_RESOURCES"}
puts "SF003_R2_PREPLACE_CLOCK_RESOURCES=0"
