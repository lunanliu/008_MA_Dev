# Bounded native project/IP migration review. No output generation or design runs.
set script_root [file normalize [file join [file dirname [info script]] ../../..]]
if {$argc!=1} {error "Expected one fresh result directory"}
set resultdir [file normalize [lindex $argv 0]]
if {![string match "${script_root}/work/*" $resultdir]} {error "Result directory must belong to this workspace work/"}
file mkdir $resultdir
proc csvrow {channel values} {
    set out {};foreach value $values {lappend out "\"[string map [list \" \"\"] $value]\""};puts $channel [join $out ,];flush $channel
}
proc xci_value {path key} {
    set h [open $path r];set text [read $h];close $h
    set pattern [format {<spirit:configurableElementValue spirit:referenceId="%s">([^<]*)</spirit:configurableElementValue>} $key]
    if {![regexp $pattern $text all value]} {error "Missing XCI field $key in $path"}
    return $value
}
proc config_snapshot {stage} {
    global expected_user_config resultdir
    set h [open [file join $resultdir config_${stage}.csv] w];csvrow $h {IP Parameter Value Expected SourceMatches}
    set snapshot [dict create];set mismatches 0
    foreach n [lsort [dict keys $expected_user_config]] {
        set ip [get_ips $n];if {[llength $ip]!=1} {error "IP not unique: $n"}
        set props [list_property $ip]
        foreach key [lsort [dict keys [dict get $expected_user_config $n]]] {
            set prop CONFIG.$key
            if {[lsearch -exact $props $prop]<0} {error "Missing native CONFIG property $n/$key"}
            set value [get_property $prop $ip];set want [dict get $expected_user_config $n $key]
            dict set snapshot $n $key $value
            set equal [expr {$value eq $want}];if {!$equal} {incr mismatches}
            csvrow $h [list $n $key $value $want $equal]
        }
    };close $h
    # Export differences for review instead of silently changing expected values.
    puts "CONFIG_SOURCE_DIFFERENCES_${stage}=$mismatches"
    return $snapshot
}
proc project_identity {stage} {
    global root target resultdir expected_ipdef
    if {[get_property PART [current_project]] ne $target} {error "Project target differs"}
    if {[get_property top [get_filesets sources_1]] ne "t10_two_pass_system"} {error "Hardware top differs"}
    if {[get_property top [get_filesets sim_1]] ne "t10_full023_tb"} {error "Simulation top differs"}
    set declared [read_list [file join $root rtl sources.f]];set count 0
    set h [open [file join $resultdir files_${stage}.csv] w];csvrow $h {Fileset Path Exists}
    foreach fs {sources_1 sim_1 constrs_1} {
        foreach f [get_files -of_objects [get_filesets $fs]] {
            set path [file normalize $f]
            csvrow $h [list $fs $path [file exists $path]]
            if {![string match "${root}/*" $path]} {error "External source dependency: $path"}
            if {![file exists $path]} {error "Missing project input: $path"}
        }
    };close $h
    foreach rel $declared {set f [get_files [file normalize [file join $root $rel]]];if {[llength $f]!=1} {error "Declared core missing/ambiguous: $rel"};incr count}
    if {$count!=74 || [llength [get_ips]]!=34} {error "Wrong source or IP count"}
    set actualxci {};foreach f [get_files -all] {if {[string equal -nocase [file extension $f] .xci]} {lappend actualxci [file normalize $f]}}
    set actualxci [lsort -unique $actualxci];set wantedxci {}
    set h [open [file join $resultdir ip_${stage}.csv] w];csvrow $h {IP IPDEF Path Device Package Speed Temperature Locked}
    foreach n [lsort [dict keys $expected_ipdef]] {
        set path [file normalize [file join $root ip config $n ${n}.xci]];lappend wantedxci $path
        set ip [get_ips $n];set def [get_property IPDEF $ip]
        if {$def ne [dict get $expected_ipdef $n]} {error "IPDEF version changed: $n/$def"}
        set device [xci_value $path PROJECT_PARAM.DEVICE];set package [xci_value $path PROJECT_PARAM.PACKAGE]
        set speed [xci_value $path PROJECT_PARAM.SPEEDGRADE];set temp [xci_value $path PROJECT_PARAM.TEMPERATURE_GRADE];set locked [get_property IS_LOCKED $ip]
        csvrow $h [list $n $def $path $device $package $speed $temp $locked]
        if {$device ne "xcvu11p" || $package ne "flgb2104" || $speed ne "-2" || ![string equal -nocase $temp E] || $locked} {error "IP target/lock differs: $n"}
    };close $h
    if {$actualxci ne [lsort $wantedxci]} {error "Project XCI sources are not exactly canonical ip/config"}
    set h [open [file join $resultdir runs_${stage}.csv] w];csvrow $h {Run Status Progress}
    foreach run [get_runs] {csvrow $h [list $run [get_property STATUS $run] [get_property PROGRESS $run]];if {[get_property PROGRESS $run] ne "0%"} {error "Unexpected executed design run"}}
    close $h
}
set rc [catch {
    source [file join $script_root ip expected_user_config.tcl]
    source [file join $script_root tools vivado create_project.tcl]
    report_ip_status -file [file join $resultdir ip_before.rpt]
    set before [config_snapshot before]
    foreach n [lsort [dict keys $expected_ipdef]] {
        set path [file join $root ip config $n ${n}.xci]
        if {[xci_value $path PROJECT_PARAM.PACKAGE] ne "flgb2104" || [get_property IS_LOCKED [get_ips $n]]} {
            puts "NATIVE_RETARGET_BEGIN $n";flush stdout
            upgrade_ip -vlnv [dict get $expected_ipdef $n] -log [file join $resultdir native_retarget.log] [get_ips $n]
            puts "NATIVE_RETARGET_END $n";flush stdout
        }
    }
    set after [config_snapshot after]
    if {$before ne $after} {error "Native CONFIG changed during migration; review CSVs without changing baseline"}
    update_compile_order -fileset sim_1
    project_identity after
    report_ip_status -file [file join $resultdir ip_after.rpt]
    close_project
    open_project [file join $script_root vivado T10_SFO T10_SFO.xpr]
    project_identity reopened
    set reopened [config_snapshot reopened]
    if {$after ne $reopened} {error "CONFIG changed on reopen"}
    close_project
    set h [open [file join $resultdir native_complete.json] w]
    puts $h {"status":"PENDING_ASTRA_REVIEW","part":"xcvu11p-flgb2104-2-e","hardware_top":"t10_two_pass_system","simulation_top":"t10_full023_tb","core_sources":74,"ips":34,"canonical_ip_sources":true,"reopened_in_vivado":true,"gui_interaction_test":false,"ip_output_generation":false,"simulation":false,"synthesis":false,"implementation":false}}
    close $h
} message options]
if {$rc} {
    set h [open [file join $resultdir native_error.txt] w];puts $h $message
    if {[dict exists $options -errorinfo]} {puts $h [dict get $options -errorinfo]};close $h
    catch {close_project};puts stderr $message;exit 1
}
puts "T10_MIGRATE_GUI001_NATIVE_COMPLETE";exit 0
