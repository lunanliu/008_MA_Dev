function bistatic_generate_rtl_package(cfg, outputPath)
%BISTATIC_GENERATE_RTL_PACKAGE Generate SystemVerilog constants from JSON.

parent = fileparts(outputPath);
if ~isempty(parent) && ~isfolder(parent)
    mkdir(parent);
end
fid = fopen(outputPath, 'wt');
if fid < 0
    error('bistatic:FileOpen', 'Cannot create RTL package: %s', outputPath);
end
cleaner = onCleanup(@() fclose(fid));

fprintf(fid, '// Generated from config/frame_config.json. Do not hand edit.\n');
fprintf(fid, '// Config SHA-256: %s\n', cfg.sha256);
fprintf(fid, 'package bistatic_frame_params_pkg;\n');
emit('SAMPLE_RATE_HZ', cfg.signal.sample_rate_hz);
emit('SAMPLES_PER_CLOCK', cfg.interface.samples_per_clock);
emit('SAMPLE_COMPONENT_BITS', cfg.signal.complex_components_bits);
emit('BEAT_DATA_BITS', cfg.interface.beat_data_bits);
emit('FFT_LENGTH', cfg.frame.fft_length);
emit('CYCLIC_PREFIX_SAMPLES', cfg.frame.cyclic_prefix_samples);
emit('ACTIVE_SUBCARRIERS', cfg.frame.active_subcarriers);
emit('PREAMBLE_SYMBOLS', cfg.frame.preamble_symbols);
emit('PAYLOAD_SYMBOLS', cfg.frame.payload_symbols);
emit('TOTAL_SYMBOLS', cfg.frame.total_symbols);
emit('SYMBOL_SAMPLES_WITH_CP', cfg.frame.symbol_samples_with_cp);
emit('FRAME_SAMPLES', cfg.frame.frame_samples);
emit('CYCLES_PER_FRAME_125MHZ', cfg.frame.cycles_per_frame_125mhz);
emit('ACTIVE_POS_FIRST_BIN', cfg.indexing.active_positive_zero_based_inclusive(1));
emit('ACTIVE_POS_LAST_BIN', cfg.indexing.active_positive_zero_based_inclusive(2));
emit('ACTIVE_NEG_FIRST_BIN', cfg.indexing.active_negative_zero_based_inclusive(1));
emit('ACTIVE_NEG_LAST_BIN', cfg.indexing.active_negative_zero_based_inclusive(2));
emit('MAX_TO_SYNC_SAMPLES', cfg.offset_limits.to_sync_samples);
emit('MAX_FO_SYNC_HZ', cfg.offset_limits.fo_sync_hz);
emit('MAX_SFO_PPM', cfg.offset_limits.sfo_ppm);
emit('MIN_PRE_T07_HALO_SAMPLES', cfg.continuous_waveform.minimum_pre_t07_halo_each_side_samples);
fprintf(fid, '  localparam bit LANE_ZERO_IS_EARLIEST = 1''b1;\n');
fprintf(fid, 'endpackage\n');

    function emit(name, value)
        fprintf(fid, '  localparam int unsigned %s = %u;\n', name, uint64(value));
    end
end
