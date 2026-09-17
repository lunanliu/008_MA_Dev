function summary = validate_frontend_boardtest(attemptDir)
% Offline verification of NEW CSV conversion and analyzer, never an RTL/board run.
assert(~isfolder(attemptDir),'Use a new validation attempt directory');
mkdir(attemptDir);
root=fileparts(mfilename('fullpath'));
baseline=fullfile(root,'data','baseline');
if isfolder(baseline)
    % Preserve an already generated delivery fixture across script-fix attempts.
    info=jsondecode(fileread(fullfile(baseline,'manifest.json')));
else
    info=generate_frontend_csv(baseline,'baseline');
end
assert(info.sample_count==60324 && info.beat_count==15081);
dma=double(read_iq_words(fullfile(baseline,'input_iq.csv')));
% Compare every lane to the frozen source, independently of the CSV writer.
rows=strip(readlines(fullfile(root,'reference','autonomous_stream.mem')));
rows=char(rows(strlength(rows)>0));
for lane=0:3
    first=25-8*lane;
    assert(isequal(dma(lane+1:4:end),hex2dec(rows(:,first:first+7))),'I/Q values or lane order changed');
end
schedule=readtable(fullfile(baseline,'host_chunks.csv'));
assert(sum(schedule.word_count)==60324 && all(mod(schedule.word_count,4)==0));
assert(schedule.wait_accepted_samples(end)==60324);
ref=readtable(fullfile(root,'reference','autonomous_results.csv'));
records=zeros(4,9,'uint32');
records(:,1)=uint32(ref.epoch); records(:,2)=uint32(ref.rx_frame_id);
records(:,3)=uint32(ref.candidate_id);
coarse=uint64(ref.coarse_absolute); fine=uint64(ref.fine_absolute);
records(:,4)=uint32(bitand(coarse,uint64(4294967295)));
records(:,5)=uint32(bitshift(coarse,-32));
records(:,6)=uint32(bitand(fine,uint64(4294967295)));
records(:,7)=uint32(bitshift(fine,-32));
records(:,8)=reshape(typecast(int32(ref.cfo_hz),'uint32'),[],1);
records(:,9)=bitor(bitshift(uint32(hex2dec(char(string(ref.status)))),16),uint32(ref.quality));
exampleFile=fullfile(root,'reference','example_SIMULATION_readback_u32.csv');
expectedExample=double(reshape(records.',[],1));
if isfile(exampleFile)
    assert(isequal(readmatrix(exampleFile),expectedExample),'Existing simulation example differs');
else
    writematrix(expectedExample,exampleFile);
end
options=struct('ExpectedEpoch',0,'AcceptedSamples',60324,'ErrorSticky',0,'StrictRtl',true);
good=analyze_frontend_readback(exampleFile,baseline,fullfile(attemptDir,'good'),options);
assert(strcmp(good.verdict,'FINITE_REPLAY_CHECKS_PASS'),'Reference decode failed');
changed=records; changed(2,:)=records(1,:);
expect_failure(changed,'duplicate_frame',baseline,attemptDir,options);
changed=records; changed(3,8)=uint32(typecast(int32(180000),'uint32'));
expect_failure(changed,'wrong_cfo',baseline,attemptDir,options);
changed=records; changed(4,6)=changed(4,6)+1;
expect_failure(changed,'wrong_timing',baseline,attemptDir,options);
changed=records; changed(:,9)=bitand(changed(:,9),uint32(hex2dec('F7FFFFFF')));
expect_failure(changed,'invalid_status',baseline,attemptDir,options);
tailFile=fullfile(attemptDir,'truncated_input.csv');
flat=reshape(records.',[],1); writematrix(double(flat(1:end-1)),tailFile);
tailReport=analyze_frontend_readback(tailFile,baseline,fullfile(attemptDir,'truncated'),options);
assert(~tailReport.checks.complete_nine_word_records);
emptyFile=fullfile(attemptDir,'empty_input.csv');
fid=fopen(emptyFile,'w'); fclose(fid);
emptyReport=analyze_frontend_readback(emptyFile,baseline,fullfile(attemptDir,'empty'),options);
assert(~emptyReport.checks.expected_record_count);
optionsNoDiag=struct;
noDiag=analyze_frontend_readback(exampleFile,baseline,fullfile(attemptDir,'no_diagnostics'),optionsNoDiag);
assert(strcmp(noDiag.verdict,'RESULT_FIELDS_PASS_DIAGNOSTICS_NOT_CHECKED'));
changed=records; changed(:,1)=1;
epochFile=fullfile(attemptDir,'epoch1_input.csv');
writematrix(double(reshape(changed.',[],1)),epochFile);
epochReport=analyze_frontend_readback(epochFile,baseline,fullfile(attemptDir,'epoch1'), ...
    struct('ExpectedEpoch',1,'AcceptedSamples',60324,'ErrorSticky',0));
assert(strcmp(epochReport.verdict,'FINITE_REPLAY_CHECKS_PASS'));
badShape=fullfile(attemptDir,'bad_shape.csv');
writematrix([1 2;3 4],badShape);
rejected=false;
try
    analyze_frontend_readback(badShape,baseline,fullfile(attemptDir,'bad_shape_analysis'));
catch ex
    rejected=contains(ex.message,'ONE numeric column');
end
assert(rejected,'Multi-column readback was not rejected');
% Verify exact uint64 reconstruction above double precision, independent of truth.
changed=records;
large=bitshift(uint64(1),60)+uint64(12345);
changed(1,4)=uint32(bitand(large,uint64(4294967295)));
changed(1,5)=uint32(bitshift(large,-32));
largeFile=fullfile(attemptDir,'uint64_input.csv');
writematrix(double(reshape(changed.',[],1)),largeFile);
analyze_frontend_readback(largeFile,baseline,fullfile(attemptDir,'uint64'));
csvFile=fullfile(attemptDir,'uint64','decoded_results.csv');
importOptions=detectImportOptions(csvFile);
importOptions=setvartype(importOptions,{'coarse_absolute','fine_absolute'},'uint64');
decoded=readtable(csvFile,importOptions);
assert(decoded.coarse_absolute(1)==large,'U64 precision lost');
custom=fullfile(attemptDir,'custom');
customInfo=generate_frontend_csv(custom,'custom', ...
    struct('Seed',7,'LeadingNoiseSamples',8192,'GapSamples',12288));
customWords=read_iq_words(fullfile(custom,'input_iq.csv'));
baseTruth=readtable(fullfile(baseline,'expected_truth.csv'));
customTruth=readtable(fullfile(custom,'expected_truth.csv'));
for k=1:4
    a=baseTruth.fixture_start_0(k)+(1:3176);
    b=customTruth.fixture_start_0(k)+(1:3176);
    assert(isequal(uint32(dma(a)),customWords(b)),'Custom fragment changed');
end
assert(mod(customInfo.sample_count,4)==0);
analyzerFiles={'generate_frontend_csv.m','analyze_frontend_readback.m','validate_frontend_boardtest.m'};
issueCounts=zeros(1,numel(analyzerFiles));
for k=1:numel(analyzerFiles)
    issues=checkcode(fullfile(root,analyzerFiles{k}),'-id');
    issueCounts(k)=numel(issues);
    disp(issues);
end
summary=struct('status','NEW_MATLAB_SCRIPTS_VERIFIED','baseline_samples',60324, ...
    'baseline_words',numel(dma),'example_reference_records',4, ...
    'negative_cases','duplicate frame; wrong CFO; wrong timing; invalid status; truncated; empty; bad shape', ...
    'other_cases','missing diagnostics; epoch selection; exact uint64; custom fragment preservation', ...
    'code_analyzer_issue_counts',issueCounts,'new_rtl_simulation_run',false,'board_data_tested',false);
fid=fopen(fullfile(attemptDir,'validation_summary.json'),'w','n','UTF-8');
fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true)); fclose(fid);
disp(summary);
end
function expect_failure(records,name,baseline,attemptDir,options)
file=fullfile(attemptDir,[name '_input.csv']);
writematrix(double(reshape(records.',[],1)),file);
report=analyze_frontend_readback(file,baseline,fullfile(attemptDir,name),options);
assert(strcmp(report.verdict,'FAIL_OR_INCOMPLETE_CAPTURE'),'Bad data not rejected: %s',name);
end

function words=read_iq_words(path)
iq=readmatrix(path,'Delimiter',',');
assert(size(iq,2)==2 && all(isfinite(iq(:)) & iq(:)==fix(iq(:)) & ...
    iq(:)>=-32768 & iq(:)<=32767),'Expected two signed I16 columns');
words=bitor(uint32(mod(iq(:,1),65536)),bitshift(uint32(mod(iq(:,2),65536)),16));
end
