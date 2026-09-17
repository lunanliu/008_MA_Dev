function report = analyze_frontend_readback(readbackCsv, inputDir, outputDir, options)
%ANALYZE_FRONTEND_READBACK Decode raw DMA words and compare TO/CFO to truth.
% Input: ONE COLUMN of unsigned decimal words, no header, in received order.
% Do NOT pass the truth CSV or decoded mixed-field table as readback.
% Options: ExpectedEpoch (default 0), AcceptedSamples, ErrorSticky, StrictRtl.
% StrictRtl is valid only for baseline + exact original FPGA cycle schedule.
if nargin<4, options=struct; end
root=fileparts(mfilename('fullpath'));
if nargin<2 || isempty(inputDir), inputDir=fullfile(root,'data','baseline'); end
if nargin<3 || isempty(outputDir)
    outputDir=fullfile(fileparts(char(readbackCsv)), ...
        ['analysis_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
end
allowed={'ExpectedEpoch','AcceptedSamples','ErrorSticky','StrictRtl'};
assert(isempty(setdiff(fieldnames(options),allowed)),'Unknown analysis option');
expectedEpoch=get_option(options,'ExpectedEpoch',0);
strict=get_option(options,'StrictRtl',false);
validateattributes(expectedEpoch,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
validateattributes(strict,{'logical'},{'scalar'});
if isfolder(outputDir)
    entries=dir(outputDir);
    assert(~any(~ismember({entries.name},{'.','..'})),'Choose a new, empty analysis directory');
else
    mkdir(outputDir);
end
manifest=jsondecode(fileread(fullfile(inputDir,'manifest.json')));
truth=readtable(fullfile(inputDir,'expected_truth.csv'),'VariableNamingRule','preserve');
if isfile(readbackCsv) && dir(readbackCsv).bytes==0
    raw=zeros(0,1);
else
    raw=readmatrix(readbackCsv);
end
assert(isnumeric(raw) && (isempty(raw) || size(raw,2)==1), ...
    'Readback CSV must have ONE numeric column, NO HEADER');
assert(all(isfinite(raw(:)) & raw(:)>=0 & raw(:)<=2^32-1 & raw(:)==fix(raw(:))), ...
    'DMA words must be exact unsigned decimal integers in [0, 4294967295]');
raw=uint32(raw(:));
nr=floor(numel(raw)/9); tail=mod(numel(raw),9);
words=reshape(raw(1:9*nr),9,[]).';
epoch=words(:,1); frame=words(:,2); candidate=words(:,3);
coarse=bitor(uint64(words(:,4)),bitshift(uint64(words(:,5)),32));
fine=bitor(uint64(words(:,6)),bitshift(uint64(words(:,7)),32));
cfo=reshape(typecast(words(:,8),'int32'),[],1);
quality=uint16(bitand(words(:,9),uint32(65535)));
status=uint16(bitshift(words(:,9),-16));
resultValid=bitand(status,uint16(hex2dec('0800')))~=0;
qualityValue=double(quality)/32768;
decoded=table(epoch,frame,candidate,coarse,fine,cfo,quality,qualityValue,status,resultValid, ...
    'VariableNames',{'epoch','rx_frame_id','candidate_id','coarse_absolute','fine_absolute', ...
    'cfo_hz','quality_q1_15','quality_value','result_status_u16','status_valid'});
writetable(decoded,fullfile(outputDir,'decoded_results.csv'));
if tail>0
    writematrix(double(raw(end-tail+1:end)),fullfile(outputDir,'incomplete_tail_u32.csv'));
end
truthIndex=double(frame)+1;
matched=truthIndex>=1 & truthIndex<=height(truth);
expectedFine=nan(nr,1); expectedCfo=nan(nr,1);
expectedFine(matched)=truth.fine_absolute_truth(truthIndex(matched));
expectedCfo(matched)=truth.cfo_truth_hz(truthIndex(matched));
fineMatches=false(nr,1);
fineMatches(matched)=fine(matched)==uint64(expectedFine(matched));
fineError=nan(nr,1);
safe=matched & fine<=uint64(flintmax) & expectedFine<=flintmax;
fineError(safe)=double(fine(safe))-expectedFine(safe);
cfoError=double(cfo)-expectedCfo;
comparison=table(frame,expectedFine,fine,fineError,expectedCfo,cfo,cfoError, ...
    'VariableNames',{'rx_frame_id','expected_fine_absolute','actual_fine_absolute', ...
    'fine_error_samples','expected_cfo_hz','actual_cfo_hz','cfo_error_hz'});
writetable(comparison,fullfile(outputDir,'comparison.csv'));
checks=struct;
checks.complete_nine_word_records=tail==0;
checks.expected_record_count=nr==height(truth);
checks.epoch_matches=all(epoch==uint32(expectedEpoch));
checks.frame_ids_in_order=isequal(double(frame),(0:height(truth)-1).');
checks.candidate_ids_increasing=nr==height(truth) && all(diff(double(candidate))>0);
checks.fine_timing_exact=nr==height(truth) && all(fineMatches);
checks.cfo_within_1000_hz=nr==height(truth) && all(abs(cfoError)<=1000);
checks.result_status_valid=nr==height(truth) && all(resultValid);
checks.accepted_samples_checked=isfield(options,'AcceptedSamples');
checks.accepted_samples_match=false;
if checks.accepted_samples_checked
    validateattributes(options.AcceptedSamples,{'numeric'},{'scalar','integer','nonnegative','finite'});
    checks.accepted_samples_match=options.AcceptedSamples==manifest.sample_count;
end
checks.error_sticky_checked=isfield(options,'ErrorSticky');
checks.error_sticky_clear=false;
if checks.error_sticky_checked
    validateattributes(options.ErrorSticky,{'numeric'},{'scalar','integer','nonnegative','finite'});
    checks.error_sticky_clear=options.ErrorSticky==0;
end
if strict
    assert(strcmp(manifest.mode,'baseline'),'StrictRtl is only defined for baseline');
    % This reference stores the status as HEX TEXT, e.g. "3800" means 0x3800.
    ref=readtable(fullfile(root,'reference','autonomous_results.csv'), ...
        'TextType','string','VariableNamingRule','preserve');
    expectedStatus=uint16(hex2dec(char(string(ref.status))));
    checks.strict_original_rtl_fields=nr==height(ref) && ...
        isequal(candidate,uint32(ref.candidate_id)) && ...
        isequal(coarse,uint64(ref.coarse_absolute)) && ...
        isequal(fine,uint64(ref.fine_absolute)) && isequal(cfo,int32(ref.cfo_hz)) && ...
        isequal(quality,uint16(ref.quality)) && isequal(status,expectedStatus);
end
names=fieldnames(checks);
mainNames=setdiff(names,{'accepted_samples_checked','accepted_samples_match', ...
    'error_sticky_checked','error_sticky_clear'});
resultPass=all(cellfun(@(key)checks.(key),mainNames));
diagnosticFailure=(checks.accepted_samples_checked && ~checks.accepted_samples_match) || ...
    (checks.error_sticky_checked && ~checks.error_sticky_clear);
if ~resultPass || diagnosticFailure
    verdict='FAIL_OR_INCOMPLETE_CAPTURE';
elseif ~checks.accepted_samples_checked || ~checks.error_sticky_checked
    verdict='RESULT_FIELDS_PASS_DIAGNOSTICS_NOT_CHECKED';
else
    verdict='FINITE_REPLAY_CHECKS_PASS';
end
report=struct('verdict',verdict,'mode',manifest.mode,'readback_csv',char(readbackCsv), ...
    'word_count',numel(raw),'complete_records',nr,'trailing_words',tail, ...
    'expected_epoch',expectedEpoch,'checks',checks,'strict_rtl_requested',strict, ...
    'sustained_throughput_qualified',false, ...
    'note','Only supplied finite-replay data checked. No automatic packet realignment or missing-word repair.');
if checks.accepted_samples_checked, report.accepted_samples=options.AcceptedSamples; end
if checks.error_sticky_checked, report.error_sticky=options.ErrorSticky; end
write_json(fullfile(outputDir,'analysis_summary.json'),report);
fid=fopen(fullfile(outputDir,'analysis_summary.txt'),'w','n','UTF-8');
assert(fid>=0,'Cannot write text summary');
fprintf(fid,'Verdict: %s\nWords: %d; complete records: %d; tail words: %d\n',verdict,numel(raw),nr,tail);
for k=1:numel(names), fprintf(fid,'%s: %d\n',names{k},checks.(names{k})); end
fprintf(fid,'This is a finite replay check, not sustained ADC/board qualification.\n');
fclose(fid);
fig=figure('Visible','off','Color','w','Position',[100 100 1100 700]);
cleanupFig=onCleanup(@()close(fig)); %#ok<NASGU>
tiledlayout(2,1);
nexttile; plot(0:height(truth)-1,truth.fine_absolute_truth,'ko-'); hold on;
if nr>0, plot(double(frame),double(fine),'rx'); end
xlabel('Frame ID'); ylabel('Absolute sample index (zero based)');
legend('Truth','Received','Location','best'); grid on; title('Fine timing');
nexttile; plot(0:height(truth)-1,truth.cfo_truth_hz/1000,'ko-'); hold on;
if nr>0, plot(double(frame),double(cfo)/1000,'rx'); end
xlabel('Frame ID'); ylabel('CFO (kHz)'); grid on; title('Frequency offset');
exportgraphics(fig,fullfile(outputDir,'readback_comparison.png'),'Resolution',140);
disp(report);
end
function value=get_option(s,name,default)
if isfield(s,name), value=s.(name); else, value=default; end
end
function write_json(path,value)
fid=fopen(path,'w','n','UTF-8'); assert(fid>=0,'Cannot write JSON');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
