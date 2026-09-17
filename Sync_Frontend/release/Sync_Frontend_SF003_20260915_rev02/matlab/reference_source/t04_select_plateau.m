function estimate = t04_select_plateau(metricResult, sampleRateHz, options)
%T04_SELECT_PLATEAU Select earliest qualified S&C plateau on the 4-lane grid.

required = {'expected_start_sample', 'search_pre_samples', ...
    'search_post_samples', 'lane_grid_origin', 'metric_threshold', ...
    'minimum_run_beats', 'energy_floor', 'cyclic_prefix_samples', ...
    'start_policy'};
for index = 1:numel(required)
    if ~isfield(options, required{index})
        error('bistatic:T04SelectionOption', ...
            'Missing selection option %s.', required{index});
    end
end

startIndex = metricResult.start_sample_index;
inSearch = startIndex >= options.expected_start_sample - ...
    options.search_pre_samples & ...
    startIndex <= options.expected_start_sample + ...
    options.search_post_samples;
onLaneGrid = mod(startIndex - options.lane_grid_origin, 4) == 0;
selected = find(inSearch & onLaneGrid);
estimate.valid = false;
estimate.error_code = uint16(1);
estimate.coarse_start_sample = int64(0);
estimate.cfo_hz = 0;
estimate.quality = 0;
estimate.plateau_beats = 0;
estimate.phase_sample_index = int64(0);
estimate.ambiguity = false;
estimate.denominator_zero = false;
if isempty(selected)
    estimate.error_code = uint16(2);
    return;
end

metric = metricResult.metric(selected);
energy = metricResult.energy(selected);
qualified = metric >= options.metric_threshold & ...
    energy > options.energy_floor & isfinite(metric);
edges = diff([false; qualified; false]);
runStarts = find(edges == 1);
runEnds = find(edges == -1) - 1;
runLengths = runEnds - runStarts + 1;
eligible = find(runLengths >= options.minimum_run_beats);
if isempty(eligible)
    estimate.error_code = uint16(3);
    estimate.denominator_zero = all(energy <= options.energy_floor);
    return;
end

chosenRun = eligible(1);
localRange = runStarts(chosenRun):runEnds(chosenRun);
metricIndices = selected(localRange);

[~, strongestLocal] = max(metric(localRange));
strongestIndex = metricIndices(strongestLocal);
leadingEdge = double(startIndex(metricIndices(1)));
trailingEdge = double(startIndex(metricIndices(end)));
switch char(options.start_policy)
    case 'leading_edge'
        selectedStart = leadingEdge;
    case 'trailing_edge_minus_cp'
        selectedStart = trailingEdge - options.cyclic_prefix_samples;
    case 'midpoint_minus_half_cp'
        midpointStart = (leadingEdge + trailingEdge) / 2 - ...
            options.cyclic_prefix_samples / 2;
        selectedStart = options.lane_grid_origin + 4 * round( ...
            (midpointStart - options.lane_grid_origin) / 4);
    otherwise
        error('bistatic:T04StartPolicy', 'Unknown start policy %s.', ...
            options.start_policy);
end
if ~isfield(options, 'phase_policy')
    options.phase_policy = 'run_sum';
end
switch char(options.phase_policy)
    case 'run_sum'
        phaseIndices = metricIndices;
    case 'trimmed_run_sum'
        trim = floor(numel(metricIndices) / 4);
        phaseIndices = metricIndices(1+trim:end-trim);
        if isempty(phaseIndices)
            phaseIndices = metricIndices;
        end
    case 'strongest_metric'
        phaseIndices = strongestIndex;
    case 'strongest_correlation'
        [~, strongestCorrelationLocal] = max(abs( ...
            metricResult.correlation(metricIndices)));
        phaseIndices = metricIndices(strongestCorrelationLocal);
    case 'global_strongest_metric'
        [~, globalStrongestLocal] = max(metric);
        phaseIndices = selected(globalStrongestLocal);
        strongestIndex = phaseIndices;
    case 'global_strongest_correlation'
        qualifiedSelected = selected(qualified);
        [~, globalCorrelationLocal] = max(abs( ...
            metricResult.correlation(qualifiedSelected)));
        phaseIndices = qualifiedSelected(globalCorrelationLocal);
        strongestIndex = phaseIndices;
    case 'safe_interior_sum'
        if ~isfield(options, 'safe_phase_first_offset') || ...
                ~isfield(options, 'safe_phase_last_offset')
            error('bistatic:T04SafePhaseOption', ...
                'Safe interior phase offsets must be provided.');
        end
        safeStart = selectedStart + options.safe_phase_first_offset;
        safeEnd = selectedStart + options.safe_phase_last_offset;
        phaseIndices = selected(startIndex(selected) >= safeStart & ...
            startIndex(selected) <= safeEnd);
        if isempty(phaseIndices)
            estimate.error_code = uint16(5);
            return;
        end
        strongestIndex = phaseIndices(ceil(numel(phaseIndices) / 2));
    otherwise
        error('bistatic:T04PhasePolicy', 'Unknown phase policy %s.', ...
            options.phase_policy);
end
aggregateCorrelation = sum(metricResult.correlation(phaseIndices));
aggregateEnergy = sum(metricResult.energy(phaseIndices));
if aggregateEnergy <= options.energy_floor || aggregateCorrelation == 0
    estimate.error_code = uint16(4);
    estimate.denominator_zero = true;
    return;
end
phaseRadians = angle(aggregateCorrelation);
estimate.valid = true;
estimate.error_code = uint16(0);
estimate.coarse_start_sample = int64(selectedStart);
estimate.cfo_hz = phaseRadians * sampleRateHz / ...
    (2 * pi * metricResult.half_length);
estimate.quality = min(abs(aggregateCorrelation) / aggregateEnergy, 1);
estimate.plateau_beats = numel(localRange);
estimate.phase_sample_index = int64(startIndex(strongestIndex));
estimate.ambiguity = numel(eligible) > 1;
estimate.phase_radians = phaseRadians;
estimate.phase_policy = char(options.phase_policy);
estimate.start_policy = char(options.start_policy);
estimate.leading_edge_sample = int64(leadingEdge);
estimate.trailing_edge_sample = int64(trailingEdge);
end
