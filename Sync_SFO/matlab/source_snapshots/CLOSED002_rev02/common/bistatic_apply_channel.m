function received = bistatic_apply_channel(waveform, cfg, impairment, profile, noiseSeed)
%BISTATIC_APPLY_CHANNEL Apply all offsets on one absolute continuous timeline.
% Positive TO means later arrival. Positive SFO means
% Fs_rx=Fs_tx*(1+sfo*1e-6), hence source position advances by less than one Tx
% sample per Rx sample. CFO and path Doppler use exp(+j*2*pi*f*t).

impairment = withDefault(impairment, 'to_clock_samples', 0);
impairment = withDefault(impairment, 'propagation_delay_samples', 0);
impairment = withDefault(impairment, 'cfo_oscillator_hz', 0);
impairment = withDefault(impairment, 'los_doppler_hz', 0);
impairment = withDefault(impairment, 'sfo_ppm', 0);
impairment = withDefault(impairment, 'noise_enabled', false);
impairment = withDefault(impairment, 'snr_db', 300);
impairment = withDefault(impairment, 'noise_reference', 'aggregate_received_signal');
impairment = withDefault(impairment, 'interpolation_method', 'pchip');

fsTx = cfg.signal.sample_rate_hz;
fsRx = fsTx * (1 + impairment.sfo_ppm * 1e-6);
if fsRx <= 0
    error('bistatic:SfoRange', 'Resulting receive sample rate must be positive.');
end
globalIndex = (waveform.global_first_sample:waveform.global_last_sample).';
if numel(globalIndex) ~= numel(waveform.samples)
    error('bistatic:WaveformMetadata', 'Global sample range does not match waveform length.');
end
sourceBase = globalIndex * (fsTx / fsRx) - impairment.to_clock_samples - ...
    impairment.propagation_delay_samples;
timeSeconds = globalIndex / fsRx;

signal = complex(zeros(size(waveform.samples)));
referenceSignal = complex(zeros(size(waveform.samples)));
for tap = 1:numel(profile.complex_gain)
    sourcePosition = sourceBase - profile.delay_samples(tap);
    delayed = interp1(globalIndex, waveform.samples, sourcePosition, ...
        impairment.interpolation_method, 0);
    totalFrequency = impairment.cfo_oscillator_hz + impairment.los_doppler_hz + ...
        profile.doppler_hz(tap);
    rotation = exp(1j * 2 * pi * totalFrequency * timeSeconds);
    pathSignal = profile.complex_gain(tap) .* delayed .* rotation;
    signal = signal + pathSignal;
    if tap == profile.reference_tap_index
        referenceSignal = pathSignal;
    end
end

nominalRange = waveform.nominal_start_index:waveform.nominal_end_index;
signalPower = mean(abs(signal(nominalRange)).^2);
referenceSignalPower = mean(abs(referenceSignal(nominalRange)).^2);
noisePower = 0;
if impairment.noise_enabled
    if ~isfinite(impairment.snr_db)
        error('bistatic:Snr', 'Enabled noise requires a finite SNR.');
    end
    switch impairment.noise_reference
        case 'aggregate_received_signal'
            noiseReferencePower = signalPower;
        case 'reference_los_tap'
            noiseReferencePower = referenceSignalPower;
        otherwise
            error('bistatic:NoiseReference', 'Unknown noise reference: %s', impairment.noise_reference);
    end
    noisePower = noiseReferencePower / 10^(impairment.snr_db / 10);
    rs = RandStream(cfg.rng.algorithm, 'Seed', noiseSeed);
    noise = sqrt(noisePower / 2) * (randn(rs, size(signal)) + 1j * randn(rs, size(signal)));
    signal = signal + noise;
end

reference = profile.reference_tap_index;
received.samples = signal;
received.source_position_reference = sourceBase - profile.delay_samples(reference);
received.absolute_time_s = timeSeconds;
received.nominal_start_index = waveform.nominal_start_index;
received.nominal_end_index = waveform.nominal_end_index;
received.global_first_sample = waveform.global_first_sample;
received.global_last_sample = waveform.global_last_sample;
received.metadata.physical.to_clock_samples = impairment.to_clock_samples;
received.metadata.physical.tau_reference_samples = impairment.propagation_delay_samples + ...
    profile.delay_samples(reference);
received.metadata.physical.cfo_oscillator_hz = impairment.cfo_oscillator_hz;
received.metadata.physical.fd_reference_hz = impairment.los_doppler_hz + ...
    profile.doppler_hz(reference);
received.metadata.physical.sfo_ppm = impairment.sfo_ppm;
received.metadata.physical.fs_tx_hz = fsTx;
received.metadata.physical.fs_rx_hz = fsRx;
received.metadata.truth.to_sync_true_samples = impairment.to_clock_samples + ...
    impairment.propagation_delay_samples + profile.delay_samples(reference);
received.metadata.truth.fo_sync_true_hz = impairment.cfo_oscillator_hz + ...
    impairment.los_doppler_hz + profile.doppler_hz(reference);
received.metadata.truth.reference_semantics = ternary(profile.has_physical_los, ...
    'los_referenced', 'earliest_path_surrogate_nlos_stress');
received.metadata.channel.profile = profile.name;
received.metadata.channel.classification = profile.classification;
received.metadata.channel.seed = profile.seed;
received.metadata.channel.has_physical_los = profile.has_physical_los;
received.metadata.channel.maximum_delay_samples = profile.maximum_delay_samples;
received.metadata.channel.within_cp = profile.within_cp;
received.metadata.noise.enabled = impairment.noise_enabled;
received.metadata.noise.requested_snr_db = impairment.snr_db;
received.metadata.noise.signal_power_before_noise = signalPower;
received.metadata.noise.reference_tap_power_before_noise = referenceSignalPower;
received.metadata.noise.reference_semantics = impairment.noise_reference;
received.metadata.noise.noise_power = noisePower;
received.metadata.timeline.sfo_sign_convention = ...
    'Fs_rx=Fs_tx*(1+sfo_ppm*1e-6); source_step=Fs_tx/Fs_rx';
received.metadata.timeline.frequency_sign_convention = 'exp(+j*2*pi*f*t)';
received.metadata.timeline.interpolation_method = impairment.interpolation_method;
end

function value = withDefault(value, fieldName, defaultValue)
if ~isfield(value, fieldName)
    value.(fieldName) = defaultValue;
end
end

function output = ternary(condition, trueValue, falseValue)
if condition
    output = trueValue;
else
    output = falseValue;
end
end
