function result = t05_local_fine_sync_floating(samples, globalFirstSample, ...
    coarseStartSample, coarseCfoHz, ps1Useful, cfg, options)
%T05_LOCAL_FINE_SYNC_FLOATING Bounded full-PS1 fine-timing reference.
%
% Candidate values are frame-start sample indices.  The matched-filter
% observation begins one cyclic prefix after each candidate, so the selected
% useful-symbol index is converted back to TO_sync_true frame-start semantics.

arguments
    samples (:,1) double
    globalFirstSample (1,1) double {mustBeInteger}
    coarseStartSample (1,1) double {mustBeInteger}
    coarseCfoHz (1,1) double {mustBeFinite}
    ps1Useful (:,1) double
    cfg (1,1) struct
    options.SearchRadiusSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 128
    options.QualityThreshold (1,1) double {mustBeNonnegative} = 0
    options.EqualPeakRelativeTolerance (1,1) double {mustBeNonnegative} = 2^-42
    options.SidelobeGuardSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 8
    options.AmbiguityRunnerMultiplier (1,1) double {mustBePositive} = 4
end

nfft = double(cfg.frame.fft_length);
ncp = double(cfg.frame.cyclic_prefix_samples);
fs = double(cfg.signal.sample_rate_hz);
radius = options.SearchRadiusSamples;
if numel(ps1Useful) ~= nfft
    error('bistatic:T05ReferenceLength', ...
        'PS1 useful reference must contain exactly %d samples.', nfft);
end
if any(~isfinite(real(samples)) | ~isfinite(imag(samples))) || ...
        any(~isfinite(real(ps1Useful)) | ~isfinite(imag(ps1Useful)))
    error('bistatic:T05NonFiniteInput', ...
        'Fine-timing inputs must be finite complex values.');
end

candidates = (coarseStartSample-radius:coarseStartSample+radius).';
firstUseful = candidates(1) + ncp;
lastUseful = candidates(end) + ncp + nfft - 1;
firstIndex = firstUseful - globalFirstSample + 1;
lastIndex = lastUseful - globalFirstSample + 1;
if firstIndex < 1 || lastIndex > numel(samples)
    error('bistatic:T05LocalWindowBounds', ...
        ['Input [%d,%d] does not cover required local useful range ' ...
         '[%d,%d].'], globalFirstSample, ...
        globalFirstSample + numel(samples) - 1, firstUseful, lastUseful);
end

local = samples(firstIndex:lastIndex);
relativeSample = (0:numel(local)-1).';
rotation = exp(-1j * 2*pi*coarseCfoHz/fs .* relativeSample);
corrected = local .* rotation;

% conv(x,flip(conj(r)),'valid') is the ordered sliding dot product
% sum(x(d:d+N-1).*conj(r)).
correlation = conv(corrected, flip(conj(ps1Useful)), 'valid');
if numel(correlation) ~= 2*radius + 1
    error('bistatic:T05CorrelationCount', ...
        'Expected %d candidates, received %d.', ...
        2*radius + 1, numel(correlation));
end
magnitudeSquared = abs(correlation).^2;
segmentEnergy = conv(abs(corrected).^2, ones(nfft,1), 'valid');
referenceEnergy = sum(abs(ps1Useful).^2);

[peakMagnitudeSquared, firstPeakIndex] = max(magnitudeSquared);
denominator = referenceEnergy * segmentEnergy(firstPeakIndex);
if denominator > 0 && isfinite(denominator) && ...
        peakMagnitudeSquared > 0 && isfinite(peakMagnitudeSquared)
    quality = min(peakMagnitudeSquared / denominator, 1);
else
    quality = 0;
end

tieTolerance = max(peakMagnitudeSquared * ...
    options.EqualPeakRelativeTolerance, realmin('double'));
peakIndices = find(abs(magnitudeSquared-peakMagnitudeSquared) <= tieTolerance);
selectedIndex = peakIndices(1); % Frozen earliest-index tie break.
exactTie = numel(peakIndices) > 1;

outsideGuard = abs(candidates-candidates(selectedIndex)) > ...
    options.SidelobeGuardSamples;
if any(outsideGuard)
    sidelobeMagnitudeSquared = max(magnitudeSquared(outsideGuard));
else
    sidelobeMagnitudeSquared = 0;
end
nearEqualRunner = peakMagnitudeSquared > 0 && ...
    options.AmbiguityRunnerMultiplier*sidelobeMagnitudeSquared >= ...
    peakMagnitudeSquared;
ambiguity = exactTie || nearEqualRunner;
if sidelobeMagnitudeSquared > 0
    pslrDb = 10*log10(peakMagnitudeSquared/sidelobeMagnitudeSquared);
else
    pslrDb = Inf;
end

valid = quality >= options.QualityThreshold && quality > 0 && ~ambiguity;
if peakMagnitudeSquared <= 0 || denominator <= 0
    errorCode = uint16(1); % no usable signal/energy
elseif ambiguity
    errorCode = uint16(2); % equal-peak ambiguity
elseif quality < options.QualityThreshold
    errorCode = uint16(3); % insufficient normalized correlation quality
else
    errorCode = uint16(0);
end

result.valid = valid;
result.ambiguity = ambiguity;
result.error_code = errorCode;
result.frame_start_sample = int32(candidates(selectedIndex));
result.useful_start_sample = int32(candidates(selectedIndex)+ncp);
result.peak_magnitude_squared = peakMagnitudeSquared;
result.quality = quality;
result.pslr_db = pslrDb;
result.runner_up_magnitude_squared = sidelobeMagnitudeSquared;
result.runner_to_peak_power_ratio = sidelobeMagnitudeSquared / ...
    max(peakMagnitudeSquared,realmin('double'));
result.exact_tie = exactTie;
result.near_equal_runner = nearEqualRunner;
result.candidate_frame_start = candidates;
result.correlation = correlation;
result.magnitude_squared = magnitudeSquared;
result.segment_energy = segmentEnergy;
result.reference_energy = referenceEnergy;
result.corrected_local_samples = corrected;
result.required_first_sample = firstUseful;
result.required_last_sample = lastUseful;
result.tie_count = numel(peakIndices);
result.selected_candidate_index_one_based = selectedIndex;
end
