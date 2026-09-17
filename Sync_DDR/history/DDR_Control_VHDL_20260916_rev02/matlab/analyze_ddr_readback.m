function result = analyze_ddr_readback(readbackFile, metadataFile, includePadding)
% Readback CSV is a SINGLE row or column of packed, unsigned 32-bit words.
% Example: analyze_ddr_readback('readback_A.csv','ddr_A/metadata.json')
% To inspect zero padding, read ceil(N/40)*40 samples with checker disabled,
% then call with includePadding=true. Do not send padded input to the loader.
if nargin<3, includePadding=false; end
meta = jsondecode(fileread(metadataFile));
x = readmatrix(readbackFile);
assert(isvector(x) && ~isempty(x),'Readback CSV must be one numeric row or column.');
x = x(:);
assert(all(isfinite(x) & x>=0 & x<=4294967295 & x==fix(x)), ...
    'Readback must contain exact unsigned 32-bit integer values.');
n = double(meta.sample_count);
expected = uint32(bitand(uint64(meta.pattern_seed_u32)+uint64((0:n-1)'),uint64(4294967295)));
if includePadding
    expected(end+1:double(meta.ddr_word_count)*40,1)=uint32(0);
end
actual = uint32(x);
common = min(numel(actual),numel(expected));
bad = find(actual(1:common)~=expected(1:common));
result = struct('expected_count',numel(expected),'actual_count',numel(actual), ...
    'compared_count',common,'mismatch_count',numel(bad), ...
    'length_ok',numel(actual)==numel(expected),'exact_match',false);
result.exact_match = result.length_ok && isempty(bad);
if ~isempty(bad)
    first = bad(1);
    result.first_error_index_zero_based=first-1;
    result.first_expected=double(expected(first));
    result.first_actual=double(actual(first));
end
disp(result);
assert(result.exact_match,'DDR readback does not exactly match the original pattern.');
end