function summary = bistatic_queue_summary(enqueuesPerCycle, dequeuesPerCycle, capacity)
%BISTATIC_QUEUE_SUMMARY Summarize observed cycle-by-cycle queue behavior.

enqueues = double(enqueuesPerCycle(:));
dequeues = double(dequeuesPerCycle(:));
if numel(enqueues) ~= numel(dequeues) || any(enqueues < 0) || any(dequeues < 0) || ...
        any(enqueues ~= floor(enqueues)) || any(dequeues ~= floor(dequeues)) || capacity < 0
    error('bistatic:QueueTrace', 'Queue traces/capacity are invalid.');
end
occupancy = cumsum(enqueues - dequeues);
summary.cycles = numel(enqueues);
summary.total_enqueues = sum(enqueues);
summary.total_dequeues = sum(dequeues);
summary.max_occupancy = max([0; occupancy]);
summary.min_occupancy = min([0; occupancy]);
summary.final_occupancy = ternary(isempty(occupancy), 0, occupancy(end));
summary.underflow_observed = summary.min_occupancy < 0;
summary.overflow_observed = summary.max_occupancy > capacity;
summary.capacity = capacity;
if numel(occupancy) >= 2
    fit = polyfit((1:numel(occupancy)).', occupancy, 1);
    summary.observed_growth_per_cycle = fit(1);
else
    summary.observed_growth_per_cycle = 0;
end
summary.bounded_in_observation = ~summary.underflow_observed && ~summary.overflow_observed;
end

function output = ternary(condition, trueValue, falseValue)
if condition
    output = trueValue;
else
    output = falseValue;
end
end
