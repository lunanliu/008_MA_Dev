# Actual fileset export, to be checked against independently frozen SOURCE_LOCK.json.
set report_dir [file join $root reports rotator_native]
file mkdir $report_dir
set handle [open [file join $report_dir actual_sources.csv] w]
puts $handle "fileset,path"
foreach fs {sources_1 constrs_1 sim_1} {
 foreach f [lsort [get_files -of_objects [get_filesets $fs]]] {
  puts $handle "$fs,[file normalize $f]"
 }
}
close $handle
set handle [open [file join $report_dir project_identity.txt] w]
puts $handle "part=[get_property PART [current_project]]"
puts $handle "hardware_top=[get_property TOP [get_filesets sources_1]]"
puts $handle "simulation_top=[get_property TOP [get_filesets sim_1]]"
puts $handle "project=[get_property DIRECTORY [current_project]]"
puts $handle "vivado=[version -short]"
puts $handle "xelab_jobs=[get_property xsim.elaborate.mt_level [get_filesets sim_1]]"
close $handle