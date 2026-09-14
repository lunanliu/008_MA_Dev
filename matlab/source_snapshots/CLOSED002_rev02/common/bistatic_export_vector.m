function manifest = bistatic_export_vector(basePath, samples, scaleIntegerPerUnit, metadata)
%BISTATIC_EXPORT_VECTOR Export 4-lane I16/Q16 beats plus JSON/MAT metadata.
% Binary beat order is little-endian int16 [I0,Q0,I1,Q1,I2,Q2,I3,Q3].
% Text hex is conventional MSB-first {Q3,I3,Q2,I2,Q1,I1,Q0,I0}.

if scaleIntegerPerUnit <= 0 || ~isfinite(scaleIntegerPerUnit)
    error('bistatic:VectorScale', 'scaleIntegerPerUnit must be finite and positive.');
end
samples = samples(:);
if any(~isfinite(real(samples))) || any(~isfinite(imag(samples)))
    error('bistatic:VectorSamples', 'Vector samples must be finite.');
end
requiredMetadata = {'config', 'artifacts', 'boundary', 'physical', 'truth', ...
    'expected', 'rng', 'channel', 'noise'};
for requiredIndex = 1:numel(requiredMetadata)
    if ~isfield(metadata, requiredMetadata{requiredIndex})
        error('bistatic:VectorMetadata', 'Missing required metadata section: %s', ...
            requiredMetadata{requiredIndex});
    end
end
parent = fileparts(basePath);
if ~isempty(parent) && ~isfolder(parent)
    mkdir(parent);
end

i16 = saturatingRoundEven(real(samples) * scaleIntegerPerUnit);
q16 = saturatingRoundEven(imag(samples) * scaleIntegerPerUnit);
sampleCount = numel(samples);
samplesPerBeat = 4;
beatCount = ceil(sampleCount / samplesPerBeat);
packed = zeros(2 * samplesPerBeat, beatCount, 'int16');
for sampleIndex = 1:sampleCount
    beat = floor((sampleIndex - 1) / samplesPerBeat) + 1;
    lane = mod(sampleIndex - 1, samplesPerBeat);
    packed(2 * lane + 1, beat) = i16(sampleIndex);
    packed(2 * lane + 2, beat) = q16(sampleIndex);
end

binaryPath = [basePath '.bin'];
hexPath = [basePath '.hex'];
jsonPath = [basePath '.json'];
matPath = [basePath '.mat'];

fid = fopen(binaryPath, 'wb', 'ieee-le');
if fid < 0
    error('bistatic:FileOpen', 'Cannot create vector binary: %s', binaryPath);
end
cleaner = onCleanup(@() fclose(fid));
written = fwrite(fid, packed(:), 'int16');
if written ~= numel(packed)
    error('bistatic:VectorWrite', 'Short binary write for %s.', binaryPath);
end
clear cleaner;

fid = fopen(hexPath, 'wt');
if fid < 0
    error('bistatic:FileOpen', 'Cannot create vector hex: %s', hexPath);
end
cleaner = onCleanup(@() fclose(fid));
for beat = 1:beatCount
    line = '';
    for lane = 3:-1:0
        unsignedI = typecast(packed(2 * lane + 1, beat), 'uint16');
        unsignedQ = typecast(packed(2 * lane + 2, beat), 'uint16');
        line = [line sprintf('%04X%04X', unsignedQ, unsignedI)]; %#ok<AGROW>
    end
    fprintf(fid, '%s\n', line);
end
clear cleaner;

algorithmOverflow = '';
if isfield(metadata, 'vector') && ...
        isfield(metadata.vector, 'algorithm_overflow')
    algorithmOverflow = metadata.vector.algorithm_overflow;
end

validLast = mod(sampleCount, samplesPerBeat);
if validLast == 0 && beatCount > 0
    validLast = samplesPerBeat;
end
laneValidMask = 2^validLast - 1;
metadata.vector.schema_version = 1;
metadata.vector.sample_count = sampleCount;
metadata.vector.beat_count = beatCount;
metadata.vector.samples_per_beat = samplesPerBeat;
metadata.vector.iq_format = 'signed_twos_complement_i16_q16';
metadata.vector.rounding = 'convergent_round_to_even';
metadata.vector.export_quantizer_overflow = 'explicit_saturation';
if isempty(algorithmOverflow)
    metadata.vector.overflow = 'explicit_saturation';
else
    metadata.vector.overflow = algorithmOverflow;
end
metadata.vector.scale_integer_per_unit = scaleIntegerPerUnit;
metadata.vector.lsb_in_complex_units = 1 / scaleIntegerPerUnit;
metadata.vector.binary_layout = 'little_endian_int16_per_beat_[I0,Q0,I1,Q1,I2,Q2,I3,Q3]';
metadata.vector.hex_layout = 'MSB_to_LSB_{Q3,I3,Q2,I2,Q1,I1,Q0,I0}';
metadata.vector.lane_zero_is_earliest = true;
metadata.vector.last_beat_lane_valid_mask = laneValidMask;
metadata.vector.binary_sha256 = bistatic_sha256(binaryPath, true);
metadata.vector.hex_sha256 = bistatic_sha256(hexPath, true);

save(matPath, 'metadata', 'i16', 'q16', 'packed', '-v7');
metadata.vector.mat_sha256 = bistatic_sha256(matPath, true);
jsonText = jsonencode(metadata, PrettyPrint=true);
fid = fopen(jsonPath, 'wt');
if fid < 0
    error('bistatic:FileOpen', 'Cannot create vector metadata: %s', jsonPath);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonText);
clear cleaner;

manifest.base_path = basePath;
manifest.binary_path = binaryPath;
manifest.hex_path = hexPath;
manifest.json_path = jsonPath;
manifest.mat_path = matPath;
manifest.sample_count = sampleCount;
manifest.beat_count = beatCount;
manifest.scale_integer_per_unit = scaleIntegerPerUnit;
manifest.quantized_i = i16;
manifest.quantized_q = q16;
manifest.metadata = metadata;
end

function quantized = saturatingRoundEven(values)
lower = floor(values);
fraction = values - lower;
tolerance = 4 * eps(max(1, abs(values)));
tie = abs(fraction - 0.5) <= tolerance;
rounded = lower + (fraction > 0.5 + tolerance) + ...
    (tie & mod(lower, 2) ~= 0);
rounded = min(max(rounded, -32768), 32767);
quantized = int16(rounded);
end
