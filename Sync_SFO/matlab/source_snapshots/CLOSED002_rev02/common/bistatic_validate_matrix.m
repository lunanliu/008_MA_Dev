function summary = bistatic_validate_matrix(matrix, cfg)
%BISTATIC_VALIDATE_MATRIX Validate pairwise/corner/channel/seed coverage.

if matrix.schema_version ~= 2
    error('bistatic:MatrixSchema', 'Unsupported verification-matrix schema.');
end
rows = double(matrix.offset_pairwise_rows);
if ~isequal(size(rows), [9 3])
    error('bistatic:PairwiseCoverage', 'The L9 offset array must contain 9 by 3 entries.');
end
levels = {double(matrix.offset_levels.to_sync_samples(:)).', ...
    double(matrix.offset_levels.fo_sync_hz(:)).', ...
    double(matrix.offset_levels.sfo_ppm(:)).'};
for a = 1:2
    for b = a + 1:3
        observed = unique(rows(:, [a b]), 'rows');
        expected = zeros(9, 2);
        index = 1;
        for x = levels{a}
            for y = levels{b}
                expected(index, :) = [x y];
                index = index + 1;
            end
        end
        if ~isequal(sortrows(observed), sortrows(expected))
            error('bistatic:PairwiseCoverage', 'Factors %d/%d do not cover all level pairs.', a, b);
        end
    end
end

corners = double(matrix.all_nonzero_sign_corners);
expectedSigns = unique(sign(corners), 'rows');
if ~isequal(size(corners), [8 3]) || size(expectedSigns, 1) ~= 8 || any(corners(:) == 0)
    error('bistatic:CornerCoverage', 'All eight nonzero sign corners are required.');
end

paperSeeds = double(matrix.paper_offset_snr_project_grid_fixture.seeds(:));
losSeeds = double(matrix.nominal_los_snr_sweep.seeds_per_point(:));
if numel(unique(paperSeeds)) < 10 || numel(unique(losSeeds)) < 10
    error('bistatic:SeedCoverage', 'Every final statistical point requires at least ten saved seeds.');
end

coarseGate = matrix.nominal_los_snr_sweep.coarse_cfo_acceptance;
if string(matrix.nominal_los_snr_sweep.acceptance_role) ~= ...
        "task_specific_by_snr_and_metric" || ...
        string(coarseGate.deterministic_metric) ~= ...
        "per_case_absolute_error_hz" || ...
        double(coarseGate.deterministic_max_abs_error_hz) ~= 1000 || ...
        string(coarseGate.accuracy_metric) ~= ...
        "rmse_per_snr_point_hz" || ...
        double(coarseGate.accuracy_max_rmse_hz) ~= 1000 || ...
        ~logical(coarseGate.paper_reference_fixture_accuracy_required) || ...
        string(coarseGate.paper_reference_fixture_accuracy_metric) ~= ...
        "rmse_per_channel_snr_point_hz" || ...
        double(coarseGate.paper_reference_fixture_accuracy_max_rmse_hz) ~= 1000 || ...
        logical(coarseGate.characterization_accuracy_gate)
    error('bistatic:CoarseCfoAcceptance', ...
        'The user-approved T04 statistical acceptance policy is inconsistent.');
end
accuracySnr = sort(double(coarseGate.accuracy_snr_db(:))).';
characterizationSnr = sort(double(coarseGate.characterization_snr_db(:))).';
if ~isequal(accuracySnr, [5 10 20]) || ...
        ~isequal(characterizationSnr, [-5 0]) || ...
        double(coarseGate.seeds_per_snr_point) ~= 10 || ...
        ~logical(coarseGate.require_finite_valid_result_all_deterministic_and_nominal) || ...
        ~logical(coarseGate.require_zero_ambiguity_all_deterministic_and_nominal)
    error('bistatic:CoarseCfoAcceptance', ...
        'The T04 SNR roles, seed count, valid, or ambiguity policy changed.');
end
nominalSnr = sort(double(matrix.nominal_los_snr_sweep.snr_db(:))).';
if ~isequal(sort([accuracySnr characterizationSnr]), nominalSnr)
    error('bistatic:CoarseCfoAcceptance', ...
        'Every frozen nominal SNR point needs exactly one T04 role.');
end
if double(matrix.paper_offset_snr_project_grid_fixture.paper_exact.snr_los_db) ~= 15 || ...
        numel(unique(paperSeeds)) ~= 10
    error('bistatic:CoarseCfoAcceptance', ...
        'The 15 dB paper-reference accuracy group must retain ten seeds.');
end
profiles = matrix.standardized_profiles;
profileNames = string({profiles.profile});
required = ["tdl_d_los_30ns", "tdl_a_nlos_100ns", "tdl_a_beyond_cp_300ns"];
if ~all(ismember(required, profileNames))
    error('bistatic:ChannelCoverage', 'Required standardized acceptance/stress profiles are missing.');
end
for k = 1:numel(profiles)
    if profiles(k).role ~= "beyond_cp_degradation_only" && numel(unique(profiles(k).seeds)) < 10
        error('bistatic:SeedCoverage', 'Nominal/in-CP profile %s needs ten seeds.', profiles(k).profile);
    end
end

truthCases = matrix.truth_decomposition_cases;
for k = 1:numel(truthCases)
    if truthCases(k).to_clock_samples + truthCases(k).los_delay_samples ~= ...
            truthCases(k).to_sync_true_samples
        error('bistatic:TruthDefinition', 'TO truth decomposition is inconsistent in %s.', truthCases(k).case_id);
    end
    if truthCases(k).cfo_oscillator_hz + truthCases(k).los_doppler_hz ~= ...
            truthCases(k).fo_sync_true_hz
        error('bistatic:TruthDefinition', 'FO truth decomposition is inconsistent in %s.', truthCases(k).case_id);
    end
end

if max(abs(rows(:, 1))) > cfg.offset_limits.to_sync_samples || ...
        max(abs(rows(:, 2))) > cfg.offset_limits.fo_sync_hz || ...
        max(abs(rows(:, 3))) > cfg.offset_limits.sfo_ppm
    error('bistatic:NominalRange', 'Nominal offset coverage exceeds the frozen estimator range.');
end

summary.pairwise_rows = size(rows, 1);
summary.pair_combinations_per_factor_pair = 9;
summary.nonzero_sign_corners = size(corners, 1);
summary.paper_seeds = numel(unique(paperSeeds));
summary.los_seeds_per_snr_point = numel(unique(losSeeds));
summary.los_snr_points = numel(matrix.nominal_los_snr_sweep.snr_db);
summary.coarse_cfo_deterministic_max_abs_error_hz = ...
    double(coarseGate.deterministic_max_abs_error_hz);
summary.coarse_cfo_accuracy_snr_db = accuracySnr;
summary.coarse_cfo_characterization_snr_db = characterizationSnr;
summary.coarse_cfo_accuracy_max_rmse_hz = ...
    double(coarseGate.accuracy_max_rmse_hz);
summary.coarse_cfo_paper_reference_snr_db = ...
    double(matrix.paper_offset_snr_project_grid_fixture.paper_exact.snr_los_db);
summary.coarse_cfo_paper_reference_accuracy_max_rmse_hz = ...
    double(coarseGate.paper_reference_fixture_accuracy_max_rmse_hz);
summary.standardized_profile_count = numel(profiles);
summary.pass = true;
end
