# Sourced in each Vivado run process, not only in the parent GUI.
# These are requested limits; the native stage log states effective parallelism.
set_param general.maxThreads 8
set_param synth.maxThreads 8
if {[get_param general.maxThreads] != 8 || [get_param synth.maxThreads] != 8} {
    error "Vivado did not accept the requested thread limits."
}
puts "CFO_THREAD_LIMITS pid=[pid] cwd=[pwd] general=[get_param general.maxThreads] synth=[get_param synth.maxThreads]"
