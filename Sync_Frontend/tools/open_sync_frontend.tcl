# Navigation only. Preserve the user's existing GUI session.
set module_root [file normalize [file join [file dirname [info script]] ..]]
if {[llength [get_projects -quiet]]} {error "Use an empty Vivado session; preserve any open GUI project."}
open_project [file join $module_root Sync_Frontend.xpr]
if {[get_property TOP [get_filesets sources_1]] ne "sync_frontend_top"} {error "Core top mismatch"}
puts "Opened Sync_Frontend. No run started."
