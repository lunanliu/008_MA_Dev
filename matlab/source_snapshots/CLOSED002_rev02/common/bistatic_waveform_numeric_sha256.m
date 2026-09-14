function digest = bistatic_waveform_numeric_sha256(waveform)
%BISTATIC_WAVEFORM_NUMERIC_SHA256 Hash exact complex-double waveform samples.
% The descriptor binds timeline and provenance fields separately. This hash
% therefore covers only the ordered numeric sample vector, using an explicit
% stable serialization rather than MATLAB object or MAT-file bytes.

if ~isstruct(waveform) || ~isscalar(waveform) || ...
        ~isfield(waveform, 'samples')
    error('bistatic:WaveformNumericHashType', ...
        'waveform must be a scalar struct containing samples.');
end
values = waveform.samples;
if ~isa(values, 'double') || ~isvector(values) || isempty(values) || ...
        any(~isfinite(real(values))) || any(~isfinite(imag(values)))
    error('bistatic:WaveformNumericHashSamples', ...
        'waveform.samples must be a nonempty finite complex-double vector.');
end

shape = size(values);
shapeText = sprintf('%d,', shape);
shapeText(end) = [];
header = sprintf([ ...
    'bistatic_waveform_numeric_sha256_v1|ndims=%d|size=%s|' ...
    'order=MATLAB_column_major|layout=real_plane_then_imag_plane|' ...
    'encoding=IEEE754_binary64_little_endian|'], ...
    ndims(values), shapeText);
payload = [uint8(unicode2native(header, 'UTF-8')).'; ...
    binary64LittleEndian(real(values)); ...
    binary64LittleEndian(imag(values))];
digest = bistatic_sha256(payload, false);
end

function bytes = binary64LittleEndian(values)
bytes = reshape(typecast(double(values(:)), 'uint8'), 8, []);
[~, ~, endian] = computer;
if endian == 'B'
    bytes = flipud(bytes);
end
bytes = bytes(:);
end
