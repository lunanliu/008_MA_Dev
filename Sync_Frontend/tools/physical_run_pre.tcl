set sync_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $sync_root tools run_threads.tcl]
# Vendor XPM resolves the literal ROM filename in the actual run working directory.
file copy -force [file join $sync_root ip rom fine_ps1_reference_16lane.mem] [file join [pwd] fine_ps1_reference_16lane.mem]
puts "SYNC_ROM_STAGED cwd=[pwd] bytes=[file size [file join [pwd] fine_ps1_reference_16lane.mem]]"
