set_param general.maxThreads 8
set_param synth.maxThreads 8
if {[get_param general.maxThreads] != 8 || [get_param synth.maxThreads] != 8} {error "thread readback mismatch"}
puts "OTA_THREADS pid=[pid] general=[get_param general.maxThreads] synth=[get_param synth.maxThreads]"
