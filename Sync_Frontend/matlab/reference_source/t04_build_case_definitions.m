function cases = t04_build_case_definitions(matrix)
%T04_BUILD_CASE_DEFINITIONS Rebuild the 91 frozen T04 study cases.

cases = repmat(emptyCase(), 0, 1);
pairwise = matrix.offset_pairwise_rows;
for index = 1:size(pairwise, 1)
    definition = emptyCase();
    definition.id = sprintf('pairwise_%02d', index);
    definition.role = 'deterministic';
    definition.to_clock = pairwise(index, 1);
    definition.cfo_oscillator = pairwise(index, 2);
    definition.sfo = pairwise(index, 3);
    definition.noise_seed = 50000 + index;
    definition.channel_seed = 50000 + index;
    cases(end+1) = withDerivedTruth(definition); %#ok<AGROW>
end

signCorners = matrix.all_nonzero_sign_corners;
for index = 1:size(signCorners, 1)
    definition = emptyCase();
    definition.id = sprintf('sign_corner_%02d', index);
    definition.role = 'deterministic';
    definition.to_clock = signCorners(index, 1);
    definition.cfo_oscillator = signCorners(index, 2);
    definition.sfo = signCorners(index, 3);
    definition.noise_seed = 50050 + index;
    definition.channel_seed = 50050 + index;
    cases(end+1) = withDerivedTruth(definition); %#ok<AGROW>
end

for laneResidue = 0:3
    definition = emptyCase();
    definition.id = sprintf('lane_boundary_mod4_%d', laneResidue);
    definition.role = 'deterministic';
    definition.to_clock = laneResidue;
    definition.cfo_oscillator = (laneResidue - 1.5) * 50000;
    definition.noise_seed = 50080 + laneResidue;
    definition.channel_seed = 50080 + laneResidue;
    cases(end+1) = withDerivedTruth(definition); %#ok<AGROW>
end

truthCases = matrix.truth_decomposition_cases;
for index = 1:numel(truthCases)
    source = truthCases(index);
    definition = emptyCase();
    definition.id = char(source.case_id);
    definition.role = 'deterministic';
    definition.to_clock = source.to_clock_samples;
    definition.propagation_delay = source.los_delay_samples;
    definition.cfo_oscillator = source.cfo_oscillator_hz;
    definition.los_doppler = source.los_doppler_hz;
    definition.expected_to = source.to_sync_true_samples;
    definition.expected_fo = source.fo_sync_true_hz;
    definition.noise_seed = 50100 + index;
    definition.channel_seed = 50100 + index;
    cases(end+1) = definition; %#ok<AGROW>
end

nominal = matrix.nominal_los_snr_sweep;
for snrIndex = 1:numel(nominal.snr_db)
    for seedIndex = 1:numel(nominal.seeds_per_point)
        definition = emptyCase();
        definition.id = sprintf('tdld_%+03ddB_seed_%d', ...
            nominal.snr_db(snrIndex), nominal.seeds_per_point(seedIndex));
        definition.role = 'nominal';
        definition.channel = char(nominal.profile);
        definition.snr = nominal.snr_db(snrIndex);
        definition.to_clock = nominal.to_sync_samples;
        definition.cfo_oscillator = nominal.fo_sync_hz;
        definition.sfo = nominal.sfo_ppm;
        definition.noise_seed = nominal.seeds_per_point(seedIndex);
        definition.channel_seed = nominal.seeds_per_point(seedIndex);
        cases(end+1) = withDerivedTruth(definition); %#ok<AGROW>
    end
end

paper = matrix.paper_offset_snr_project_grid_fixture;
for seedIndex = 1:numel(paper.seeds)
    definition = emptyCase();
    definition.id = sprintf('paper_fixture_seed_%d', paper.seeds(seedIndex));
    definition.role = 'nominal';
    definition.channel = 'paper_offset_snr_project_grid_fixture';
    definition.snr = paper.paper_exact.snr_los_db;
    definition.to_clock = paper.paper_exact.to_sync_samples;
    definition.cfo_oscillator = paper.paper_exact.fo_sync_hz;
    definition.sfo = paper.paper_exact.sfo_ppm;
    definition.noise_seed = paper.seeds(seedIndex);
    definition.channel_seed = paper.seeds(seedIndex);
    cases(end+1) = withDerivedTruth(definition); %#ok<AGROW>
end

frameOffsets = [-101 2 101];
frameFrequencies = [-150000 0 150000];
frameSfo = [150 -150 0];
for frameIndex = 1:3
    definition = emptyCase();
    definition.id = sprintf('continuous_frame_%d', frameIndex);
    definition.role = 'deterministic';
    definition.frame_id = frameIndex;
    definition.to_clock = frameOffsets(frameIndex);
    definition.cfo_oscillator = frameFrequencies(frameIndex);
    definition.sfo = frameSfo(frameIndex);
    definition.noise_seed = 50800 + frameIndex;
    definition.channel_seed = 50800 + frameIndex;
    cases(end+1) = withDerivedTruth(definition); %#ok<AGROW>
end

for signValue = [-1 1]
    definition = emptyCase();
    definition.id = sprintf('near_unambiguous_%+d', signValue);
    definition.role = 'stress';
    definition.cfo_oscillator = signValue * 240000;
    definition.noise_seed = 50900 + signValue;
    definition.channel_seed = 50900 + signValue;
    cases(end+1) = withDerivedTruth(definition); %#ok<AGROW>
end

outOfRange = matrix.explicit_out_of_range_stress;
definition = emptyCase();
definition.id = 'explicit_out_of_range';
definition.role = 'stress';
definition.to_clock = outOfRange.to_sync_samples;
definition.cfo_oscillator = outOfRange.fo_sync_hz;
definition.sfo = outOfRange.sfo_ppm;
definition.noise_seed = outOfRange.seeds(1);
definition.channel_seed = outOfRange.seeds(1);
cases(end+1) = withDerivedTruth(definition);

if numel(cases) ~= 91
    error('bistatic:T04BitTrueCaseCount', ...
        'Expected 91 T04 cases, rebuilt %d.', numel(cases));
end
roles = string({cases.role});
if nnz(roles == "deterministic") ~= 28 || ...
        nnz(roles == "nominal") ~= 60 || nnz(roles == "stress") ~= 3
    error('bistatic:T04BitTrueCaseRoles', ...
        'Expected deterministic/nominal/stress counts 28/60/3.');
end
end

function definition = emptyCase()
definition.id = '';
definition.role = '';
definition.channel = 'single_path';
definition.snr = Inf;
definition.to_clock = 0;
definition.propagation_delay = 0;
definition.cfo_oscillator = 0;
definition.los_doppler = 0;
definition.sfo = 0;
definition.noise_seed = 1;
definition.channel_seed = 1;
definition.frame_id = 0;
definition.expected_to = NaN;
definition.expected_fo = NaN;
end

function definition = withDerivedTruth(definition)
definition.expected_to = definition.to_clock + ...
    definition.propagation_delay;
definition.expected_fo = definition.cfo_oscillator + ...
    definition.los_doppler;
end
