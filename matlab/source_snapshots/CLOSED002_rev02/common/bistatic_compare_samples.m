function metrics = bistatic_compare_samples(reference, candidate, maxLatency, lsbSize)
%BISTATIC_COMPARE_SAMPLES Align latency then report common sample metrics.

reference = reference(:);
candidate = candidate(:);
if isempty(reference) || isempty(candidate) || maxLatency < 0 || lsbSize <= 0
    error('bistatic:CompareInput', 'Comparison inputs, latency, or LSB size are invalid.');
end

bestScore = -Inf;
bestLag = 0;
bestReference = [];
bestCandidate = [];
for lag = -floor(maxLatency):floor(maxLatency)
    if lag >= 0
        count = min(numel(reference), numel(candidate) - lag);
        refIndices = 1:count;
        candidateIndices = lag + (1:count);
    else
        count = min(numel(reference) + lag, numel(candidate));
        candidateIndices = 1:count;
        refIndices = -lag + (1:count);
    end
    if count < 1
        continue;
    end
    r = reference(refIndices);
    c = candidate(candidateIndices);
    denominator = norm(r) * norm(c);
    score = 0;
    if denominator > 0
        score = abs(r' * c) / denominator;
    elseif isequal(r, c)
        score = 1;
    end
    if score > bestScore
        bestScore = score;
        bestLag = lag;
        bestReference = r;
        bestCandidate = c;
    end
end

errorValues = bestCandidate - bestReference;
componentLsb = max(abs(real(errorValues)), abs(imag(errorValues))) / lsbSize;
mismatch = find(componentLsb > 1 + 1e-12, 1, 'first');
if isempty(mismatch)
    mismatch = 0;
end
signalNorm = norm(bestReference);
if signalNorm == 0
    evmDb = ternary(norm(errorValues) == 0, -Inf, Inf);
else
    evmDb = 20 * log10(norm(errorValues) / signalNorm);
end

metrics.latency_samples = bestLag;
metrics.aligned_sample_count = numel(errorValues);
metrics.correlation_score = bestScore;
metrics.max_lsb_error = max(componentLsb);
metrics.samples_over_1lsb = nnz(componentLsb > 1 + 1e-12);
metrics.first_mismatch_aligned_index = mismatch;
metrics.evm_db = evmDb;
metrics.error_statistics = bistatic_error_statistics(errorValues);
end

function output = ternary(condition, trueValue, falseValue)
if condition
    output = trueValue;
else
    output = falseValue;
end
end
