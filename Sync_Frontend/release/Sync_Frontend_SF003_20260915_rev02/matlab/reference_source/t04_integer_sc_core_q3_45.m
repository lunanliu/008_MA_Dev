function estimate = t04_integer_sc_core_q3_45(i16, q16, globalFirstSample, ...
    cfg, policy, includeWideTrace)
%T04_INTEGER_SC_CORE_Q3_45 Native Scaled_Radians Q3.45 integer model.

if nargin < 6
    includeWideTrace = false;
end
i16 = i16(:);
q16 = q16(:);
if ~isa(i16, 'int16') || ~isa(q16, 'int16') || ...
        ~isequal(size(i16), size(q16))
    error('bistatic:T04BitTrueInputType', ...
        'The integer core requires equal-length int16 I and Q vectors.');
end
core = policy.integer_core;
if ~strcmp(core.phase_format, 'signed_scaled_radians_q3_45') || ...
        core.phase_fractional_bits ~= 45
    error('bistatic:T04BitTrueQ345Policy', ...
        'The active integer core requires native signed Q3.45 phase.');
end
if core.metric_threshold_exact_numerator ~= 3 || ...
        core.metric_threshold_exact_denominator ~= 100 || ...
        core.energy_floor_integer ~= 0 || ...
        core.search_step_samples ~= 4
    error('bistatic:T04BitTruePolicyCore', ...
        'The integer-core policy differs from the implemented exact contract.');
end

halfLength = cfg.frame.fft_length / 2;
sampleCount = numel(i16);
if sampleCount < 2 * halfLength
    error('bistatic:T04BitTrueInputLength', ...
        'The integer input does not contain two half-lengths.');
end

oldI = int64(i16(1:end-halfLength));
oldQ = int64(q16(1:end-halfLength));
newI = int64(i16(halfLength+1:end));
newQ = int64(q16(halfLength+1:end));
pairRe = oldI .* newI + oldQ .* newQ;
pairIm = oldI .* newQ - oldQ .* newI;
energy = newI .* newI + newQ .* newQ;
prefixRe = [int64(0); cumsum(pairRe)];
prefixIm = [int64(0); cumsum(pairIm)];
prefixEnergy = [int64(0); cumsum(energy)];

starts = int64((core.search_start_samples: ...
    core.search_step_samples:core.search_stop_samples).');
if numel(starts) ~= 257
    error('bistatic:T04BitTrueSearchCount', ...
        'The frozen search must contain exactly 257 points.');
end
first = double(starts - int64(globalFirstSample) + 1);
lastPlusOne = first + halfLength;
if any(first < 1) || any(lastPlusOne > numel(prefixRe))
    error('bistatic:T04BitTrueSearchBounds', ...
        'The quantized vector does not cover the frozen search interval.');
end
rollingRe = prefixRe(lastPlusOne) - prefixRe(first);
rollingIm = prefixIm(lastPlusOne) - prefixIm(first);
rollingEnergy = prefixEnergy(lastPlusOne) - prefixEnergy(first);

qualified = false(numel(starts), 1);
if includeWideTrace
    thresholdLhs = strings(numel(starts), 1);
    thresholdRhs = strings(numel(starts), 1);
else
    thresholdLhs = strings(0, 1);
    thresholdRhs = strings(0, 1);
end
for index = 1:numel(starts)
    if rollingEnergy(index) > int64(core.energy_floor_integer)
        [qualified(index), lhsText, rhsText] = exactThreshold( ...
            rollingRe(index), rollingIm(index), rollingEnergy(index), ...
            includeWideTrace);
    else
        lhsText = "0";
        rhsText = "0";
    end
    if includeWideTrace
        thresholdLhs(index) = lhsText;
        thresholdRhs(index) = rhsText;
    end
end

estimate.valid = false;
estimate.error_code = uint16(1);
estimate.ambiguity = false;
estimate.coarse_start_sample = int64(0);
estimate.cfo_hz = int32(0);
estimate.quality_code = uint16(0);
estimate.phase_code_q3_45 = int64(0);
estimate.magnitude_code_q1_47 = int64(0);
estimate.plateau_beats = 0;
estimate.safe_point_count = 0;
estimate.leading_edge_sample = int64(0);
estimate.trailing_edge_sample = int64(0);

edges = diff([false; qualified; false]);
runStarts = find(edges == 1);
runEnds = find(edges == -1) - 1;
runLengths = runEnds - runStarts + 1;
eligible = find(runLengths >= core.minimum_run_beats);
if isempty(eligible)
    estimate.error_code = uint16(3);
    estimate.trace = makeTrace(starts, rollingRe, rollingIm, ...
        rollingEnergy, qualified, thresholdLhs, thresholdRhs);
    return;
end

chosen = eligible(1);
leading = starts(runStarts(chosen));
trailing = starts(runEnds(chosen));
leadingBeat = idivide(leading, int64(core.search_step_samples), 'fix');
trailingBeat = idivide(trailing, int64(core.search_step_samples), 'fix');
z = leadingBeat + trailingBeat - int64( ...
    cfg.frame.cyclic_prefix_samples / core.search_step_samples);
selectedBeat = divideByTwoRoundAway(z);
selectedStart = selectedBeat * int64(core.search_step_samples);

safeFirst = selectedStart + int64(core.safe_phase_first_offset_samples);
safeLast = selectedStart + int64(core.safe_phase_last_offset_samples);
safe = starts >= safeFirst & starts <= safeLast;
if ~any(safe)
    estimate.error_code = uint16(5);
    estimate.trace = makeTrace(starts, rollingRe, rollingIm, ...
        rollingEnergy, qualified, thresholdLhs, thresholdRhs);
    return;
end
safeRe = sum(rollingRe(safe), 'native');
safeIm = sum(rollingIm(safe), 'native');
safeEnergy = sum(rollingEnergy(safe), 'native');
if safeEnergy <= int64(core.energy_floor_integer) || ...
        (safeRe == 0 && safeIm == 0)
    estimate.error_code = uint16(4);
    estimate.trace = makeTrace(starts, rollingRe, rollingIm, ...
        rollingEnergy, qualified, thresholdLhs, thresholdRhs);
    return;
end

phaseNormalized = atan2(double(safeIm), double(safeRe)) / pi;
phaseScale = 2^45;
phaseRounded = t02_round_even(phaseNormalized * phaseScale);
if phaseRounded == phaseScale
    % Canonical circular endpoint: +pi is encoded as -pi.
    phaseRounded = -phaseScale;
elseif phaseRounded < -phaseScale || phaseRounded > phaseScale - 1
    error('bistatic:T04BitTrueQ345PrincipalRange', ...
        'Ideal Q3.45 phase escaped the canonical [-1,+1) interval.');
end
phaseCode = int64(phaseRounded);
cfoHz = phaseCodeToIntegerHz(phaseCode);

magnitudeRounded = t02_round_even(hypot(double(safeRe), double(safeIm)));
if magnitudeRounded < 0 || magnitudeRounded > double(intmax('int64'))
    error('bistatic:T04BitTrueMagnitudeRange', ...
        'Ideal Q1.47 magnitude is outside int64 range.');
end
magnitudeCode = int64(magnitudeRounded);
if magnitudeCode > idivide(intmax('int64'), int64(2^15), 'floor')
    error('bistatic:T04BitTrueQualityNumerator', ...
        'The shifted quality numerator would overflow int64.');
end
qualityQuotient = idivide(magnitudeCode * int64(2^15), ...
    safeEnergy, 'floor');
qualityCode = uint16(min(qualityQuotient, ...
    int64(core.quality_clamp_one_code)));

estimate.valid = true;
estimate.error_code = uint16(0);
estimate.ambiguity = numel(eligible) > 1;
estimate.coarse_start_sample = selectedStart;
estimate.cfo_hz = int32(cfoHz);
estimate.quality_code = qualityCode;
estimate.phase_code_q3_45 = phaseCode;
estimate.magnitude_code_q1_47 = magnitudeCode;
estimate.plateau_beats = runLengths(chosen);
estimate.safe_point_count = nnz(safe);
estimate.leading_edge_sample = leading;
estimate.trailing_edge_sample = trailing;
estimate.safe_correlation_re = safeRe;
estimate.safe_correlation_im = safeIm;
estimate.safe_energy = safeEnergy;
estimate.trace = makeTrace(starts, rollingRe, rollingIm, ...
    rollingEnergy, qualified, thresholdLhs, thresholdRhs);
end

function value = divideByTwoRoundAway(value)
if value >= 0
    value = idivide(value + 1, int64(2), 'floor');
else
    value = -idivide(-value + 1, int64(2), 'floor');
end
end

function [passed, lhsText, rhsText] = exactThreshold(pRe, pIm, energy, ...
    returnText)
pReBig = javaMethod('valueOf', 'java.math.BigInteger', pRe);
pImBig = javaMethod('valueOf', 'java.math.BigInteger', pIm);
energyBig = javaMethod('valueOf', 'java.math.BigInteger', energy);
hundred = javaMethod('valueOf', 'java.math.BigInteger', int64(100));
three = javaMethod('valueOf', 'java.math.BigInteger', int64(3));
pMagnitudeSquared = pReBig.multiply(pReBig).add( ...
    pImBig.multiply(pImBig));
lhs = pMagnitudeSquared.multiply(hundred);
rhs = energyBig.multiply(energyBig).multiply(three);
passed = lhs.compareTo(rhs) >= 0;
if returnText
    lhsText = string(char(lhs.toString()));
    rhsText = string(char(rhs.toString()));
else
    lhsText = "";
    rhsText = "";
end
end

function cfoHz = phaseCodeToIntegerHz(phaseCode)
phaseBig = javaMethod('valueOf', 'java.math.BigInteger', phaseCode);
constant = javaMethod('valueOf', 'java.math.BigInteger', int64(1953125));
numerator = phaseBig.multiply(constant);
rounded = roundPowerOfTwoEven(numerator, 48);
cfoHz = int64(str2double(char(rounded.toString())));
if cfoHz < int64(intmin('int32')) || cfoHz > int64(intmax('int32'))
    error('bistatic:T04BitTrueCfoRange', ...
        'Integer-Hz CFO does not fit signed 32 bits.');
end
end

function rounded = roundPowerOfTwoEven(value, shift)
one = javaObject('java.math.BigInteger', '1');
zero = javaObject('java.math.BigInteger', '0');
denominator = one.shiftLeft(shift);
absolute = value.abs();
parts = absolute.divideAndRemainder(denominator);
quotient = parts(1);
remainder = parts(2);
comparison = remainder.shiftLeft(1).compareTo(denominator);
if comparison > 0 || (comparison == 0 && quotient.testBit(0))
    quotient = quotient.add(one);
end
if value.signum() < 0
    rounded = quotient.negate();
elseif value.signum() > 0
    rounded = quotient;
else
    rounded = zero;
end
end

function trace = makeTrace(starts, pRe, pIm, energy, qualified, lhs, rhs)
trace.start_sample = starts;
trace.p_re = pRe;
trace.p_im = pIm;
trace.energy = energy;
trace.qualified = qualified;
trace.threshold_lhs_decimal = lhs;
trace.threshold_rhs_decimal = rhs;
end
