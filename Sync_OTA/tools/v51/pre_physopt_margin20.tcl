set ota_here [file dirname [file normalize [info script]]]
source [file join $ota_here ../vivado/run_threads.tcl]
source [file join $ota_here timing_margin20_common.tcl]
ota_margin20::validate_owned
source [file join $ota_here optimize_fft_controls_after_place.tcl]
set ota_phys_report [file join [pwd] margin20_fft_controls_[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]]
ota_optimize_fft_controls $ota_phys_report
