function result = analyze_ddr_counters(statsFile)
% statsFile is JSON exported from Host after read_done and stable generation.
% Required fields: read_clock_mhz, sample_count, sent_samples, checked_samples,
% mismatch_count, replay_cycles, transfer_cycles, no_data_cycles,
% sink_stall_cycles, pause_cycles, read_done, read_fault.
% Optional write fields: write_clock_mhz, loaded_samples, load_cycles,
% data_window_cycles. Clocks must match the ACTUAL configured SCTL clocks.
s = jsondecode(fileread(statsFile));
required = {'read_clock_mhz','sample_count','sent_samples','checked_samples', ...
 'mismatch_count','replay_cycles','transfer_cycles','no_data_cycles', ...
 'sink_stall_cycles','pause_cycles','read_done','read_fault'};
for k=1:numel(required), assert(isfield(s,required{k}),'Missing field: %s',required{k}); end
countFields = {'sample_count','sent_samples','checked_samples','mismatch_count', ...
    'replay_cycles','transfer_cycles','no_data_cycles','sink_stall_cycles','pause_cycles', ...
    'loaded_samples','load_cycles','data_window_cycles'};
for k=1:numel(countFields)
    field=countFields{k};
    if isfield(s,field)
        value=s.(field);
        assert(isnumeric(value) && isscalar(value) && isfinite(value) && ...
            value>=0 && value==fix(value) && value<flintmax, ...
            'Counter %s is not an exactly representable nonnegative integer.',field);
    end
end
assert(s.sample_count>0 && mod(s.sample_count,4)==0,'Invalid sample count.');
assert(isnumeric(s.read_clock_mhz) && isscalar(s.read_clock_mhz) && ...
    isfinite(s.read_clock_mhz) && s.read_clock_mhz>0,'Invalid read clock.');
assert(s.replay_cycles>0 && s.read_clock_mhz>0,'Invalid time denominator.');
result = struct;
result.read_rate_msps = double(s.sent_samples)*double(s.read_clock_mhz)/double(s.replay_cycles);
result.replay_time_us = double(s.replay_cycles)/double(s.read_clock_mhz);
result.cycle_accounting_ok = s.replay_cycles == s.transfer_cycles+s.no_data_cycles+s.sink_stall_cycles+s.pause_cycles;
result.all_samples_checked = s.checked_samples==s.sample_count;
result.full_pattern_match = logical(s.read_done) && ~logical(s.read_fault) && ...
    s.sent_samples==s.sample_count && result.all_samples_checked && s.mismatch_count==0;
result.no_playback_gaps = logical(s.read_done) && ~logical(s.read_fault) && ...
    s.sent_samples==s.sample_count && s.transfer_cycles*4==s.sample_count && ...
    result.cycle_accounting_ok && s.no_data_cycles==0 && s.sink_stall_cycles==0 && s.pause_cycles==0;
result.sustained_500_msps_this_run = result.full_pattern_match && result.no_playback_gaps && ...
    result.read_rate_msps>=500;
if all(isfield(s,{'write_clock_mhz','loaded_samples','load_cycles','data_window_cycles'}))
    if s.load_cycles>0
        result.write_overall_msps=double(s.loaded_samples)*double(s.write_clock_mhz)/double(s.load_cycles);
    end
    if s.data_window_cycles>0
        result.write_data_window_msps=double(s.loaded_samples)*double(s.write_clock_mhz)/double(s.data_window_cycles);
    end
end
disp(result);
% This is a bounded board-run result, not a DDR latency guarantee for all loads.
end