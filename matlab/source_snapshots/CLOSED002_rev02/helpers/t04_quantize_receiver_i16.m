function quantized = t04_quantize_receiver_i16(samples, integerPerUnit)
%T04_QUANTIZE_RECEIVER_I16 Apply the frozen case-independent I16 boundary.

if ~isscalar(integerPerUnit) || ~isfinite(integerPerUnit) || ...
        integerPerUnit <= 0
    error('bistatic:T04BitTrueScale', ...
        'integerPerUnit must be one positive finite scalar.');
end
rawI = t02_round_even(real(samples(:)) * integerPerUnit);
rawQ = t02_round_even(imag(samples(:)) * integerPerUnit);
minimum = double(intmin('int16'));
maximum = double(intmax('int16'));
clipI = rawI < minimum | rawI > maximum;
clipQ = rawQ < minimum | rawQ > maximum;
limitedI = min(max(rawI, minimum), maximum);
limitedQ = min(max(rawQ, minimum), maximum);

quantized.i = int16(limitedI);
quantized.q = int16(limitedQ);
quantized.clip_i_count = nnz(clipI);
quantized.clip_q_count = nnz(clipQ);
quantized.clip_component_count = nnz(clipI) + nnz(clipQ);
quantized.sample_count = numel(samples);
quantized.integer_per_unit = integerPerUnit;
end
