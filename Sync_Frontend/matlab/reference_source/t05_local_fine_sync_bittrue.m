function result = t05_local_fine_sync_bittrue(inputI, inputQ, ...
    globalFirstSample, coarseStartSample, coarseCfoHz, refI, refQ, ...
    sampleRateHz, options)
%T05_LOCAL_FINE_SYNC_BITTRUE Mathematical fixed-point fine-timing oracle.
%
% This model deliberately stops at a mathematical fixed-point boundary. It
% models the provisional DDS phase/coefficient quantization, complex
% rotation, 16-way correlation reduction, exact integer peak selection, and
% the Q1.15 quality decision. It is not a vendor DDS bit-accurate model.

arguments
    inputI (:,1) int16
    inputQ (:,1) int16
    globalFirstSample (1,1) double {mustBeInteger}
    coarseStartSample (1,1) double {mustBeInteger}
    coarseCfoHz (1,1) double {mustBeFinite}
    refI (:,1) int16
    refQ (:,1) int16
    sampleRateHz (1,1) double {mustBePositive,mustBeFinite}
    options.SearchRadiusSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 128
    options.CyclicPrefixSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 512
    options.PhaseWidthBits (1,1) double {mustBeInteger,mustBePositive} = 32
    options.CoefficientWidthBits (1,1) double {mustBeInteger,mustBePositive} = 18
    options.CorrectedWidthBits (1,1) double {mustBeInteger,mustBePositive} = 18
    options.CorrelationAccumulatorWidthBits (1,1) double {mustBeInteger,mustBePositive} = 48
    options.PartitionCount (1,1) double {mustBeInteger,mustBePositive} = 16
    options.SidelobeGuardSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 8
    options.QualityThresholdCodeQ1_15 (1,1) double {mustBeInteger,mustBeNonnegative} = 3162
end

if numel(inputI) ~= numel(inputQ)
    error('bistatic:T05BitTrueInputLength','I and Q input lengths differ.');
end
if numel(refI) ~= numel(refQ) || numel(refI) ~= 2048
    error('bistatic:T05BitTrueReferenceLength', ...
        'The fixed-point PS1 reference must contain 2048 complex taps.');
end
if options.PhaseWidthBits > 52
    error('bistatic:T05BitTruePhaseWidth', ...
        'The modulo-phase implementation supports at most 52 bits.');
end
if options.PartitionCount ~= 16
    error('bistatic:T05BitTruePartitionCount', ...
        'The frozen mathematical ordering uses exactly 16 partitions.');
end

radius = options.SearchRadiusSamples;
referenceLength = numel(refI);
candidates = (coarseStartSample-radius:coarseStartSample+radius).';
localFirstSample = candidates(1) + options.CyclicPrefixSamples;
localLastSample = candidates(end) + options.CyclicPrefixSamples + referenceLength - 1;
firstIndex = localFirstSample-globalFirstSample+1;
lastIndex = localLastSample-globalFirstSample+1;
if firstIndex < 1 || lastIndex > numel(inputI)
    error('bistatic:T05BitTrueLocalBounds', ...
        'Input range does not cover the required local candidate union.');
end

localI = inputI(firstIndex:lastIndex);
localQ = inputQ(firstIndex:lastIndex);
relativeSample = (0:numel(localI)-1).';
[phaseCode, phaseIncrement, cosineCode, sineCode] = localNcoCodes( ...
    relativeSample, coarseCfoHz, sampleRateHz, ...
    options.PhaseWidthBits, options.CoefficientWidthBits);
coefficientFractionBits = options.CoefficientWidthBits-1;
rotationRealProduct = int64(localI).*cosineCode + int64(localQ).*sineCode;
rotationImagProduct = int64(localQ).*cosineCode - int64(localI).*sineCode;
[correctedI, overflowI] = roundShiftSaturate(rotationRealProduct, ...
    coefficientFractionBits, options.CorrectedWidthBits);
[correctedQ, overflowQ] = roundShiftSaturate(rotationImagProduct, ...
    coefficientFractionBits, options.CorrectedWidthBits);

candidateCount = numel(candidates);
correlationReal = zeros(candidateCount,1,'int64');
correlationImag = zeros(candidateCount,1,'int64');
segmentEnergy = zeros(candidateCount,1,'int64');
for partition = 1:options.PartitionCount
    taps = partition:options.PartitionCount:referenceLength;
    sampleIndices = (0:candidateCount-1).' + taps;
    xI = int64(correctedI(sampleIndices));
    xQ = int64(correctedQ(sampleIndices));
    rI = reshape(int64(refI(taps)),1,[]);
    rQ = reshape(int64(refQ(taps)),1,[]);
    correlationReal = correlationReal + ...
        sum(xI.*rI + xQ.*rQ,2,'native');
    correlationImag = correlationImag + ...
        sum(xQ.*rI - xI.*rQ,2,'native');
    segmentEnergy = segmentEnergy + sum(xI.*xI + xQ.*xQ,2,'native');
end

accumulatorMinimum = -2^(options.CorrelationAccumulatorWidthBits-1);
accumulatorMaximum = 2^(options.CorrelationAccumulatorWidthBits-1)-1;
accumulatorOverflow = correlationReal < accumulatorMinimum | ...
    correlationReal > accumulatorMaximum | correlationImag < accumulatorMinimum | ...
    correlationImag > accumulatorMaximum;

referenceEnergy = sum(int64(refI).*int64(refI) + ...
    int64(refQ).*int64(refQ),'native');
magnitudeSquared = cell(candidateCount,1);
magnitudeSquaredDecimal = strings(candidateCount,1);
peakIndex = 1;
peakMagnitude = nonnegativeBigInteger(0);
tieCount = 0;
for candidateIndex = 1:candidateCount
    re = nonnegativeBigInteger(abs(correlationReal(candidateIndex)));
    im = nonnegativeBigInteger(abs(correlationImag(candidateIndex)));
    magnitude = re.multiply(re).add(im.multiply(im));
    magnitudeSquared{candidateIndex} = magnitude;
    magnitudeSquaredDecimal(candidateIndex) = string(char(magnitude.toString()));
    comparison = magnitude.compareTo(peakMagnitude);
    if comparison > 0
        peakMagnitude = magnitude;
        peakIndex = candidateIndex;
        tieCount = 1;
    elseif comparison == 0
        tieCount = tieCount + 1;
    end
end

outsideGuard = abs(candidates-candidates(peakIndex)) > options.SidelobeGuardSamples;
runnerMagnitude = nonnegativeBigInteger(0);
runnerIndex = 0;
for candidateIndex = 1:candidateCount
    if outsideGuard(candidateIndex) && ...
            magnitudeSquared{candidateIndex}.compareTo(runnerMagnitude) > 0
        runnerMagnitude = magnitudeSquared{candidateIndex};
        runnerIndex = candidateIndex;
    end
end
exactTie = tieCount > 1;
nearEqualRunner = peakMagnitude.signum() > 0 && ...
    runnerMagnitude.shiftLeft(2).compareTo(peakMagnitude) >= 0;
ambiguity = exactTie || nearEqualRunner;

denominator = nonnegativeBigInteger(referenceEnergy).multiply( ...
    nonnegativeBigInteger(segmentEnergy(peakIndex)));
if peakMagnitude.signum() > 0 && denominator.signum() > 0
    qualityBig = peakMagnitude.shiftLeft(15).divide(denominator);
    qualityCode = min(double(qualityBig.longValue()),32768);
else
    qualityCode = 0;
end
quality = qualityCode/2^15;
if peakMagnitude.signum() == 0 || denominator.signum() == 0
    errorCode = uint16(1);
elseif ambiguity
    errorCode = uint16(2);
elseif qualityCode < options.QualityThresholdCodeQ1_15
    errorCode = uint16(3);
elseif any(accumulatorOverflow)
    errorCode = uint16(4);
elseif any(overflowI | overflowQ)
    errorCode = uint16(5);
else
    errorCode = uint16(0);
end
valid = errorCode == 0;

peakDouble = double(correlationReal(peakIndex))^2 + double(correlationImag(peakIndex))^2;
if runnerIndex > 0
    runnerDouble = double(correlationReal(runnerIndex))^2 + ...
        double(correlationImag(runnerIndex))^2;
else
    runnerDouble = 0;
end
if runnerDouble > 0
    pslrDb = 10*log10(peakDouble/runnerDouble);
else
    pslrDb = Inf;
end

result.model = 'T05_MATHEMATICAL_BIT_TRUE_PROVISIONAL_VENDOR_CONFIG';
result.production_ip_verified = false;
result.valid = valid;
result.ambiguity = ambiguity;
result.error_code = errorCode;
result.frame_start_sample = int32(candidates(peakIndex));
result.useful_start_sample = int32(candidates(peakIndex)+options.CyclicPrefixSamples);
result.quality_code_q1_15 = uint16(qualityCode);
result.quality = quality;
result.pslr_db = pslrDb;
result.exact_tie = exactTie;
result.near_equal_runner = nearEqualRunner;
result.tie_count = tieCount;
result.peak_index_one_based = peakIndex;
result.runner_index_one_based = runnerIndex;
result.peak_magnitude_squared_decimal = string(char(peakMagnitude.toString()));
result.runner_magnitude_squared_decimal = string(char(runnerMagnitude.toString()));
result.reference_energy = referenceEnergy;
result.candidate_frame_start = candidates;
result.correlation_real = correlationReal;
result.correlation_imag = correlationImag;
result.magnitude_squared_decimal = magnitudeSquaredDecimal;
result.segment_energy = segmentEnergy;
result.local_first_sample = localFirstSample;
result.local_last_sample = localLastSample;
result.local_global_sample = (localFirstSample:localLastSample).';
result.local_input_i = localI;
result.local_input_q = localQ;
result.phase_increment_code = phaseIncrement;
result.phase_code = phaseCode;
result.nco_cosine_code = cosineCode;
result.nco_sine_code = sineCode;
result.corrected_i = correctedI;
result.corrected_q = correctedQ;
result.corrected_overflow = overflowI | overflowQ;
result.corrected_overflow_count = nnz(result.corrected_overflow);
result.accumulator_overflow = accumulatorOverflow;
result.accumulator_overflow_count = nnz(accumulatorOverflow);
result.config = options;
end

function [phaseCode, phaseIncrement, cosineCode, sineCode] = ...
        localNcoCodes(relativeSample, cfoHz, sampleRateHz, ...
        phaseWidthBits, coefficientWidthBits)
phaseScale = 2^phaseWidthBits;
phaseIncrement = int64(t02_round_even(cfoHz/sampleRateHz*phaseScale));
phaseDouble = mod(double(relativeSample).*double(phaseIncrement),phaseScale);
phaseCode = uint64(phaseDouble);
angle = 2*pi*phaseDouble/phaseScale;
coefficientScale = 2^(coefficientWidthBits-1);
rawCosine = t02_round_even(cos(angle)*coefficientScale);
rawSine = t02_round_even(sin(angle)*coefficientScale);
minimum = -coefficientScale;
maximum = coefficientScale-1;
cosineCode = int64(min(max(rawCosine,minimum),maximum));
sineCode = int64(min(max(rawSine,minimum),maximum));
end

function [output, overflow] = roundShiftSaturate(input, ...
        fractionBits, outputWidthBits)
scale = int64(2^fractionBits);
half = idivide(scale,int64(2),'floor');
negative = input < 0;
magnitude = abs(input);
quotient = idivide(magnitude,scale,'floor');
remainder = magnitude - quotient.*scale;
increment = remainder > half | ...
    (remainder == half & bitand(quotient,int64(1)) ~= 0);
roundedMagnitude = quotient + int64(increment);
rounded = roundedMagnitude;
rounded(negative) = -roundedMagnitude(negative);
minimum = int64(-2^(outputWidthBits-1));
maximum = int64(2^(outputWidthBits-1)-1);
overflow = rounded < minimum | rounded > maximum;
output = min(max(rounded,minimum),maximum);
end

function value = nonnegativeBigInteger(input)
if ~isa(input,'int64')
    input = int64(input);
end
if input < 0
    error('bistatic:T05BitTrueBigIntegerSign','Expected nonnegative integer.');
end
value = javaObject('java.math.BigInteger',char(string(input)));
end
