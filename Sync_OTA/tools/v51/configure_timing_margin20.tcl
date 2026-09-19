# Source in the open Sync_OTA GUI project. Configures the next run; launches nothing.
set ota_tools [file dirname [file normalize [info script]]]
set ota_root [file normalize [file join $ota_tools ../..]]
if {[llength [current_project -quiet]]!=1} {error "Open the Sync_OTA project first"}
if {![string equal -nocase [file normalize [get_property DIRECTORY [current_project]]] $ota_root] ||
    [get_property NAME [current_project]] ne "Sync_OTA"} {error "This configuration belongs only to $ota_root/Sync_OTA.xpr"}
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Unexpected part"}
set ota_run [get_runs -quiet impl_1]
if {[llength $ota_run]!=1} {error "Missing/ambiguous impl_1"}
set ota_thread_hook [file normalize [file join $ota_tools ../vivado/run_threads.tcl]]
set ota_final_hook [file normalize [file join $ota_tools post_route_margin20.tcl]]
set ota_postroute [get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED $ota_run]
if {$ota_postroute} {set ota_final_key STEPS.POST_ROUTE_PHYS_OPT_DESIGN.TCL.POST} else {set ota_final_key STEPS.ROUTE_DESIGN.TCL.POST}
set ota_changes [dict create \
    STEPS.OPT_DESIGN.TCL.PRE [file normalize [file join $ota_tools pre_impl_margin20.tcl]] \
    STEPS.PHYS_OPT_DESIGN.TCL.PRE [file normalize [file join $ota_tools pre_physopt_margin20.tcl]] \
    STEPS.ROUTE_DESIGN.TCL.POST "" \
    STEPS.POST_ROUTE_PHYS_OPT_DESIGN.TCL.POST ""]
dict set ota_changes $ota_final_key $ota_final_hook
# Preflight ALL old properties before the first mutation; same basename is not ownership.
set ota_previous [dict create]
dict for {key value} $ota_changes {
    set old [get_property $key $ota_run];dict set ota_previous $key $old
    if {$old ne ""} {
        set old_norm [file normalize $old]
        set allowed [list $ota_final_hook]
        if {[string match *.PRE $key]} {set allowed [list $ota_thread_hook $value]}
        set owned 0
        foreach a $allowed {if {[string equal -nocase $old_norm $a]} {set owned 1}}
        if {!$owned} {error "Preserve/merge existing hook first: $key=$old"}
    }
    if {$value ne "" && ![file exists $value]} {error "Missing hook $value"}
}
if {[catch {
    dict for {key value} $ota_changes {
        if {$value eq ""} {reset_property $key $ota_run} else {set_property $key $value $ota_run}
    }
} ota_error ota_options]} {
    dict for {key value} $ota_previous {
        if {$value eq ""} {catch {reset_property $key $ota_run}} else {catch {set_property $key $value $ota_run}}
    }
    return -options $ota_options $ota_error
}
puts "MARGIN20 configured for next manual implementation, final stage=$ota_final_key; no run launched."
