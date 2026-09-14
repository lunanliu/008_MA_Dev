function [frameSamples, frequencySymbols] = bistatic_generate_frame( ...
        cfg, frameId, baseSeed, artifacts)
%BISTATIC_GENERATE_FRAME Generate one deterministic 522-symbol OFDM frame.
% The optional second output exposes the exact unshifted frequency symbols
% already used by the IFFT; existing single-output callers are unchanged.

nfft = cfg.frame.fft_length;
ncp = cfg.frame.cyclic_prefix_samples;
nPayload = cfg.frame.payload_symbols;
active = bistatic_active_indices(cfg);
nActive = numel(active);

if ~isequal(size(artifacts.preamble_fd), [nfft, cfg.frame.preamble_symbols])
    error('bistatic:ArtifactShape', 'Preamble artifact shape is invalid.');
end
if ~isequal(size(artifacts.pilot_mask_active_by_payload), [nActive, nPayload]) || ...
        ~isequal(size(artifacts.pilot_values_active_by_payload), [nActive, nPayload])
    error('bistatic:ArtifactShape', 'Pilot artifact shape is invalid.');
end

frameSeed = mod(double(baseSeed) + double(frameId + 32768) * 65537, 2147483646) + 1;
rs = RandStream(cfg.rng.algorithm, 'Seed', frameSeed);
payloadActive = reshape(bistatic_gray_qpsk(...
    randi(rs, [0 1], 2 * nActive * nPayload, 1)), nActive, nPayload);
mask = artifacts.pilot_mask_active_by_payload;
pilotValues = artifacts.pilot_values_active_by_payload;
payloadActive(mask) = pilotValues(mask);

payloadFd = complex(zeros(nfft, nPayload));
payloadFd(active, :) = payloadActive;
frequencySymbols = [artifacts.preamble_fd, payloadFd];
timeSymbols = ifft(frequencySymbols, nfft, 1);
withCp = [timeSymbols(end - ncp + 1:end, :); timeSymbols];
frameSamples = withCp(:);
end
