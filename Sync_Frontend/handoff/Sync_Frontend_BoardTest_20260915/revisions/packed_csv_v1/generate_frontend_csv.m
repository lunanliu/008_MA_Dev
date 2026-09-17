function info = generate_frontend_csv(outputDir, mode, options)
%GENERATE_FRONTEND_CSV Create CSV samples for the compiled Sync_Frontend.
% generate_frontend_csv() regenerates the frozen baseline into generated_baseline.
% generate_frontend_csv('my_custom','custom',struct('Seed',7,'GapSamples',12288))
% "baseline": exact frozen input used by the existing RTL test.
% "custom": new low-level noise/gaps, reusing the same four validated IQ fragments.
% Does not generate a complete OFDM payload frame or run a new RTL simulation.
if nargin < 2 || isempty(mode), mode = 'baseline'; end
if nargin < 3, options = struct; end
root = fileparts(mfilename('fullpath'));
mode = validatestring(mode, {'baseline','custom'});
if nargin < 1 || isempty(outputDir)
    outputDir = fullfile(root, ['generated_' mode]);
end
outputDir = char(outputDir);
if isfolder(outputDir)
    entries = dir(outputDir);
    if any(~ismember({entries.name},{'.','..'}))
        error('frontend:OutputExists','Choose a new, empty output directory: %s',outputDir);
    end
else
    mkdir(outputDir);
end
allowed = {'Seed','LeadingNoiseSamples','GapSamples','NoiseCodePeak','IncludeFakePreamble'};
unknown = setdiff(fieldnames(options),allowed);
assert(isempty(unknown),'Unknown generator option');
streamFile = fullfile(root,'reference','autonomous_stream.mem');
sourceManifest = jsondecode(fileread(fullfile(root,'reference','autonomous_manifest.json')));
sourceHash = sha256_file(streamFile);
hashKey = matlab.lang.makeValidName('autonomous_stream.mem_sha256');
assert(strcmpi(sourceHash,sourceManifest.(hashKey)), 'Frozen input SHA256 mismatch');
baseWords = read_hex_beats(streamFile);
assert(numel(baseWords)==sourceManifest.accepted_samples,'Frozen input length mismatch');
sourceTruth = sourceManifest.expected;
trueStart = double([sourceTruth.true_start].');
origin = double([sourceTruth.fixture_start].');
cfo = double([sourceTruth.expected_cfo_hz].');
caseId = string({sourceTruth.case_id}.');
if strcmp(mode,'baseline')
    assert(isempty(fieldnames(options)), 'Options apply only to custom mode');
    words = baseWords;
    generationNote = 'Exact frozen input; original RTL timing schedule was 256 beats then 8000 idle clocks.';
else
    seed = get_option(options,'Seed',9414002);
    lead = get_option(options,'LeadingNoiseSamples',4096);
    gap = get_option(options,'GapSamples',8192);
    peak = get_option(options,'NoiseCodePeak',10);
    includeFake = get_option(options,'IncludeFakePreamble',true);
    validateattributes(seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
    validateattributes(lead,{'numeric'},{'scalar','integer','>=',0,'<=',1e7});
    validateattributes(gap,{'numeric'},{'scalar','integer','>=',8192,'<=',1e7});
    validateattributes(peak,{'numeric'},{'scalar','integer','>=',0,'<=',10});
    validateattributes(includeFake,{'logical'},{'scalar'});
    previousRng = rng; restoreRng = onCleanup(@()rng(previousRng)); %#ok<NASGU>
    rng(seed,'twister');
    words = noise_words(lead,peak);
    if includeFake
        fake = noise_words(1024,8000);
        words = [words;fake(end-511:end);fake;fake]; %#ok<AGROW>
    end
    words = [words;noise_words(gap,peak)];
    for k=1:4
        relativeStart = double(sourceTruth(k).true_start-sourceTruth(k).fixture_start);
        while mod(numel(words)+relativeStart,4)~=k-1
            words(end+1,1) = noise_words(1,peak); %#ok<AGROW>
        end
        origin(k) = numel(words);
        trueStart(k) = origin(k)+relativeStart;
        indices = double(sourceTruth(k).fixture_start)+(1:3176);
        words = [words;baseWords(indices);noise_words(gap,peak)]; %#ok<AGROW>
    end
    if mod(numel(words),4)~=0
        words = [words;noise_words(4-mod(numel(words),4),peak)];
    end
    generationNote = ['New MATLAB-assembled stream. Four IQ fragments/CFO values are unchanged; ' ...
        'new noise and spacing have NOT been RTL- or board-qualified.'];
end
iCodes = typecast(uint16(bitand(words,uint32(65535))),'int16');
qCodes = typecast(uint16(bitshift(words,-16)),'int16');
iCodes = iCodes(:); qCodes = qCodes(:);
assert(isequal(pack_iq(iCodes,qCodes),words),'I/Q packing round trip');
n = numel(words);
% Exactly one unsigned decimal integer per line, NO HEADER.
writematrix(double(words),fullfile(outputDir,'input_dma_u32.csv'));
sampleIndex = (0:n-1).';
timeUs = sampleIndex/500e6*1e6;
iq = table(sampleIndex,timeUs,iCodes,qCodes,words, ...
    'VariableNames',{'sample_index_0','signal_time_us','i_i16','q_i16','dma_u32'});
writetable(iq,fullfile(outputDir,'input_iq_view.csv'));
beats = reshape(words,4,[]).';
writematrix(double(beats),fullfile(outputDir,'input_four_lanes_view.csv'));
truth = table((0:3).',caseId,origin,trueStart,cfo,mod(trueStart,4), ...
    'VariableNames',{'rx_frame_id','case_id','fixture_start_0','fine_absolute_truth','cfo_truth_hz','lane'});
writetable(truth,fullfile(outputDir,'expected_truth.csv'));
starts = (0:1024:n-1).';
lengths = min(1024,n-starts);
schedule = table((0:numel(starts)-1).',starts,lengths,starts+lengths,ones(size(starts)), ...
    'VariableNames',{'chunk_index_0','first_sample_0','word_count','wait_accepted_samples','host_pause_ms'});
writetable(schedule,fullfile(outputDir,'host_chunks.csv'));
info = struct('mode',mode,'sample_rate_hz',500e6,'fpga_clock_hz',125e6, ...
    'sample_count',n,'beat_count',n/4,'expected_results',4, ...
    'input_format','unsigned decimal U32; low16=I two-complement, high16=Q two-complement', ...
    'result_words_per_record',9,'default_epoch',0,'source_sha256',sourceHash, ...
    'schedule','1024-word Host chunks; wait accepted_samples; then wait at least 1 ms', ...
    'note',generationNote,'new_rtl_simulation_run',false,'board_test_run',false);
write_json(fullfile(outputDir,'manifest.json'),info);
fig = figure('Visible','off','Color','w','Position',[100 100 1200 700]);
cleanupFig = onCleanup(@()close(fig)); %#ok<NASGU>
tiledlayout(2,1);
nexttile; plot(timeUs,double(iCodes)); hold on; plot(timeUs,double(qCodes));
for k=1:4, xline(trueStart(k)/500e6*1e6,'--'); end
xlabel('Signal time (us), excluding DMA pauses'); ylabel('Signed I16 / Q16 codes');
legend('I','Q','Location','best'); grid on; title(['Input waveform: ' mode]);
nexttile; plot(timeUs,hypot(double(iCodes),double(qCodes))); grid on;
for k=1:4, xline(trueStart(k)/500e6*1e6,'--'); end
xlabel('Signal time (us), excluding DMA pauses'); ylabel('Magnitude (integer codes)');
exportgraphics(fig,fullfile(outputDir,'input_waveform.png'),'Resolution',140);
disp(info);
end
function value = get_option(s,name,default)
if isfield(s,name), value=s.(name); else, value=default; end
end
function words = noise_words(n,peak)
iv=int16(randi([-peak peak],n,1)); qv=int16(randi([-peak peak],n,1));
words=pack_iq(iv,qv);
end
function words = pack_iq(iv,qv)
iu=reshape(typecast(iv(:),'uint16'),[],1);
qu=reshape(typecast(qv(:),'uint16'),[],1);
words=bitor(uint32(iu),bitshift(uint32(qu),16));
end
function words = read_hex_beats(path)
rows=strip(readlines(path)); rows=rows(strlength(rows)>0);
assert(all(strlength(rows)==32),'Every reference beat must have 32 hex digits');
chars=char(rows);
assert(all(ismember(lower(chars(:)),'0123456789abcdef')),'Invalid hex input');
words=zeros(numel(rows)*4,1,'uint32');
for lane=0:3
    first=25-8*lane;
    words(lane+1:4:end)=uint32(hex2dec(chars(:,first:first+7)));
end
end
function hash = sha256_file(path)
fid=fopen(path,'rb'); assert(fid>=0,'Cannot open reference file');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes=fread(fid,Inf,'*uint8');
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(bytes,'int8'));
digest=typecast(md.digest(),'uint8');
hash=lower(reshape(dec2hex(digest,2).',1,[]));
end
function write_json(path,value)
fid=fopen(path,'w','n','UTF-8'); assert(fid>=0,'Cannot write JSON');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
