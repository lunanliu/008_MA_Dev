function result = t04_sc_metric_rolling(samples, halfLength, ...
    globalFirstSample, sampleRateHz)
%T04_SC_METRIC_ROLLING Floating S&C rolling correlation and energy.

samples = samples(:);
if nargin < 3
    globalFirstSample = 0;
end
if nargin < 4
    error('bistatic:T04SampleRate', ...
        'sampleRateHz must be provided; the helper has no implicit rate.');
end
if halfLength < 1 || halfLength ~= floor(halfLength)
    error('bistatic:T04HalfLength', 'halfLength must be a positive integer.');
end
count = numel(samples) - 2 * halfLength + 1;
if count < 1
    error('bistatic:T04InputLength', ...
        'Input must contain at least two repeated-half lengths.');
end

pairProducts = conj(samples(1:end-halfLength)) .* ...
    samples(halfLength+1:end);
secondEnergy = abs(samples(halfLength+1:end)).^2;
pairPrefix = [complex(0); cumsum(pairProducts)];
energyPrefix = [0; cumsum(secondEnergy)];
first = (1:count).';
lastPlusOne = first + halfLength;

result.correlation = pairPrefix(lastPlusOne) - pairPrefix(first);
result.energy = energyPrefix(lastPlusOne) - energyPrefix(first);
result.metric = abs(result.correlation).^2 ./ ...
    max(result.energy.^2, realmin('double'));
result.start_sample_index = globalFirstSample + (0:count-1).';
result.half_length = halfLength;
result.unambiguous_limit_hz = sampleRateHz / (2 * halfLength);
end
