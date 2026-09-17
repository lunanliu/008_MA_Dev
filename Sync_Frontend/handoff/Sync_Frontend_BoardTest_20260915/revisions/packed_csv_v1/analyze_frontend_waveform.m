function stats = analyze_frontend_waveform(inputDir, outputDir)
%ANALYZE_FRONTEND_WAVEFORM Explain the input IQ and its repeated-preamble metric.
% This is floating-point visualization, not the autonomous RTL golden model.
root=fileparts(mfilename('fullpath'));
if nargin<1 || isempty(inputDir), inputDir=fullfile(root,'data','baseline'); end
if nargin<2 || isempty(outputDir)
    outputDir=fullfile(inputDir,['waveform_analysis_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
end
if isfolder(outputDir)
    entries=dir(outputDir);
    assert(~any(~ismember({entries.name},{'.','..'})),'Choose a new, empty analysis directory');
else, mkdir(outputDir);
end
manifest=jsondecode(fileread(fullfile(inputDir,'manifest.json')));
raw=readmatrix(fullfile(inputDir,'input_dma_u32.csv'));
assert(size(raw,2)==1 && all(isfinite(raw) & raw==fix(raw) & raw>=0 & raw<=2^32-1));
words=uint32(raw);
iv=reshape(typecast(uint16(bitand(words,uint32(65535))),'int16'),[],1);
qv=reshape(typecast(uint16(bitshift(words,-16)),'int16'),[],1);
x=complex(double(iv),double(qv));
truth=readtable(fullfile(inputDir,'expected_truth.csv'));
fs=manifest.sample_rate_hz; lag=1024; window=1024;
assert(numel(x)>=lag+window);
% P(n)=sum(conj(x(n+k))*x(n+k+lag)), k=0..window-1.
pairs=conj(x(1:end-lag)).*x(1+lag:end);
early=abs(x(1:end-lag)).^2; late=abs(x(1+lag:end)).^2;
p=window_sum(pairs,window); e1=window_sum(early,window); e2=window_sum(late,window);
metric=abs(p).^2./max(e1.*e2,eps);
coarseCfo=angle(p)*fs/(2*pi*lag);
startIndex=(0:numel(metric)-1).';
trace=table(startIndex,metric,coarseCfo,e1,e2, ...
    'VariableNames',{'window_start_0','normalized_repetition_metric','phase_cfo_hz','early_energy','late_energy'});
writetable(trace,fullfile(outputDir,'repetition_metric.csv'));
locations=double(truth.fine_absolute_truth)+1;
assert(all(locations<=numel(metric)));
atTruth=table(truth.rx_frame_id,truth.fine_absolute_truth,truth.cfo_truth_hz, ...
    coarseCfo(locations),metric(locations), ...
    'VariableNames',{'rx_frame_id','truth_start_0','truth_cfo_hz','phase_cfo_at_truth_hz','metric_at_truth'});
writetable(atTruth,fullfile(outputDir,'metric_at_known_positions.csv'));
stats=struct('sample_count',numel(words),'sample_rate_hz',fs, ...
    'signal_duration_us',numel(words)/fs*1e6,'rms_complex_code',sqrt(mean(abs(x).^2)), ...
    'peak_complex_code',max(abs(x)), ...
    'component_rail_count',nnz(iv==32767 | iv==-32768)+nnz(qv==32767 | qv==-32768), ...
    'phase_cfo_unambiguous_magnitude_hz',fs/(2*lag), ...
    'note','Floating visualization only; metric at truth positions is NOT an autonomous detection test.');
fid=fopen(fullfile(outputDir,'waveform_stats.json'),'w','n','UTF-8'); assert(fid>=0);
fprintf(fid,'%s\n',jsonencode(stats,'PrettyPrint',true)); fclose(fid);
fig=figure('Visible','off','Color','w','Position',[100 100 1200 900]);
cleanupFig=onCleanup(@()close(fig)); %#ok<NASGU>
tiledlayout(3,1);
nexttile; plot((0:numel(x)-1)/fs*1e6,abs(x)); ylabel('IQ magnitude (codes)'); grid on;
title('Input signal and an explanatory floating-point repetition metric');
nexttile; plot(startIndex/fs*1e6,metric); ylabel('Normalized repetition metric'); grid on;
for k=1:height(truth), xline(double(truth.fine_absolute_truth(k))/fs*1e6,'--'); end
nexttile;
strong=metric>=0.5;
plot(startIndex(strong)/fs*1e6,coarseCfo(strong)/1000,'.'); hold on;
plot(double(truth.fine_absolute_truth)/fs*1e6,truth.cfo_truth_hz/1000,'rx','MarkerSize',10);
xlabel('Signal time (us), excluding DMA pauses'); ylabel('Phase CFO (kHz)'); grid on;
exportgraphics(fig,fullfile(outputDir,'waveform_analysis.png'),'Resolution',140);
disp(stats);
end
function y=window_sum(x,n)
s=cumsum([0;x(:)]);
y=s(n+1:end)-s(1:end-n);
end
