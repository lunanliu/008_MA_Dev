function symbols = bistatic_gray_qpsk(bits)
%BISTATIC_GRAY_QPSK Map bit pairs 00,01,11,10 around the four quadrants.

bits = double(bits);
if ~isvector(bits) || mod(numel(bits), 2) ~= 0 || any(bits ~= 0 & bits ~= 1)
    error('bistatic:QpskBits', 'Input must be an even-length vector of binary values.');
end
pairs = reshape(bits(:), 2, []);
symbols = complex(1 - 2 * pairs(2, :), 1 - 2 * pairs(1, :)) / sqrt(2);
symbols = symbols(:);
end
