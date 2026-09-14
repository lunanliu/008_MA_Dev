function summary = t06_compact14_generate_data(repoRoot,fixtureRoot)
%T06_COMPACT14_GENERATE_DATA Build bounded fixtures for one XSim campaign.
% Generate only PS1--PS10 plus the PS11 boundary owner.  C13 and C14 reuse
% the twelve physical fixtures created for the isolated C01--C12 cases.
arguments
    repoRoot (1,:) char
    fixtureRoot (1,:) char
end
repoRoot=char(java.io.File(repoRoot).getCanonicalPath());
fixtureRoot=char(java.io.File(fixtureRoot).getCanonicalPath());
assert(startsWith(lower(fixtureRoot),lower([repoRoot filesep])), ...
    'bistatic:T06CompactPath','fixtureRoot must be inside the repository.');
addpath(fullfile(repoRoot,'matlab','common'));
addpath(fullfile(repoRoot,'matlab','tasks','T02_frame_design'));
addpath(fullfile(repoRoot,'matlab','tasks','T04_coarse_sync'));
addpath(fullfile(repoRoot,'matlab','tasks','T06_initial_sfo'));
if isfolder(fixtureRoot) && ~isempty(dir(fullfile(fixtureRoot,'case_*')))
    error('bistatic:T06CompactOverwrite','Existing fixtures will not be replaced.');
end
if ~isfolder(fixtureRoot),mkdir(fixtureRoot);end
cfg=bistatic_load_config(fullfile(repoRoot,'config','frame_config.json'));
assert(cfg.frame.fft_length==2048 && cfg.frame.cyclic_prefix_samples==512 && ...
    cfg.frame.symbol_samples_with_cp==2560 && cfg.frame.preamble_symbols==10);
scale=263403.20193827286; captureFirst=5272; captureLast=25959;
captureSamples=captureLast-captureFirst+1;
assert(captureSamples==20688 && mod(captureSamples,4)==0);
definitions=compactDefinitions();
assert(numel(definitions)==12 && nnz([definitions.numeric_valid])==11);
indexRows=repmat(emptyIndexRow(),12,1); caseSummaries=cell(12,1);
for oneBased=1:12
    caseIndex=oneBased-1; d=definitions(oneBased);
    caseRoot=fullfile(fixtureRoot,sprintf('case_%03d',caseIndex));
    assert(~isfolder(caseRoot),'Destination already exists: %s',caseRoot);mkdir(caseRoot);
    bank=t06_build_bounded_ps1_ps10_owner_bank(cfg,repoRoot,d.frame_id,90401);
    % PS11 exists only as owner-safe guard for queries beyond PS10.
    bank.last_output_global_sample=captureLast;
    bank.coverage='PS1_useful_start_through_capture_last_with_PS11_owner_guard';
    profile=bistatic_channel_profile(d.channel,cfg,d.channel_seed);
    impairment=struct('to_clock_samples',d.to_clock, ...
        'propagation_delay_samples',d.propagation_delay, ...
        'cfo_oscillator_hz',d.total_cfo_hz,'los_doppler_hz',0, ...
        'sfo_ppm',d.sfo_true_ppm,'noise_enabled',isfinite(d.snr_db), ...
        'snr_db',d.snr_db,'noise_reference','reference_los_tap');
    received=t06_apply_bounded_cp_ofdm_channel(bank,cfg,impairment,profile,d.noise_seed);
    assert(received.global_first_sample==512 && received.global_last_sample==captureLast && ...
        numel(received.samples)==captureLast-512+1);
    q=t04_quantize_receiver_i16(received.samples,scale);
    globalSample=int32((captureFirst:captureLast).');
    sourceIndex=double(globalSample)-received.global_first_sample+1;
    rawI=q.i(sourceIndex);rawQ=q.q(sourceIndex);
    assert(isa(rawI,'int16') && isa(rawQ,'int16') && numel(rawI)==captureSamples);
    if d.numeric_valid
        publicCfo=int32(d.coarse_cfo_hz);publicFine=int32(d.fine_start);
        residualCfo=d.total_cfo_hz-double(publicCfo);
        phaseIncrement=int32(t02_round_even(double(publicCfo)/ ...
            double(cfg.signal.sample_rate_hz)*2^32));
        cfoStatus='2800';fineStatus='3800';serviceStatus='4800';
    else
        publicCfo=int32(0);publicFine=int32(0);phaseIncrement=int32(0);
        residualCfo=NaN;
        cfoStatus='2400';fineStatus='3402';serviceStatus='4402';
    end
    context=struct('schema','t06_compact14_case_context_v1', ...
        'case_index_zero_based',caseIndex,'scenario_id',d.scenario_id, ...
        'case_id',d.case_id,'role',d.role,'frame_id',uint32(d.frame_id), ...
        'coarse_cfo_hz',publicCfo,'fine_start',publicFine, ...
        'phase_increment',phaseIncrement,'numeric_valid',logical(d.numeric_valid), ...
        'capture_first',captureFirst,'capture_last',captureLast, ...
        'capture_origin',captureFirst,'capture_beats',captureSamples/4, ...
        'received_global_first_sample',received.global_first_sample, ...
        'received_global_last_sample',received.global_last_sample, ...
        'integer_per_unit',scale,'channel',d.channel,'snr_db',d.snr_db, ...
        'channel_seed',d.channel_seed,'noise_seed',d.noise_seed, ...
        'sfo_true_ppm',d.sfo_true_ppm,'total_cfo_hz',d.total_cfo_hz, ...
        'residual_cfo_hz',residualCfo, ...
        'residual_cfo_defined',logical(d.numeric_valid), ...
        'supported_accuracy',logical(d.supported_accuracy), ...
        'characterization_only',logical(d.characterization_only), ...
        'public_cfo_status_hex',cfoStatus,'public_fine_status_hex',fineStatus, ...
        'expected_service_status_hex',serviceStatus, ...
        'full_received_frame_generated',false, ...
        'generated_owner_keys',double(bank.owner_keys(:).'), ...
        'interpolation_method',bank.interpolation_method);
    save(fullfile(caseRoot,'raw_window.mat'),'rawI','rawQ','globalSample','context','-v7');
    writeCaptureMem(fullfile(caseRoot,'capture.mem'),rawI,rawQ);
    writeJson(fullfile(caseRoot,'context.json'),context);
    writeContextText(fullfile(caseRoot,'context.txt'),context);
    writeTbExpect(fullfile(caseRoot,'tb_expect.txt'),context);
    one=struct('schema','t06_compact14_case_fixture_v1', ...
        'status','COMPACT_CASE_DATA_GENERATION_COMPLETE', ...
        'case_index_zero_based',caseIndex,'scenario_id',d.scenario_id, ...
        'case_id',d.case_id,'saved_raw_samples',captureSamples, ...
        'capture_beats',captureSamples/4,'capture_range',[captureFirst captureLast], ...
        'bounded_received_range',[received.global_first_sample received.global_last_sample], ...
        'generated_complete_frame_count',bank.generated_complete_frame_count, ...
        'generated_payload_symbol_count',bank.generated_payload_symbol_count, ...
        'receiver_clip_component_count',q.clip_component_count, ...
        'receiver_maximum_abs_code',max(abs([double(rawI);double(rawQ)])), ...
        'capture_mem_sha256',bistatic_sha256(fullfile(caseRoot,'capture.mem'),true), ...
        'raw_mat_sha256',bistatic_sha256(fullfile(caseRoot,'raw_window.mat'),true), ...
        'context_sha256',bistatic_sha256(fullfile(caseRoot,'context.json'),true), ...
        'mathematical_bittrue_executed',false,'rtl_executed',false, ...
        't06_pass_claimed',false);
    writeJson(fullfile(caseRoot,'fixture_summary.json'),one);
    caseSummaries{oneBased}=one;indexRows(oneBased)=makeIndexRow(caseIndex,d,context);
    fprintf('T06_COMPACT_DATA case=%s index=%d samples=%d beats=%d\n', ...
        d.scenario_id,caseIndex,captureSamples,captureSamples/4);
end
writetable(struct2table(indexRows),fullfile(fixtureRoot,'index.csv'));
writeCases(fullfile(fixtureRoot,'cases.txt'),indexRows);
writeRunPlan(fullfile(fixtureRoot,'run_plan.txt'),cfg);
summary=struct('schema','t06_compact14_fixture_set_v1', ...
    'status','COMPACT14_FIXTURE_GENERATION_COMPLETE', ...
    'physical_fixture_count',12,'numeric_fixture_count',11, ...
    'outage_fixture_count',1,'logical_scenario_count',14, ...
    'isolated_case_indices',0:11,'continuous_reuse_case_indices',[3 1 5], ...
    'protocol_reuse_case_index',1, ...
    'continuous_frame_interval_cycles',double(cfg.frame.cycles_per_frame_125mhz), ...
    'capture_samples_per_fixture',captureSamples, ...
    'capture_beats_per_fixture',captureSamples/4, ...
    'bounded_bank_range',[512 captureLast],'integer_per_unit',scale, ...
    'full_received_frame_generated',false,'mathematical_bittrue_executed',false, ...
    'rtl_executed',false,'t06_pass_claimed',false,'cases',{caseSummaries});
writeJson(fullfile(fixtureRoot,'fixture_summary.json'),summary);
fprintf('T06_COMPACT14_FIXTURE_GENERATION_COMPLETE physical=12 logical=14\n');
end

function d=compactDefinitions()
t=struct('scenario_id','','case_id','','role','','channel','single_path', ...
    'snr_db',Inf,'channel_seed',0,'noise_seed',0,'frame_id',0, ...
    'to_clock',0,'propagation_delay',0,'sfo_true_ppm',0, ...
    'total_cfo_hz',100000,'coarse_cfo_hz',100000,'fine_start',0, ...
    'numeric_valid',true,'supported_accuracy',true,'characterization_only',false);
d=repmat(t,12,1);
d(1)=setCase(t,'C01','single_noiseless_sfo_m150','deterministic','single_path',Inf,61001,-150,100000,100000,0,true,true,false);
d(2)=setCase(t,'C02','single_noiseless_sfo_000','deterministic','single_path',Inf,61002,0,100000,100000,0,true,true,false);
d(3)=setCase(t,'C03','single_noiseless_sfo_p150','deterministic','single_path',Inf,61003,150,100000,100000,0,true,true,false);
d(4)=setCase(t,'C04','tdld_10dB_sfo_m150_residual_m1k','acceptance','tdl_d_los_30ns',10,41007,-150,100000,101000,67,true,true,false);
d(5)=setCase(t,'C05','tdld_10dB_sfo_000_residual_0','acceptance','tdl_d_los_30ns',10,41007,0,100000,100000,67,true,true,false);
d(6)=setCase(t,'C06','tdld_10dB_sfo_p150_residual_p1k','acceptance','tdl_d_los_30ns',10,41007,150,100000,99000,67,true,true,false);
d(7)=setCase(t,'C07','tdld_20dB_sfo_p100','acceptance','tdl_d_los_30ns',20,41007,100,100000,100000,67,true,true,false);
d(8)=setCase(t,'C08','paper_15dB_sfo_p100','acceptance','paper_offset_snr_project_grid_fixture',15,31008,100,100000,100000,67,true,true,false);
d(9)=setCase(t,'C09','tdld_05dB_sfo_p100','characterization','tdl_d_los_30ns',5,41003,100,100000,100000,67,true,false,true);
d(10)=setCase(t,'C10','tdld_00dB_sfo_p100','characterization','tdl_d_los_30ns',0,41003,100,100000,100000,67,true,false,true);
% C11 retains the prior T04 handoff that produced shared-gain activation.
d(11)=setCase(t,'C11','tdld_m05dB_seed41006_shared_gain','characterization','tdl_d_los_30ns',-5,41006,100,100000,101933,67,true,false,true);
d(12)=setCase(t,'C12','tdld_m05dB_seed41003_outage','approved_outage','tdl_d_los_30ns',-5,41003,100,100000,0,67,false,false,true);
for k=1:numel(d)
    d(k).frame_id=6000+k;
    d(k).to_clock=double(~strcmp(d(k).channel,'single_path'))*67;
end
end
function v=setCase(v,id,name,role,channel,snr,seed,sfo,total,coarse,fine,numeric,supported,characterization)
v.scenario_id=id;v.case_id=name;v.role=role;v.channel=channel;v.snr_db=snr;
v.channel_seed=seed;v.noise_seed=seed;v.sfo_true_ppm=sfo;
v.total_cfo_hz=total;v.coarse_cfo_hz=coarse;v.fine_start=fine;
v.numeric_valid=numeric;v.supported_accuracy=supported;
v.characterization_only=characterization;
end
function row=emptyIndexRow()
row=struct('case_index_zero_based',0,'scenario_id','','case_id','', ...
    'frame_id',0,'numeric_valid',0,'supported_accuracy',0, ...
    'characterization_only',0,'channel','','snr_db',0,'channel_seed',0, ...
    'sfo_true_ppm',0,'total_cfo_hz',0,'coarse_cfo_hz',0, ...
    'residual_cfo_hz',0,'residual_cfo_defined',0, ...
    'fine_start',0,'case_directory','', ...
    'expected_service_status_hex','');
end
function row=makeIndexRow(index,d,c)
row=emptyIndexRow();row.case_index_zero_based=index;row.scenario_id=d.scenario_id;
row.case_id=d.case_id;row.frame_id=d.frame_id;row.numeric_valid=double(d.numeric_valid);
row.supported_accuracy=double(d.supported_accuracy);
row.characterization_only=double(d.characterization_only);row.channel=d.channel;
row.snr_db=d.snr_db;row.channel_seed=d.channel_seed;row.sfo_true_ppm=d.sfo_true_ppm;
row.total_cfo_hz=d.total_cfo_hz;row.coarse_cfo_hz=double(c.coarse_cfo_hz);
row.residual_cfo_hz=c.residual_cfo_hz;
row.residual_cfo_defined=double(c.residual_cfo_defined);
row.fine_start=double(c.fine_start);
row.case_directory=sprintf('case_%03d',index);
row.expected_service_status_hex=c.expected_service_status_hex;
end
function writeCaptureMem(path,iValues,qValues)
iBits=reshape(typecast(iValues(:),'uint16'),4,[]);
qBits=reshape(typecast(qValues(:),'uint16'),4,[]);
fid=fopen(path,'wt');assert(fid>=0,'Cannot create %s.',path);guard=onCleanup(@()fclose(fid));
for beat=1:size(iBits,2)
    for lane=4:-1:1,fprintf(fid,'%04X%04X',qBits(lane,beat),iBits(lane,beat));end
    fprintf(fid,'\n');
end
clear guard
end
function writeContextText(path,c)
fid=fopen(path,'wt');assert(fid>=0,'Cannot create %s.',path);guard=onCleanup(@()fclose(fid));
fprintf(fid,'%u %d %d %d %d\n',c.frame_id,c.coarse_cfo_hz,c.fine_start,c.phase_increment,c.numeric_valid);clear guard
end
function writeTbExpect(path,c)
fid=fopen(path,'wt');assert(fid>=0,'Cannot create %s.',path);guard=onCleanup(@()fclose(fid));
fprintf(fid,'%u %d %s\n',c.frame_id,c.numeric_valid,c.expected_service_status_hex);
fprintf(fid,'FRAME_ID %u\n',c.frame_id);
fprintf(fid,'NUMERIC_VALID %d\n',c.numeric_valid);
fprintf(fid,'EXPECTED_SERVICE_STATUS_HEX %s\n',c.expected_service_status_hex);
fprintf(fid,'TRUE_SFO_PPM %.17g\n',c.sfo_true_ppm);
fprintf(fid,'RESIDUAL_CFO_HZ %.17g\n',c.residual_cfo_hz);
fprintf(fid,'SUPPORTED_ACCURACY %d\n',c.supported_accuracy);
fprintf(fid,'CHARACTERIZATION_ONLY %d\n',c.characterization_only);
clear guard
end
function writeCases(path,rows)
fid=fopen(path,'wt');assert(fid>=0,'Cannot create %s.',path);guard=onCleanup(@()fclose(fid));
for k=1:numel(rows),fprintf(fid,'%d %d %d\n',rows(k).case_index_zero_based,rows(k).frame_id,rows(k).numeric_valid);end
clear guard
end
function writeRunPlan(path,cfg)
fid=fopen(path,'wt');assert(fid>=0,'Cannot create %s.',path);guard=onCleanup(@()fclose(fid));
fprintf(fid,'T06_COMPACT14_RUN_PLAN_V1\n');
fprintf(fid,'ISOLATED 0 1 2 3 4 5 6 7 8 9 10 11\n');
fprintf(fid,'CONTINUOUS 3 1 5\n');
fprintf(fid,'PROTOCOL 1\n');
fprintf(fid,'FRAME_INTERVAL_CYCLES %d\n',cfg.frame.cycles_per_frame_125mhz);
fprintf(fid,'EVALUATION_DEFERRED 1\n');clear guard
end
function writeJson(path,value)
fid=fopen(path,'wt');assert(fid>=0,'Cannot create %s.',path);guard=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));clear guard
end
