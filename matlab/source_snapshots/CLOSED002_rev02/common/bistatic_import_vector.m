function imported = bistatic_import_vector(basePath)
%BISTATIC_IMPORT_VECTOR Verify hashes and import a T01 vector bit-exactly.

binaryPath = [basePath '.bin'];
hexPath = [basePath '.hex'];
jsonPath = [basePath '.json'];
matPath = [basePath '.mat'];
metadata = jsondecode(fileread(jsonPath));

verifyHash(binaryPath, metadata.vector.binary_sha256);
verifyHash(hexPath, metadata.vector.hex_sha256);
verifyHash(matPath, metadata.vector.mat_sha256);

fid = fopen(binaryPath, 'rb', 'ieee-le');
if fid < 0
    error('bistatic:FileOpen', 'Cannot open vector binary: %s', binaryPath);
end
cleaner = onCleanup(@() fclose(fid));
raw = fread(fid, Inf, '*int16');
clear cleaner;
expectedWords = metadata.vector.beat_count * metadata.vector.samples_per_beat * 2;
if numel(raw) ~= expectedWords
    error('bistatic:VectorLength', 'Binary word count does not match metadata.');
end
packed = reshape(raw, 2 * metadata.vector.samples_per_beat, metadata.vector.beat_count);
sampleCount = metadata.vector.sample_count;
i16 = zeros(sampleCount, 1, 'int16');
q16 = zeros(sampleCount, 1, 'int16');
for sampleIndex = 1:sampleCount
    beat = floor((sampleIndex - 1) / metadata.vector.samples_per_beat) + 1;
    lane = mod(sampleIndex - 1, metadata.vector.samples_per_beat);
    i16(sampleIndex) = packed(2 * lane + 1, beat);
    q16(sampleIndex) = packed(2 * lane + 2, beat);
end

matData = load(matPath, 'i16', 'q16');
if ~isequal(i16, matData.i16) || ~isequal(q16, matData.q16)
    error('bistatic:VectorMatMismatch', 'MAT and binary quantized samples differ.');
end

imported.quantized_i = i16;
imported.quantized_q = q16;
imported.samples = complex(double(i16), double(q16)) / metadata.vector.scale_integer_per_unit;
imported.packed_words = packed;
imported.metadata = metadata;
end

function verifyHash(path, expected)
actual = bistatic_sha256(path, true);
if ~strcmpi(actual, expected)
    error('bistatic:VectorHashMismatch', 'SHA-256 mismatch for %s.', path);
end
end
