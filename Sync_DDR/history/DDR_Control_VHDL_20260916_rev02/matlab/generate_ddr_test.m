function metadata = generate_ddr_test(outputDirectory, sampleCount, seed)
% DDR pattern: packed U32[n] = (seed + n) mod 2^32, n starts at zero.
% CSV INPUT remains two columns: I first, Q second, signed int16 values.
% Packing contract: I occupies bits 15:0; Q occupies bits 31:16.
% Example:
% generate_ddr_test('ddr_A',60324,uint32(hex2dec('FFFFFFF0')));
% generate_ddr_test('ddr_B',60324,uint32(hex2dec('1A2B3C40')));
if nargin < 1, outputDirectory = 'ddr_A'; end
if nargin < 2, sampleCount = 60324; end
if nargin < 3, seed = uint32(hex2dec('FFFFFFF0')); end
validateattributes(sampleCount,{'numeric'},{'scalar','integer','positive','<=',81920});
assert(mod(sampleCount,4)==0,'sampleCount must be a multiple of four.');
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative','<=',4294967295});
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
sampleCount = double(sampleCount);
seed = uint32(seed);
index = uint64((0:sampleCount-1)');
words = uint32(bitand(uint64(seed)+index,uint64(4294967295)));
iValue = double(bitand(words,uint32(65535)));
qValue = double(bitshift(words,-16));
iValue(iValue>=32768) = iValue(iValue>=32768)-65536;
qValue(qValue>=32768) = qValue(qValue>=32768)-65536;
writematrix([iValue qValue],fullfile(outputDirectory,'input_iq_i16.csv'),'Delimiter',',');
% This is a reference output, not the waveform-input CSV.
writematrix(double(words),fullfile(outputDirectory,'expected_u32.csv'),'Delimiter',',');
metadata = struct('sample_count',sampleCount,'ddr_word_count',ceil(sampleCount/40), ...
    'pattern_seed_u32',double(seed),'pattern_seed_hex',dec2hex(seed,8), ...
    'first_word_u32',double(words(1)),'last_word_u32',double(words(end)), ...
    'packing','I in low 16 bits, Q in high 16 bits, two-complement bit patterns', ...
    'formula','word[n] = (seed + n) mod 2^32, zero-based n');
fid = fopen(fullfile(outputDirectory,'metadata.json'),'w');
assert(fid>=0,'Could not create metadata.json.');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(metadata,PrettyPrint=true));
disp(metadata);
end