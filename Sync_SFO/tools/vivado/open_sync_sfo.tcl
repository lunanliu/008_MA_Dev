# Navigation only: no synthesis, implementation, simulation or IP generation.
set module_root [file normalize [file join [file dirname [info script]] ../..]]
if {[llength [get_projects -quiet]]} {error "Use an empty Vivado session; preserve any open GUI project."}
open_project [file join $module_root Sync_SFO.xpr]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Part mismatch"}
if {[get_property TOP [get_filesets sources_1]] ne "sync_sfo_top"} {error "Core top mismatch"}
puts "Opened Sync_SFO. No run started."
