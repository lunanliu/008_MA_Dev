function received = bistatic_apply_cp_ofdm_channel( ...
        waveform, cfg, impairment, profile, noiseSeed, descriptor)
%BISTATIC_APPLY_CP_OFDM_CHANNEL Owner-safe project CP-OFDM channel oracle.
% This entry point is intentionally separate from the generic sample-domain
% channel. It regenerates the bound OFDM symbols, uses an L128 INTERPFT grid
% for interior queries, and switches only boundary-crossing non-exact queries
% to direct Fourier evaluation with the query owner's own frequency symbol.

narginchk(6, 6);
nargoutchk(0, 1);

[descriptor, artifacts] = validateDescriptor(descriptor, cfg, waveform);
validateWaveform(waveform, cfg, descriptor);
validateRegeneratedWaveform(waveform, cfg, descriptor, artifacts);
profile = validateProfile(profile);
impairment = normalizeImpairment(impairment);

fsTx = double(cfg.signal.sample_rate_hz);
fsRx = fsTx * (1 + impairment.sfo_ppm * 1e-6);
if ~isfinite(fsRx) || fsRx <= 0
    error('bistatic:CpOfdmSfoRange', ...
        'Resulting receive sample rate must be finite and positive.');
end

globalIndex = (waveform.global_first_sample:waveform.global_last_sample).';
outputCount = numel(globalIndex);
sourceStep = fsTx / fsRx;
commonDelay = impairment.to_clock_samples + ...
    impairment.propagation_delay_samples;
sourceBase = globalIndex * sourceStep - commonDelay;
timeSeconds = globalIndex / fsRx;

nfft = double(cfg.frame.fft_length);
ncp = double(cfg.frame.cyclic_prefix_samples);
symbolSamples = double(cfg.frame.symbol_samples_with_cp);
totalSymbols = double(cfg.frame.total_symbols);
L = 128;

minimumSource = sourceBase(1) - max(profile.delay_samples);
maximumSource = sourceBase(end) - min(profile.delay_samples);
firstOwnerKey = floor(minimumSource / symbolSamples);
lastOwnerKey = floor(maximumSource / symbolSamples);
ownerKeys = (firstOwnerKey:lastOwnerKey).';
if isempty(ownerKeys)
    error('bistatic:CpOfdmOwnerRange', ...
        'No physical CP-OFDM owner covers the requested output range.');
end

ownerFrameOffset = floor(ownerKeys / totalSymbols);
ownerFrameIds = descriptor.anchor_frame_id + ownerFrameOffset;
ownerSymbolIds = ownerKeys - ownerFrameOffset * totalSymbols;
if any(ownerSymbolIds < 0) || any(ownerSymbolIds >= totalSymbols) || ...
        any(~ismember(ownerFrameIds, descriptor.context_frame_ids))
    error('bistatic:CpOfdmMissingContext', ...
        'The descriptor does not contain every physical source owner.');
end

[officialInterpft, officialInterpftPath] = resolveOfficialInterpft();
signal = complex(zeros(outputCount, 1));
referenceSignal = complex(zeros(outputCount, 1));
tapCount = numel(profile.complex_gain);
coverage = zeros(outputCount, tapCount, 'uint8');

branch.exact_query_count = uint64(0);
branch.b8_query_count = uint64(0);
branch.direct_fourier_query_count = uint64(0);
branch.unread_exact_cross_owner_node_count = uint64(0);
branch.exact_query_with_unread_cross_owner_count = uint64(0);
branch.nonexact_cross_owner_node_count = uint64(0);
branch.direct_fourier_nonzero_term_count = uint64(0);
gridBuildCount = uint64(0);
ownerTapDispatchCount = uint64(0);

cachedFrameId = nan;
cachedFrequencySymbols = complex(zeros(nfft, 0));
for ownerIndex = 1:numel(ownerKeys)
    ownerKey = ownerKeys(ownerIndex);
    ownerFrameId = ownerFrameIds(ownerIndex);
    ownerSymbolId = ownerSymbolIds(ownerIndex);
    ownerCpStart = ownerKey * symbolSamples;

    if ownerFrameId ~= cachedFrameId
        [~, cachedFrequencySymbols] = bistatic_generate_frame(cfg, ...
            ownerFrameId, descriptor.base_seed, artifacts);
        cachedFrameId = ownerFrameId;
    end
    fdBins = cachedFrequencySymbols(:, ownerSymbolId + 1);
    validateFrequencySymbol(fdBins, cfg);
    grid = officialInterpft(ifft(fdBins, nfft), nfft * L);
    if ~isa(grid, 'double') || ~isvector(grid) || ...
            numel(grid) ~= nfft * L || ...
            any(~isfinite(real(grid))) || any(~isfinite(imag(grid)))
        error('bistatic:CpOfdmInterpftGrid', ...
            'Official INTERPFT returned an invalid owner grid.');
    end
    grid = grid(:);
    gridBuildCount = gridBuildCount + uint64(1);

    for tapIndex = 1:tapCount
        pathDelay = profile.delay_samples(tapIndex);
        lowerReal = (ownerCpStart + commonDelay + pathDelay) / sourceStep;
        upperReal = (ownerCpStart + symbolSamples + ...
            commonDelay + pathDelay) / sourceStep;
        candidateFirst = max(waveform.global_first_sample, ...
            floor(lowerReal) - 1);
        candidateLast = min(waveform.global_last_sample, ...
            ceil(upperReal) + 1);
        if candidateFirst > candidateLast
            continue
        end
        candidateRx = (candidateFirst:candidateLast).';
        candidateSource = candidateRx * sourceStep - ...
            commonDelay - pathDelay;
        ownerMask = floor(candidateSource / symbolSamples) == ownerKey;
        ownedRx = candidateRx(ownerMask);
        if isempty(ownedRx)
            continue
        end
        ownedSource = candidateSource(ownerMask);
        withinUseful = ownedSource - (ownerCpStart + ncp);
        [interpolated, queryDiagnostics] = ...
            bistatic_cp_ofdm_interpft8_l128_hybrid_query( ...
            fdBins, grid, withinUseful, ownedSource, ownerCpStart, ...
            nfft, ncp, L);
        validateQueryDiagnostics(queryDiagnostics, numel(ownedRx));

        totalFrequency = impairment.cfo_oscillator_hz + ...
            impairment.los_doppler_hz + profile.doppler_hz(tapIndex);
        outputIndex = ownedRx - waveform.global_first_sample + 1;
        rotation = exp(1j * 2 * pi * totalFrequency * ...
            timeSeconds(outputIndex));
        pathSignal = profile.complex_gain(tapIndex) .* ...
            interpolated .* rotation;
        signal(outputIndex) = signal(outputIndex) + pathSignal;
        if tapIndex == profile.reference_tap_index
            referenceSignal(outputIndex) = pathSignal;
        end
        coverage(outputIndex, tapIndex) = ...
            coverage(outputIndex, tapIndex) + uint8(1);
        ownerTapDispatchCount = ownerTapDispatchCount + uint64(1);

        branch.exact_query_count = branch.exact_query_count + ...
            uint64(queryDiagnostics.exact_query_count);
        branch.b8_query_count = branch.b8_query_count + ...
            uint64(queryDiagnostics.b8_query_count);
        branch.direct_fourier_query_count = ...
            branch.direct_fourier_query_count + ...
            uint64(queryDiagnostics.direct_fourier_query_count);
        branch.unread_exact_cross_owner_node_count = ...
            branch.unread_exact_cross_owner_node_count + ...
            uint64(queryDiagnostics.unread_exact_cross_owner_node_count);
        branch.exact_query_with_unread_cross_owner_count = ...
            branch.exact_query_with_unread_cross_owner_count + ...
            uint64(queryDiagnostics.exact_query_with_unread_cross_owner_count);
        branch.nonexact_cross_owner_node_count = ...
            branch.nonexact_cross_owner_node_count + ...
            uint64(queryDiagnostics.nonexact_cross_owner_node_count);
        branch.direct_fourier_nonzero_term_count = ...
            branch.direct_fourier_nonzero_term_count + ...
            uint64(queryDiagnostics.direct_fourier_query_count) * ...
            uint64(queryDiagnostics.direct_fourier_nonzero_bin_count);
    end
end

coverageGapCount = nnz(coverage == 0);
coverageDuplicateCount = nnz(coverage > 1);
expectedQueryCount = uint64(outputCount) * uint64(tapCount);
partitionQueryCount = branch.exact_query_count + branch.b8_query_count + ...
    branch.direct_fourier_query_count;
if coverageGapCount ~= 0 || coverageDuplicateCount ~= 0 || ...
        partitionQueryCount ~= expectedQueryCount
    error('bistatic:CpOfdmCoverage', ...
        ['Owner dispatch failed: gap=%d duplicate=%d partition=%u ' ...
        'expected=%u.'], coverageGapCount, coverageDuplicateCount, ...
        partitionQueryCount, expectedQueryCount);
end
if any(~isfinite(real(signal))) || any(~isfinite(imag(signal)))
    error('bistatic:CpOfdmOutputFinite', ...
        'The CP-OFDM channel produced a nonfinite sample.');
end

nominalRange = waveform.nominal_start_index:waveform.nominal_end_index;
signalPower = mean(abs(signal(nominalRange)).^2);
referenceSignalPower = mean(abs(referenceSignal(nominalRange)).^2);
noisePower = 0;
if impairment.noise_enabled
    switch impairment.noise_reference
        case 'aggregate_received_signal'
            noiseReferencePower = signalPower;
        case 'reference_los_tap'
            noiseReferencePower = referenceSignalPower;
        otherwise
            error('bistatic:CpOfdmNoiseReference', ...
                'Unknown noise reference: %s', impairment.noise_reference);
    end
    noisePower = noiseReferencePower / 10^(impairment.snr_db / 10);
    rs = RandStream(cfg.rng.algorithm, 'Seed', noiseSeed);
    noise = sqrt(noisePower / 2) * ...
        (randn(rs, size(signal)) + 1j * randn(rs, size(signal)));
    signal = signal + noise;
end

referenceTap = profile.reference_tap_index;
received.samples = signal;
received.source_position_reference = sourceBase - ...
    profile.delay_samples(referenceTap);
received.absolute_time_s = timeSeconds;
received.nominal_start_index = waveform.nominal_start_index;
received.nominal_end_index = waveform.nominal_end_index;
received.global_first_sample = waveform.global_first_sample;
received.global_last_sample = waveform.global_last_sample;
received.metadata.physical.to_clock_samples = ...
    impairment.to_clock_samples;
received.metadata.physical.tau_reference_samples = ...
    impairment.propagation_delay_samples + ...
    profile.delay_samples(referenceTap);
received.metadata.physical.cfo_oscillator_hz = ...
    impairment.cfo_oscillator_hz;
received.metadata.physical.fd_reference_hz = ...
    impairment.los_doppler_hz + profile.doppler_hz(referenceTap);
received.metadata.physical.sfo_ppm = impairment.sfo_ppm;
received.metadata.physical.fs_tx_hz = fsTx;
received.metadata.physical.fs_rx_hz = fsRx;
received.metadata.truth.to_sync_true_samples = ...
    impairment.to_clock_samples + impairment.propagation_delay_samples + ...
    profile.delay_samples(referenceTap);
received.metadata.truth.fo_sync_true_hz = ...
    impairment.cfo_oscillator_hz + impairment.los_doppler_hz + ...
    profile.doppler_hz(referenceTap);
received.metadata.truth.reference_semantics = ternary( ...
    profile.has_physical_los, 'los_referenced', ...
    'earliest_path_surrogate_nlos_stress');
received.metadata.channel.profile = profile.name;
received.metadata.channel.classification = profile.classification;
received.metadata.channel.seed = profile.seed;
received.metadata.channel.has_physical_los = profile.has_physical_los;
received.metadata.channel.maximum_delay_samples = ...
    profile.maximum_delay_samples;
received.metadata.channel.within_cp = profile.within_cp;
received.metadata.noise.enabled = impairment.noise_enabled;
received.metadata.noise.requested_snr_db = impairment.snr_db;
received.metadata.noise.signal_power_before_noise = signalPower;
received.metadata.noise.reference_tap_power_before_noise = ...
    referenceSignalPower;
received.metadata.noise.reference_semantics = ...
    impairment.noise_reference;
received.metadata.noise.noise_power = noisePower;
received.metadata.timeline.sfo_sign_convention = ...
    'Fs_rx=Fs_tx*(1+sfo_ppm*1e-6); source_step=Fs_tx/Fs_rx';
received.metadata.timeline.frequency_sign_convention = ...
    'exp(+j*2*pi*f*t)';
received.metadata.timeline.interpolation_method = ...
    descriptor.reference_method;
received.metadata.reference.schema = ...
    'bistatic_cp_ofdm_channel_reference_diagnostics_v1';
received.metadata.reference.descriptor_schema = descriptor.schema;
received.metadata.reference.descriptor_waveform_numeric_sha256 = ...
    descriptor.waveform_numeric_sha256;
received.metadata.reference.artifact_content_sha256 = ...
    descriptor.artifact_content_sha256;
received.metadata.reference.owner_symbol_count = numel(ownerKeys);
received.metadata.reference.grid_build_count = gridBuildCount;
received.metadata.reference.owner_tap_dispatch_count = ...
    ownerTapDispatchCount;
received.metadata.reference.expected_query_count = expectedQueryCount;
received.metadata.reference.exact_query_count = branch.exact_query_count;
received.metadata.reference.b8_query_count = branch.b8_query_count;
received.metadata.reference.direct_fourier_query_count = ...
    branch.direct_fourier_query_count;
received.metadata.reference.unread_exact_cross_owner_node_count = ...
    branch.unread_exact_cross_owner_node_count;
received.metadata.reference.exact_query_with_unread_cross_owner_count = ...
    branch.exact_query_with_unread_cross_owner_count;
received.metadata.reference.nonexact_cross_owner_node_count = ...
    branch.nonexact_cross_owner_node_count;
received.metadata.reference.direct_fourier_nonzero_term_count = ...
    branch.direct_fourier_nonzero_term_count;
received.metadata.reference.coverage_gap_count = coverageGapCount;
received.metadata.reference.coverage_duplicate_count = ...
    coverageDuplicateCount;
received.metadata.reference.generic_fallback_used = false;
received.metadata.reference.pchip_fallback_used = false;
received.metadata.reference.official_interpft_path = officialInterpftPath;
received.metadata.reference.all_checks_passed = true;
end

function [descriptor, artifacts] = validateDescriptor(descriptor, cfg, waveform)
required = {'schema', 'signal_class', 'mode', 'reference_method', ...
    'generic_fallback_allowed', 'pchip_fallback_allowed', ...
    'config_sha256', 'artifact_source_kind', 'artifact_source_path', ...
    'artifact_sha256', 'artifact_content_sha256', ...
    'artifacts_snapshot', 'base_seed', 'anchor_frame_id', 'frame_ids', ...
    'context_frame_ids', 'requested_output_global_range', ...
    'available_context_global_range', 'waveform_numeric_sha256'};
requireScalarStruct(descriptor, 'descriptor');
requireFields(descriptor, required, 'descriptor');
if ~strcmp(textScalar(descriptor.schema, 'descriptor.schema'), ...
        'bistatic_cp_ofdm_channel_descriptor_v1') || ...
        ~strcmp(textScalar(descriptor.signal_class, ...
        'descriptor.signal_class'), 'project_cp_ofdm') || ...
        ~strcmp(textScalar(descriptor.reference_method, ...
        'descriptor.reference_method'), ...
        'interpft_l128_barycentric8_boundary_direct_fourier') || ...
        ~islogical(descriptor.generic_fallback_allowed) || ...
        ~isscalar(descriptor.generic_fallback_allowed) || ...
        descriptor.generic_fallback_allowed || ...
        ~islogical(descriptor.pchip_fallback_allowed) || ...
        ~isscalar(descriptor.pchip_fallback_allowed) || ...
        descriptor.pchip_fallback_allowed
    error('bistatic:CpOfdmDescriptorContract', ...
        'The descriptor does not authorize the frozen owner-safe method.');
end

options.mode = descriptor.mode;
options.frame_ids = descriptor.frame_ids;
options.base_seed = descriptor.base_seed;
options.anchor_frame_id = descriptor.anchor_frame_id;
options.config_sha256 = descriptor.config_sha256;
options.waveform_numeric_sha256 = ...
    bistatic_waveform_numeric_sha256(waveform);
options.requested_global_range = ...
    descriptor.requested_output_global_range;
options.context_frame_ids = descriptor.context_frame_ids;
options.context_global_range = descriptor.available_context_global_range;
options.artifact_content_sha256 = descriptor.artifact_content_sha256;
if strcmp(descriptor.artifact_source_kind, 'file_bytes')
    options.artifact_source_path = descriptor.artifact_source_path;
    options.artifact_sha256 = descriptor.artifact_sha256;
else
    requireFields(descriptor, {'research_artifact_id'}, 'descriptor');
    options.research_artifact_id = descriptor.research_artifact_id;
    options.artifact_sha256 = 'NOT_APPLICABLE_RESEARCH';
end
rebuilt = bistatic_make_cp_ofdm_descriptor( ...
    cfg, descriptor.artifacts_snapshot, options);
critical = {'schema', 'mode', 'reference_method', 'config_sha256', ...
    'artifact_source_kind', 'artifact_source_path', 'artifact_sha256', ...
    'artifact_content_sha256', 'base_seed', 'anchor_frame_id', ...
    'frame_ids', 'context_frame_ids', 'requested_output_global_range', ...
    'available_context_global_range', 'waveform_numeric_sha256'};
for index = 1:numel(critical)
    name = critical{index};
    if ~isequal(rebuilt.(name), descriptor.(name))
        error('bistatic:CpOfdmDescriptorIntegrity', ...
            'Descriptor field %s failed independent reconstruction.', name);
    end
end
descriptor = rebuilt;
artifacts = descriptor.artifacts_snapshot;
end

function validateWaveform(waveform, cfg, descriptor)
required = {'samples', 'global_first_sample', 'global_last_sample', ...
    'nominal_start_index', 'nominal_end_index', 'frame_ids', ...
    'base_seed', 'artifact_class', 'production_artifacts', ...
    'config_sha256'};
requireScalarStruct(waveform, 'waveform');
requireFields(waveform, required, 'waveform');
if ~isa(waveform.samples, 'double') || ~iscolumn(waveform.samples) || ...
        isempty(waveform.samples) || ...
        any(~isfinite(real(waveform.samples))) || ...
        any(~isfinite(imag(waveform.samples)))
    error('bistatic:CpOfdmWaveformSamples', ...
        'waveform.samples must be a finite complex-double column.');
end
first = exactInteger(waveform.global_first_sample, ...
    'waveform.global_first_sample');
last = exactInteger(waveform.global_last_sample, ...
    'waveform.global_last_sample');
if last < first || numel(waveform.samples) ~= last - first + 1 || ...
        ~isequal([first last], descriptor.requested_output_global_range)
    error('bistatic:CpOfdmWaveformRange', ...
        'Waveform sample count/range does not match the descriptor.');
end
if ~isequal(double(waveform.frame_ids(:).'), descriptor.frame_ids) || ...
        double(waveform.base_seed) ~= descriptor.base_seed || ...
        descriptor.anchor_frame_id ~= descriptor.frame_ids(1) || ...
        ~strcmp(textScalar(waveform.artifact_class, ...
        'waveform.artifact_class'), descriptor.artifact_class) || ...
        ~isequal(logical(waveform.production_artifacts), ...
        logical(descriptor.production_allowed)) || ...
        ~strcmp(textScalar(waveform.config_sha256, ...
        'waveform.config_sha256'), cfg.sha256)
    error('bistatic:CpOfdmWaveformProvenance', ...
        'Waveform provenance does not match the descriptor.');
end
nominalFirst = exactInteger(waveform.nominal_start_index, ...
    'waveform.nominal_start_index');
nominalLast = exactInteger(waveform.nominal_end_index, ...
    'waveform.nominal_end_index');
if nominalFirst < 1 || nominalLast > numel(waveform.samples) || ...
        nominalFirst > nominalLast
    error('bistatic:CpOfdmWaveformNominalRange', ...
        'Waveform nominal indices are outside the sample vector.');
end
if ~strcmp(bistatic_waveform_numeric_sha256(waveform), ...
        descriptor.waveform_numeric_sha256)
    error('bistatic:CpOfdmWaveformHash', ...
        'Waveform numeric SHA-256 does not match the descriptor.');
end
end

function validateRegeneratedWaveform(waveform, cfg, descriptor, artifacts)
first = double(waveform.global_first_sample);
last = double(waveform.global_last_sample);
expected = complex(zeros(last - first + 1, 1));
coverage = false(size(expected));
frameSamples = double(cfg.frame.frame_samples);
for frameId = descriptor.context_frame_ids
    frameFirst = (frameId - descriptor.anchor_frame_id) * frameSamples;
    frameLast = frameFirst + frameSamples - 1;
    overlapFirst = max(first, frameFirst);
    overlapLast = min(last, frameLast);
    if overlapFirst > overlapLast
        continue
    end
    frame = bistatic_generate_frame( ...
        cfg, frameId, descriptor.base_seed, artifacts);
    source = (overlapFirst - frameFirst + 1):(overlapLast - frameFirst + 1);
    destination = (overlapFirst - first + 1):(overlapLast - first + 1);
    expected(destination) = frame(source);
    coverage(destination) = true;
end
if any(~coverage) || ~isequal(expected, waveform.samples)
    error('bistatic:CpOfdmWaveformRegeneration', ...
        'Waveform does not exactly match its declared regenerated context.');
end
end

function profile = validateProfile(profile)
required = {'name', 'seed', 'complex_gain', 'delay_samples', ...
    'doppler_hz', 'reference_tap_index', 'has_physical_los', ...
    'classification', 'maximum_delay_samples', 'within_cp'};
requireScalarStruct(profile, 'profile');
requireFields(profile, required, 'profile');
tapCount = numel(profile.complex_gain);
if tapCount < 1 || numel(profile.delay_samples) ~= tapCount || ...
        numel(profile.doppler_hz) ~= tapCount || ...
        any(~isfinite(real(profile.complex_gain))) || ...
        any(~isfinite(imag(profile.complex_gain))) || ...
        any(~isfinite(profile.delay_samples)) || ...
        any(profile.delay_samples < 0) || ...
        any(~isfinite(profile.doppler_hz)) || ...
        profile.reference_tap_index < 1 || ...
        profile.reference_tap_index > tapCount || ...
        profile.reference_tap_index ~= fix(profile.reference_tap_index)
    error('bistatic:CpOfdmProfile', ...
        'The channel profile has invalid tap arrays or reference index.');
end
profile.complex_gain = profile.complex_gain(:);
profile.delay_samples = double(profile.delay_samples(:));
profile.doppler_hz = double(profile.doppler_hz(:));
end

function impairment = normalizeImpairment(impairment)
requireScalarStruct(impairment, 'impairment');
impairment = withDefault(impairment, 'to_clock_samples', 0);
impairment = withDefault(impairment, 'propagation_delay_samples', 0);
impairment = withDefault(impairment, 'cfo_oscillator_hz', 0);
impairment = withDefault(impairment, 'los_doppler_hz', 0);
impairment = withDefault(impairment, 'sfo_ppm', 0);
impairment = withDefault(impairment, 'noise_enabled', false);
impairment = withDefault(impairment, 'snr_db', 300);
impairment = withDefault(impairment, 'noise_reference', ...
    'aggregate_received_signal');
numericFields = {'to_clock_samples', 'propagation_delay_samples', ...
    'cfo_oscillator_hz', 'los_doppler_hz', 'sfo_ppm'};
for index = 1:numel(numericFields)
    value = impairment.(numericFields{index});
    if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
            ~isfinite(value)
        error('bistatic:CpOfdmImpairment', ...
            'Impairment field %s must be one finite real scalar.', ...
            numericFields{index});
    end
    impairment.(numericFields{index}) = double(value);
end
if ~islogical(impairment.noise_enabled) || ...
        ~isscalar(impairment.noise_enabled)
    error('bistatic:CpOfdmImpairment', ...
        'impairment.noise_enabled must be a logical scalar.');
end
snrValue = impairment.snr_db;
if ~isnumeric(snrValue) || ~isscalar(snrValue) || ~isreal(snrValue) || ...
        isnan(snrValue) || (impairment.noise_enabled && ~isfinite(snrValue))
    error('bistatic:CpOfdmImpairment', ...
        ['impairment.snr_db must be a real non-NaN scalar and must be ' ...
        'finite whenever noise is enabled.']);
end
impairment.snr_db = double(snrValue);
impairment.noise_reference = textScalar( ...
    impairment.noise_reference, 'impairment.noise_reference');
if isfield(impairment, 'interpolation_method') && ...
        ~isempty(impairment.interpolation_method) && ...
        ~strcmp(textScalar(impairment.interpolation_method, ...
        'impairment.interpolation_method'), ...
        'interpft_l128_barycentric8_boundary_direct_fourier')
    error('bistatic:CpOfdmInterpolationMethod', ...
        ['The CP-OFDM API rejects generic interpolation_method values; ' ...
        'use the named sample-domain API for those experiments.']);
end
end

function validateFrequencySymbol(fdBins, cfg)
nfft = double(cfg.frame.fft_length);
if ~isa(fdBins, 'double') || ~iscolumn(fdBins) || ...
        numel(fdBins) ~= nfft || ...
        any(~isfinite(real(fdBins))) || any(~isfinite(imag(fdBins)))
    error('bistatic:CpOfdmFrequencySymbol', ...
        'Regenerated frequency symbol is invalid.');
end
active = bistatic_active_indices(cfg);
activeMask = false(nfft, 1);
activeMask(active) = true;
if any(fdBins(~activeMask) ~= 0) || fdBins(nfft / 2 + 1) ~= 0
    error('bistatic:CpOfdmFrequencySupport', ...
        'Regenerated symbol violates the frozen active-bin support.');
end
end

function validateQueryDiagnostics(value, queryCount)
required = {'query_count', 'exact_query_count', 'b8_query_count', ...
    'direct_fourier_query_count', ...
    'unread_exact_cross_owner_node_count', ...
    'exact_query_with_unread_cross_owner_count', ...
    'nonexact_cross_owner_node_count', ...
    'direct_fourier_nonzero_bin_count', 'query_owner_mismatch_count', ...
    'drop_count', 'duplicate_count', 'reorder_count', ...
    'nonfinite_count', 'pchip_fallback_used', ...
    'generic_sample_fallback_used', 'all_checks_passed'};
requireScalarStruct(value, 'query diagnostics');
requireFields(value, required, 'query diagnostics');
partition = value.exact_query_count + value.b8_query_count + ...
    value.direct_fourier_query_count;
if value.query_count ~= queryCount || partition ~= queryCount || ...
        value.query_owner_mismatch_count ~= 0 || ...
        value.drop_count ~= 0 || value.duplicate_count ~= 0 || ...
        value.reorder_count ~= 0 || value.nonfinite_count ~= 0 || ...
        value.pchip_fallback_used || value.generic_sample_fallback_used || ...
        ~value.all_checks_passed
    error('bistatic:CpOfdmQueryDiagnostics', ...
        'The owner-safe query helper failed its branch/coverage contract.');
end
end

function [officialFunction, officialPath] = resolveOfficialInterpft()
persistent boundFunction boundPath
canonicalPath = fullfile(matlabroot, 'toolbox', 'matlab', 'polyfun', ...
    'interpft.m');
activePath = which('interpft');
if isempty(activePath) || ~isfile(activePath) || ...
        ~isfile(canonicalPath) || ~samePath(activePath, canonicalPath)
    error('bistatic:CpOfdmInterpftResolution', ...
        'Active INTERPFT must be the canonical MATLAB implementation.');
end
if isempty(boundFunction)
    boundFunction = str2func('interpft');
    details = functions(boundFunction);
    if ~isfield(details, 'file') || isempty(details.file) || ...
            ~samePath(details.file, activePath)
        error('bistatic:CpOfdmInterpftHandle', ...
            'INTERPFT function handle is not bound to the canonical file.');
    end
    boundPath = activePath;
elseif ~samePath(boundPath, activePath)
    error('bistatic:CpOfdmInterpftDrift', ...
        'The resolved INTERPFT path changed after binding.');
end
officialFunction = boundFunction;
officialPath = boundPath;
end

function yes = samePath(firstPath, secondPath)
firstCanonical = char(java.io.File(firstPath).getCanonicalPath());
secondCanonical = char(java.io.File(secondPath).getCanonicalPath());
yes = strcmpi(firstCanonical, secondCanonical);
end

function value = exactInteger(value, label)
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
        ~isfinite(value) || value ~= fix(value) || abs(double(value)) > flintmax
    error('bistatic:CpOfdmInteger', ...
        '%s must be one exactly represented finite integer.', label);
end
value = double(value);
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

function value = textScalar(value, label)
if isstring(value)
    if ~isscalar(value) || ismissing(value)
        error('bistatic:CpOfdmText', ...
            '%s must be a nonmissing text scalar.', label);
    end
    value = char(value);
elseif ~ischar(value) || ~isrow(value)
    error('bistatic:CpOfdmText', ...
        '%s must be a character row or string scalar.', label);
end
end

function requireScalarStruct(value, label)
if ~isstruct(value) || ~isscalar(value)
    error('bistatic:CpOfdmType', '%s must be a scalar struct.', label);
end
end

function requireFields(value, names, label)
for index = 1:numel(names)
    if ~isfield(value, names{index})
        error('bistatic:CpOfdmMissingField', ...
            '%s is missing required field %s.', label, names{index});
    end
end
end
