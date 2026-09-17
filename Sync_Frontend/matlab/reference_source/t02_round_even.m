function rounded = t02_round_even(values)
%T02_ROUND_EVEN Convergent round-to-nearest-even for finite doubles.

if any(~isfinite(values(:)))
    error('bistatic:T02RoundInput', 'Round-to-even input must be finite.');
end
lower = floor(values);
fraction = values - lower;
tolerance = 4 * eps(max(1, abs(values)));
tie = abs(fraction - 0.5) <= tolerance;
rounded = lower + (fraction > 0.5 + tolerance) + ...
    (tie & mod(lower, 2) ~= 0);
end
