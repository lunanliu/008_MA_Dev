# Read-only project manager check. No compile/elaborate/run/generate/save commands.
set audit_dir [file normalize [file dirname [info script]]]
set root D:/008_MA_Dev
set_param general.maxThreads 8
set_param synth.maxThreads 8
set projects [list [file join $root Sync_SFO Sync_SFO.xpr] [file join $root Sync_Frontend Sync_Frontend.xpr]]
foreach name {CFO_BACKEND74 CFO_COORD CFO_FFT2048 CFO_FFT256 CFO_FRONT2048 CFO_LINK010 CFO_LINK010R1 CFO_PHASE74 CFO_SYNC} {
    lappend projects [file join $root Sync_CFO vivado $name ${name}.xpr]
}
lappend projects [file join $root Sync_Frontend examples I16_AddSub_CLIP I16_AddSub.xpr]
set index 0
set results [open [file join $audit_dir native_open_summary.tsv] w]
puts $results "index\txpr\tpart\ttop\tfiles\tips"
foreach project $projects {
    incr index
    puts "REORG_OPEN_BEGIN index=$index xpr=$project"
    open_project -read_only $project
    set part [get_property PART [current_project]]
    set top [get_property TOP [get_filesets sources_1]]
    if {$part ne "xcvu11p-flgb2104-2-e"} {error "Unexpected part $part"}
    set fh [open [file join $audit_dir native_files_${index}.tsv] w]
    puts $fh "fileset\tpath\tfile_type\tlibrary"
    set count 0
    foreach fs [get_filesets] {
        foreach f [get_files -quiet -of_objects $fs] {
            puts $fh "[get_property NAME $fs]\t[get_property NAME $f]\t[get_property FILE_TYPE $f]\t[get_property LIBRARY $f]"
            incr count
        }
    }
    close $fh
    set ipcount [llength [get_ips -quiet]]
    puts $results "$index\t$project\t$part\t$top\t$count\t$ipcount"
    flush $results
    puts "REORG_OPEN_PASS index=$index top=$top members=$count ips=$ipcount"
    close_project
}
close $results
puts "REORG_NATIVE_OPEN_ALL_COMPLETE count=$index"
exit
