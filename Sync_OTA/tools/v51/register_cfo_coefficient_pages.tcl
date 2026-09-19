# Run once in an ALREADY OPEN V5.1 Sync_OTA GUI after applying the ROM edit.
# Adds the two data dependencies only. Does not reset or launch any run.
set ota_rom_root [file normalize [file join [file dirname [info script]] ../..]]
set ota_rom_project [current_project -quiet]
if {$ota_rom_project eq ""} {error "Open Sync_OTA.xpr first"}
if {![string equal -nocase [file normalize [get_property DIRECTORY $ota_rom_project]] $ota_rom_root]} {
    error "Current project is not the modified Sync_OTA directory"
}
foreach ota_rom_name {front2048_coefficient_page0.mem front2048_coefficient_page1.mem} {
    set ota_rom_path [file join $ota_rom_root ip cfo $ota_rom_name]
    if {![file exists $ota_rom_path]} {error "Missing coefficient page: $ota_rom_path"}
    if {![llength [get_files -quiet -of_objects [get_filesets sources_1] $ota_rom_path]]} {
        add_files -norecurse -fileset sources_1 $ota_rom_path
    }
    set_property USED_IN {synthesis simulation} [get_files -quiet -of_objects [get_filesets sources_1] $ota_rom_path]
}
update_compile_order -fileset sources_1
puts "CFO coefficient pages registered. No synthesis, implementation or simulation started."
