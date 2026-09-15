# Fresh-entry owned-process cancellation probe; does not claim mid-XSim coverage.
set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root vivado CFO_SYNC CFO_SYNC.xpr]
source [file join $root vivado configure_parallel_jobs.tcl]
puts "CFO_CANCEL_PROBE_READY pid=[pid] project=[get_property DIRECTORY [current_project]]"
flush stdout
after 600000
error "Cancellation probe was not cancelled within its admitted window"