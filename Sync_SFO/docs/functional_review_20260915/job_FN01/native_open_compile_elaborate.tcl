# FN01: native project-manager open + behavioral compile/elaborate only.
# No simulate/run/synthesis/implementation command is present.
set jobdir [file normalize [file dirname [info script]]]
set canonical D:/008_MA_Dev/Sync_SFO
set private [file join $canonical work FN01 project]
set out [file join $canonical reports functional_review FN01]
if {[version -short] ne "2021.1"} {error "Vivado 2021.1 required"}
set_param general.maxThreads 8
set_param synth.maxThreads 8
set status [open [file join $out stage_status.tsv] a]
proc stage {text} {
    global status
    puts $status "[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]\t$text"
    flush $status
    puts "SFO_FN01_STAGE $text"
}
proc validate_export {root label} {
    global out jobdir
    if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Part mismatch"}
    if {[get_property TOP [get_filesets sources_1]] ne "sync_sfo_top"} {error "Core top mismatch"}
    if {[get_property TOP [get_filesets sim_1]] ne "sync_sfo_full_frame_tb"} {error "TB top mismatch"}
    if {[llength [get_ips -quiet]] != 34} {error "IP count mismatch"}
    set rows {}; set details [open [file join $out ${label}_actual_files.tsv] w]
    puts $details "fileset\tpath\tfile_type\tlibrary"
    foreach fs [get_filesets] {
        foreach f [get_files -quiet -of_objects $fs] {
            set path [file normalize [get_property NAME $f]]
            if {![file isfile $path]} {error "Missing actual source $path"}
            set prefix "[file normalize $root]/"
            if {![string equal -nocase $prefix [string range $path 0 [expr {[string length $prefix]-1}]]]} {error "External source $path"}
            set rel [string range $path [string length $prefix] end]
            lappend rows "[get_property NAME $fs]\t[string tolower $rel]\t[get_property FILE_TYPE $f]\t[get_property LIBRARY $f]"
            puts $details "[get_property NAME $fs]\t$path\t[get_property FILE_TYPE $f]\t[get_property LIBRARY $f]"
        }
    }
    close $details
    set h [open [file join $jobdir expected_native_entries.tsv] r]; set wanted [split [string trim [read $h]] "\n"]; close $h
    if {[lsort $rows] ne [lsort $wanted]} {
        set h [open [file join $out ${label}_membership_mismatch.txt] w]
        puts $h "ACTUAL\n[join [lsort $rows] \n]\nEXPECTED\n[join [lsort $wanted] \n]"; close $h
        error "Exact source membership mismatch; do not relax the list"
    }
    set ips [open [file join $out ${label}_ip_status.tsv] w]
    puts $ips "name\tipdef\tlocked\tip_file"
    foreach ip [get_ips -quiet] {puts $ips "[get_property NAME $ip]\t[get_property IPDEF $ip]\t[get_property IS_LOCKED $ip]\t[get_property IP_FILE $ip]"}
    close $ips
    stage "$label OPEN_AND_MEMBERSHIP_PASS members=[llength $rows] ips=34"
}
if {[catch {
    stage "CANONICAL_OPEN_BEGIN"
    open_project -read_only [file join $canonical Sync_SFO.xpr]
    validate_export $canonical canonical
    close_project
    stage "PRIVATE_OPEN_BEGIN"
    open_project [file join $private Sync_SFO.xpr]
    validate_export $private private
    source [file join $private tools vivado configure_parallel_jobs.tcl]
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]
    foreach ip [get_ips -quiet] {if {[get_property IS_LOCKED $ip]} {error "Locked IP: $ip"}}
    update_compile_order -fileset sim_1
    set h [open [file join $out compile_order_before.txt] w]
    foreach f [get_files -compile_order sources -used_in simulation] {puts $h [file normalize $f]}; close $h
    stage "COMPILE_BEGIN general=[get_param general.maxThreads] synth=[get_param synth.maxThreads] xelab=[get_property xsim.elaborate.mt_level [get_filesets sim_1]]"
    launch_simulation -simset sim_1 -mode behavioral -step compile
    stage "COMPILE_COMMAND_COMPLETED"
    launch_simulation -simset sim_1 -mode behavioral -step elaborate
    stage "ELABORATE_COMMAND_COMPLETED"
    set h [open [file join $out compile_order_after.txt] w]
    foreach f [get_files -compile_order sources -used_in simulation] {puts $h [file normalize $f]}; close $h
    close_project
    stage "SFO_FN01_NATIVE_STAGES_COMPLETED_NO_SIMULATION"
} message options]} {
    stage "FAILED $message"
    set h [open [file join $out native_error.txt] w]; puts $h $message; puts $h [dict get $options -errorinfo]; close $h
    close $status
    exit 1
}
close $status
exit 0
