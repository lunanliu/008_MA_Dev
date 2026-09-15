function artifacts = bistatic_fixture_artifacts(cfg)
%BISTATIC_FIXTURE_ARTIFACTS Create structural T01-only preamble/pilot fixtures.
% These values verify the common generator API. T02 must replace them before
% production use; the generator rejects them unless explicitly opted in.

rs = RandStream(cfg.rng.algorithm, 'Seed', cfg.rng.t01_fixture_artifact_seed);
nfft = cfg.frame.fft_length;
nPreamble = cfg.frame.preamble_symbols;
nPayload = cfg.frame.payload_symbols;
active = bistatic_active_indices(cfg);
nActive = numel(active);

preambleFd = complex(zeros(nfft, nPreamble));
ps1Bins = active(mod(active - 1, 2) == 0);
preambleFd(ps1Bins, 1) = bistatic_gray_qpsk(randi(rs, [0 1], 2 * numel(ps1Bins), 1));
preambleFd(:, 2) = preambleFd(:, 1);
for pairStart = 3:2:9
    values = bistatic_gray_qpsk(randi(rs, [0 1], 2 * nActive, 1));
    preambleFd(active, pairStart) = values;
    preambleFd(active, pairStart + 1) = values;
end

pilotMask = false(nActive, nPayload);
pilotMask(1:cfg.payload.pilot_frequency_spacing:end, ...
    1:cfg.payload.pilot_time_spacing:end) = true;
pilotValues = complex(zeros(nActive, nPayload));
pilotValues(pilotMask) = bistatic_gray_qpsk(...
    randi(rs, [0 1], 2 * nnz(pilotMask), 1));

artifacts.artifact_class = 't01_test_fixture';
artifacts.production_allowed = false;
artifacts.resolved_by = 'T02';
artifacts.description = ['Structural-only fixture; PN polynomial, seed, PS2 definition, ' ...
    'pilot phase/offset, and observation maps are not production decisions.'];
artifacts.preamble_fd = preambleFd;
artifacts.pilot_mask_active_by_payload = pilotMask;
artifacts.pilot_values_active_by_payload = pilotValues;
end
