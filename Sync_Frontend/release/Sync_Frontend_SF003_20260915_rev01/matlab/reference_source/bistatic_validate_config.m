function derived = bistatic_validate_config(cfg)
%BISTATIC_VALIDATE_CONFIG Recompute every frozen derived frame constant.

mustEqual(cfg.schema_version, 1, 'schema_version');
mustEqual(cfg.signal.sample_rate_hz, 500e6, 'sample_rate_hz');
mustEqual(cfg.frame.fft_length, 2048, 'fft_length');
mustEqual(cfg.frame.cyclic_prefix_samples, 512, 'cyclic_prefix_samples');
mustEqual(cfg.frame.active_subcarriers, 1640, 'active_subcarriers');
mustEqual(cfg.frame.preamble_symbols, 10, 'preamble_symbols');
mustEqual(cfg.frame.payload_symbols, 512, 'payload_symbols');
mustEqual(cfg.interface.samples_per_clock, 4, 'samples_per_clock');
mustEqual(cfg.interface.baseline_clock_hz, 125e6, 'baseline_clock_hz');

derived.total_symbols = cfg.frame.preamble_symbols + cfg.frame.payload_symbols;
derived.symbol_samples_with_cp = cfg.frame.fft_length + cfg.frame.cyclic_prefix_samples;
derived.frame_samples = derived.total_symbols * derived.symbol_samples_with_cp;
derived.frame_duration_s = derived.frame_samples / cfg.signal.sample_rate_hz;
derived.cycles_per_frame_125mhz = derived.frame_samples / cfg.interface.samples_per_clock;
derived.cycles_per_frame_150mhz = derived.frame_duration_s * cfg.interface.optimization_clock_hz;
derived.sfo_drift_max_samples = ceil(derived.frame_samples * cfg.offset_limits.sfo_ppm * 1e-6);
derived.minimum_pre_t07_halo_each_side_samples = ...
    derived.sfo_drift_max_samples + cfg.offset_limits.to_sync_samples;

positive = cfg.indexing.active_positive_zero_based_inclusive;
negative = cfg.indexing.active_negative_zero_based_inclusive;
guard = cfg.indexing.guard_zero_based_inclusive;
derived.active_count_from_ranges = positive(2) - positive(1) + 1 + ...
    negative(2) - negative(1) + 1;
derived.guard_count_from_range = guard(2) - guard(1) + 1;

mustEqual(cfg.frame.total_symbols, derived.total_symbols, 'total_symbols');
mustEqual(cfg.frame.symbol_samples_with_cp, derived.symbol_samples_with_cp, 'symbol_samples_with_cp');
mustEqual(cfg.frame.frame_samples, derived.frame_samples, 'frame_samples');
mustClose(cfg.frame.frame_duration_s, derived.frame_duration_s, 1e-15, 'frame_duration_s');
mustEqual(cfg.frame.cycles_per_frame_125mhz, derived.cycles_per_frame_125mhz, 'cycles_per_frame_125mhz');
mustClose(cfg.frame.cycles_per_frame_150mhz, derived.cycles_per_frame_150mhz, 1e-9, 'cycles_per_frame_150mhz');
mustEqual(cfg.frame.active_subcarriers, derived.active_count_from_ranges, 'active range count');
mustEqual(cfg.continuous_waveform.minimum_pre_t07_halo_each_side_samples, ...
    derived.minimum_pre_t07_halo_each_side_samples, 'minimum pre-T07 halo');

if cfg.indexing.dc_zero_based ~= 0 || positive(1) ~= 1 || positive(2) ~= 820 || ...
        guard(1) ~= 821 || guard(2) ~= 1227 || negative(1) ~= 1228 || negative(2) ~= 2047
    error('bistatic:IndexConvention', 'The unshifted frequency-bin convention is inconsistent.');
end
if cfg.continuous_waveform.default_halo_each_side_samples < ...
        derived.minimum_pre_t07_halo_each_side_samples
    error('bistatic:HaloTooSmall', 'Default halo is below the pre-T07 lower bound.');
end
if cfg.rtl_development.resource_planning_percent > cfg.rtl_development.resource_hard_limit_percent || ...
        cfg.rtl_development.resource_hard_limit_percent + ...
        cfg.rtl_development.ni_vi_minimum_reserve_percent > 100
    error('bistatic:ResourcePolicy', 'RTL resource planning/reserve policy is inconsistent.');
end

if isfield(cfg, 't02')
    mustEqual(cfg.t02.artifact_schema_version, 1, 't02 artifact schema');
    if strlength(string(cfg.t02.selected_ps1_ps2_candidate_id)) == 0 || ...
            strlength(string(cfg.t02.artifact_relative_path)) == 0
        error('bistatic:T02Config', 'T02 selected candidate and artifact path are required.');
    end
    expectedCounts = [32 64 128 256 512 1640];
    if ~isequal(double(cfg.t02.observation_candidate_counts(:)).', expectedCounts)
        error('bistatic:T02ObservationCounts', ...
            'T02 observation candidate counts do not match the frozen family.');
    end
    mustEqual(cfg.t02.payload_pilot.time_offset_zero_based, 0, ...
        't02 pilot time offset');
    mustEqual(cfg.t02.payload_pilot.pilot_bearing_symbols, 74, ...
        't02 pilot-bearing symbols');
    mustEqual(cfg.t02.payload_pilot.pilots_per_bearing_symbol, 820, ...
        't02 pilots per bearing symbol');
    mustEqual(cfg.t02.payload_pilot.total_pilots, 60680, ...
        't02 total pilots');
    mustClose(cfg.t02.payload_pilot.active_resource_element_fraction, ...
        60680 / (1640 * 512), 1e-15, 't02 pilot overhead');
    if ~strcmp(cfg.t02.payload_pilot.lattice, 'even') || ...
            ~strcmp(cfg.t02.payload_pilot.value_modulation, 'qpsk')
        error('bistatic:T02PilotDecision', ...
            'T02 production pilot must use the frozen even/QPSK decision.');
    end
    mustEqual(cfg.t02.rom.sample_count, 10 * cfg.frame.fft_length, ...
        't02 ROM sample count');
    mustEqual(cfg.t02.rom.beat_depth, ...
        cfg.t02.rom.sample_count / cfg.interface.samples_per_clock, ...
        't02 ROM beat depth');
    mustEqual(cfg.t02.rom.word_bits, cfg.interface.beat_data_bits, ...
        't02 ROM word bits');
    if cfg.t02.rom.peak_headroom_fraction <= 0 || ...
            cfg.t02.rom.peak_headroom_fraction > 1 || ...
            ~cfg.t02.rom.lane_zero_is_earliest
        error('bistatic:T02RomDecision', 'T02 ROM headroom or lane order is invalid.');
    end
end
end

function mustEqual(actual, expected, label)
if ~isequal(actual, expected)
    error('bistatic:ConfigDerivedMismatch', '%s mismatch: actual=%g expected=%g', label, actual, expected);
end
end

function mustClose(actual, expected, tolerance, label)
if abs(actual - expected) > tolerance
    error('bistatic:ConfigDerivedMismatch', '%s mismatch: actual=%.17g expected=%.17g', label, actual, expected);
end
end
