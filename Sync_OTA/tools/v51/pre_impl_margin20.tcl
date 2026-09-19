set ota_here [file dirname [file normalize [info script]]]
source [file join $ota_here ../vivado/run_threads.tcl]
source [file join $ota_here timing_margin20_common.tcl]
ota_margin20::apply
