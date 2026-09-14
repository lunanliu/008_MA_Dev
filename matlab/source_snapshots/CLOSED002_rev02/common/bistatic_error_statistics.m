function statistics = bistatic_error_statistics(errorValues)
%BISTATIC_ERROR_STATISTICS Common estimator/sample error statistics.

values = errorValues(:);
if isempty(values) || any(~isfinite(real(values))) || any(~isfinite(imag(values)))
    error('bistatic:StatisticsInput', 'Statistics require finite, nonempty values.');
end
absolute = abs(values);
sortedAbsolute = sort(absolute);
index95 = max(1, ceil(0.95 * numel(sortedAbsolute)));
statistics.count = numel(values);
statistics.mean_error = mean(values);
statistics.absolute_value_of_mean_error = abs(statistics.mean_error);
statistics.mean_absolute_error = mean(absolute);
statistics.rmse = sqrt(mean(absolute.^2));
statistics.standard_deviation = std(values, 0);
statistics.percentile95_absolute_error = sortedAbsolute(index95);
end
