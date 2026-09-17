function report = compare_frontend_readback(readbackCsv)
% Compare NI/simulation readback against the frozen short-stream truth.
% Only received valid records belong in the CSV; preserve file row order.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
manifest = jsondecode(fileread(fullfile(root,'sim','data','autonomous_manifest.json')));
actual = readtable(readbackCsv, 'VariableNamingRule','preserve');
required = {'epoch','rx_frame_id','candidate_id','coarse_absolute','fine_absolute','cfo_hz','quality','status'};
assert(all(ismember(required,actual.Properties.VariableNames)), 'Missing readback columns');
assert(height(actual)==4, 'Expected exactly four received valid records');
expected = manifest.expected;
assert(all(actual.epoch==0), 'Unexpected epoch');
assert(isequal(actual.rx_frame_id(:),(0:3).'), 'Missing/duplicate/reordered local frame id');
assert(all(diff(actual.candidate_id)>0), 'Candidate order');
positionError = double(actual.fine_absolute(:)) - double([expected.true_start].');
cfoError = double(actual.cfo_hz(:)) - double([expected.expected_cfo_hz].');
assert(all(positionError==0), 'Fine TO mismatch');
assert(all(abs(cfoError)<=1000), 'CFO error exceeds original deterministic gate');
report = struct('scope','frozen four-frame readback only','frames',4, ...
    'maximumAbsoluteFineErrorSamples',max(abs(positionError)), ...
    'maximumAbsoluteCfoErrorHz',max(abs(cfoError)), ...
    'throughputQualified',false,'boardQualified',false);
disp(report);
end
