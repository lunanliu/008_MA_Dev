function summary=t09_closed002_rev02(packageRoot,outputDir)
%T09_CLOSED002 Reuse actual T06 RTL estimates on identical noiseless input.
% Full-span MATLAB only; no new T06/T08 RTL or T10 implementation.
assert(strcmp(version('-release'),'2024a') && isfolder(outputDir));
assert(~isfile(fullfile(outputDir,'completion.json')));
started=tic;caseId=0;stage='identity';
try
    addpath(fullfile(packageRoot,'common'));addpath(fullfile(packageRoot,'helpers'));
    manifest=jsondecode(fileread(fullfile(packageRoot,'manifest.json')));
    for ii=1:numel(manifest.files)
        f=manifest.files(ii);
        assert(strcmpi(bistatic_sha256(fullfile(packageRoot,f.path),true),f.sha256), ...
            'T09:HashMismatch','Frozen file changed: %s',f.path);
    end
    cfg=bistatic_load_config(fullfile(packageRoot,'config','frame_config.json'));
    artifacts=bistatic_production_artifacts(cfg,packageRoot);
    N=cfg.frame.frame_samples;assert(N==1336320);
    profile=struct('coefficient_bits',14,'data_bits',16,'mu_bits',8,'ratio_bits',28);
    pilotSymbols=(0:7:511).';times=(10+pilotSymbols)*2560+384+1023.5;
    active=bistatic_active_indices(cfg);k=active-1;k(k>=1024)=k(k>=1024)-2048;
    rows=find(mod(k,2)==0);k=k(rows);bins=active(rows);
    P=artifacts.pilot_values_active_by_payload(rows,pilotSymbols+1);
    admission=cell(4,1);
    for ci=1:4
        root=fullfile(packageRoot,'upstream',sprintf('C%02d',ci));
        c=jsondecode(fileread(fullfile(root,'context.json')));
        opts=detectImportOptions(fullfile(root,'service_result.csv'),'TextType','string');
        opts=setvartype(opts,{'Scenario','Subtest','ResultHex','Status'},'string');
        result=readtable(fullfile(root,'service_result.csv'),opts);
        assert(height(result)==1 && result.Seen==1 && result.FrameId==c.frame_id);
        h=char(result.ResultHex);assert(numel(h)==24);
        valueCode=hex2dec(h(1:8));if valueCode>=2^31,valueCode=valueCode-2^32;end
        ppm=valueCode/2^18;
        accepted=strcmp(char(result.Status),'4800') && c.numeric_valid && abs(ppm)<=150;
        admission{ci}=struct('case_id',ci,'frame_id',c.frame_id,'generation',1, ...
            'rtl_result_hex',h,'status_hex',char(result.Status),'value_q18',valueCode, ...
            'estimate_ppm',ppm,'physical_truth_ppm',c.sfo_true_ppm, ...
            'accepted_by_T08_value_contract',accepted,'clamped',false);
    end
    assert(all(cellfun(@(a)a.accepted_by_T08_value_contract,admission(1:3))) && ...
        ~admission{4}.accepted_by_T08_value_contract);
    writeJson(fullfile(outputDir,'upstream_admission.json'),struct('cases',{admission}, ...
        'C04_boundary_rejection_expected',true,'T06_partition_repaired',false));
    results=cell(3,1);
    for ci=1:3
        caseId=ci;folder=fullfile(outputDir,sprintf('case_%03d',ci));mkdir(folder);
        source=fullfile(packageRoot,'upstream',sprintf('C%02d',ci));
        c=jsondecode(fileread(fullfile(source,'context.json')));
        old=load(fullfile(source,'raw_window.mat'),'rawI','rawQ','globalSample','context');
        assert(isequal(c.frame_id,double(old.context.frame_id)) && strcmp(c.channel,'single_path'));
        trace=readtable(fullfile(source,'service_raw.csv'));
        traceIndex=double(trace.Abs)-double(old.globalSample(1))+1;
        assert(height(trace)==16384 && all(trace.Frame==c.frame_id) && ...
            numel(unique(trace.Abs))==16384 && min(traceIndex)>=1 && max(traceIndex)<=numel(old.rawI));
        assert(all(double(old.rawI(traceIndex))==trace.I) && all(double(old.rawQ(traceIndex))==trace.Q), ...
            'T09:RTLTraceIdentity','Saved fixture differs from actual RTL raw input trace.');
        fid=c.frame_id;generation=1;hat1=admission{ci}.estimate_ppm;
        writeJson(fullfile(outputDir,'progress.json'),struct('case_id',ci,'stage','generate_channel','elapsed_seconds',toc(started)));
        stage='generate_channel';timer=tic;
        wave=bistatic_generate_continuous_waveform(cfg,1,90401,artifacts, ...
            struct('first_frame_id',fid,'halo_samples',2048));
        options=struct('mode','production','frame_ids',fid,'base_seed',90401, ...
            'anchor_frame_id',fid,'config_sha256',cfg.sha256, ...
            'waveform_numeric_sha256',bistatic_waveform_numeric_sha256(wave), ...
            'requested_global_range',[wave.global_first_sample wave.global_last_sample], ...
            'context_frame_ids',[fid-1 fid fid+1],'context_global_range',[-N 2*N-1]);
        descriptor=bistatic_make_cp_ofdm_descriptor(cfg,artifacts,options);
        % Preserve exact complex data in MAT; JSON contains metadata only.
        descriptorPath=fullfile(folder,'source_descriptor.mat');
        save(descriptorPath,'descriptor','-v7.3');
        descriptorMetadata=rmfield(descriptor,'artifacts_snapshot');
        descriptorMetadata.artifacts_snapshot_storage=struct('file','source_descriptor.mat', ...
            'sha256',bistatic_sha256(descriptorPath,true),'field','descriptor.artifacts_snapshot');
        writeJson(fullfile(folder,'source_descriptor.json'),descriptorMetadata);
        reloaded=load(descriptorPath,'descriptor');
        assert(isequaln(reloaded.descriptor,descriptor),'T09:DescriptorRoundTrip', ...
            'Binary descriptor checkpoint does not round-trip exactly.');
        clear reloaded
        channel=bistatic_channel_profile(c.channel,cfg,c.channel_seed);
        impairment=struct('to_clock_samples',0,'propagation_delay_samples',0, ...
            'cfo_oscillator_hz',c.total_cfo_hz,'los_doppler_hz',0, ...
            'sfo_ppm',c.sfo_true_ppm,'noise_enabled',false,'snr_db',Inf, ...
            'noise_reference','reference_los_tap');
        received=bistatic_apply_cp_ofdm_channel(wave,cfg,impairment,channel,c.noise_seed,descriptor);
        quantized=t04_quantize_receiver_i16(received.samples,c.integer_per_unit);
        oldIndices=double(old.globalSample)-received.global_first_sample+1;
        mismatch=nnz(quantized.i(oldIndices)~=old.rawI)+nnz(quantized.q(oldIndices)~=old.rawQ);
        identity=struct('frame_id',fid,'generation',generation,'base_seed',90401, ...
            'rtl_raw_trace_components_checked',2*height(trace),'raw_overlap_samples',numel(old.rawI),'raw_overlap_component_mismatches',mismatch, ...
            'receiver_clip_components',quantized.clip_component_count, ...
            'channel_elapsed_seconds',toc(timer),'reference_descriptor',descriptorMetadata, ...
            'physical_truth',impairment,'upstream',admission{ci}, ...
            'T04_T05_context_source','Existing compact14 supplied public context; not fresh acquisition');
        % Commit raw samples before JSON or gate assertions so failure is recoverable.
        rawFirst=-172;rawCount=N+540;indices=rawFirst-received.global_first_sample+(1:rawCount);
        raw=complex(double(quantized.i(indices)),double(quantized.q(indices)))/32768;
        save(fullfile(folder,'raw_input.mat'),'raw','rawFirst','c','identity','-v7.3');
        writeJson(fullfile(folder,'raw_input_checkpoint.json'),struct('saved',true, ...
            'sha256',bistatic_sha256(fullfile(folder,'raw_input.mat'),true), ...
            'identity_gate_asserted',false,'raw_overlap_component_mismatches',mismatch));
        writeJson(fullfile(folder,'input_identity.json'),identity);
        assert(mismatch==0,'T09:UpstreamInputMismatch', ...
            'Regenerated source differs from actual T06 capture; no closed-loop claim permitted.');
        assert(quantized.clip_component_count==0,'T09:ReceiverClip','Unexpected receiver clipping.');

        clear wave received quantized old
        stage='first_resample';timer=tic;
        [y1,info1]=t07_fixed_arithmetic_window(raw,rawFirst,hat1*1e-6,-36,N+72,0,profile);
        clear raw
        step1=info1.step_integer/2^28;
        expectedStep=2^28+sign(admission{ci}.value_q18)* ...
            t02_round_even(abs(admission{ci}.value_q18)*16/15625);
        assert(info1.step_integer==expectedStep && numel(y1)==N+72);
        firstElapsed=toc(timer);
        save(fullfile(folder,'first_resampled.mat'),'y1','info1','step1','fid','generation','-v7.3');
        writeJson(fullfile(folder,'first_resample_complete.json'),struct('complete',true, ...
            'source_sha256',bistatic_sha256(fullfile(folder,'first_resampled.mat'),true), ...
            'elapsed_seconds',firstElapsed,'info',info1));
        stage='first_observe';
        [Q1,windows1]=extractPilots(y1,-36,P,bins,k,pilotSymbols,0);
        first=t09_dtp_float002(Q1,k,times);
        [Q1c,~]=extractPilots(y1,-36,P,bins,k,pilotSymbols,c.coarse_cfo_hz);
        firstCfoDiagnostic=t09_dtp_float002(Q1c,k,times);
        residual1=((1+c.sfo_true_ppm*1e-6)/step1-1)*1e6;
        correction=cell(2,1);
        for zi=1:2
            ei=2*zi;estimate=first(ei);z=estimate.padding;
            record=struct('padding',z,'method',estimate.method,'estimate_ppm',estimate.ppm, ...
                'estimate_valid',estimate.valid,'correction_executed',false, ...
                'primary_branch','A128 only; no added coarse-CFO correction', ...
                'post_rate_truth_ppm',NaN,'post_dtp_ppm',NaN,'post_dtp_valid',false, ...
                'post_local_cfo_diagnostic_ppm',NaN,'target_met',false);
            if estimate.valid
                stage=sprintf('second_resample_z%d',z);timer=tic;
                [y2,info2]=t07_fixed_arithmetic_window(y1,-36,estimate.ppm*1e-6,0,N,0,profile);
                step2=info2.step_integer/2^28;
                record.correction_executed=true;
                record.post_rate_truth_ppm=((1+c.sfo_true_ppm*1e-6)/(step1*step2)-1)*1e6;
                [Q2,windows2]=extractPilots(y2,0,P,bins,k,pilotSymbols,0);
                post=t09_dtp_float002(Q2,k,times);
                [Q2c,~]=extractPilots(y2,0,P,bins,k,pilotSymbols,c.coarse_cfo_hz);
                postCfoDiagnostic=t09_dtp_float002(Q2c,k,times);
                record.post_dtp_ppm=post(end).ppm;record.post_dtp_valid=post(end).valid;
                record.post_local_cfo_diagnostic_ppm=postCfoDiagnostic(end).ppm;
                record.target_met=abs(record.post_rate_truth_ppm)<0.1 && ...
                    record.post_dtp_valid && abs(record.post_dtp_ppm)<0.1 && ...
                    info1.total_saturated_components==0 && info2.total_saturated_components==0;
                record.second_resample_info=info2;record.elapsed_seconds=toc(timer);
                save(fullfile(folder,sprintf('second_z%d.mat',z)),'y2','info2','step2', ...
                    'Q2','windows2','post','postCfoDiagnostic','-v7.3');
                clear y2
                writeJson(fullfile(folder,sprintf('second_z%d_complete.json',z)),struct('complete',true, ...
                    'sha256',bistatic_sha256(fullfile(folder,sprintf('second_z%d.mat',z)),true),'record',record));
            end
            correction{zi}=record;
        end
        save(fullfile(folder,'first_nodes.mat'),'Q1','windows1','first','firstCfoDiagnostic', ...
            'pilotSymbols','times','k','bins','P','-v7');
        results{ci}=struct('case_id',ci,'frame_id',fid,'generation',generation, ...
            'input_identity',identity,'initial_residual_rate_truth_ppm',residual1, ...
            'first_info',info1,'first_estimates',first,'first_local_cfo_diagnostic',firstCfoDiagnostic, ...
            'corrections',{correction},'cfo_diagnostic_changes_production',false);
        writeJson(fullfile(folder,'result.json'),results{ci});
        writeJson(fullfile(outputDir,'progress.json'),struct('completed_cases',ci,'total_cases',3, ...
            'stage','case_complete','elapsed_seconds',toc(started)));
        fprintf('T09_CLOSED002_CASE %d/3 elapsed=%.3f\n',ci,toc(started));
    end
    summary=struct('schema','T09_CLOSED002_v1','status','BOUNDED_PHYSICAL_INPUT_RESEARCH_COMPLETE', ...
        'case_count',3,'admission_case_count',4,'results',{results},'elapsed_seconds',toc(started), ...
        'matlab_version',version,'actual_T06_RTL_estimates_reused',true, ...
        'actual_T06_capture_overlap_required',true,'resampler_model','Frozen T07 C14D16M8R28 integer oracle', ...
        'T08_RTL_executed',false,'T10_implemented',false,'T06_partition_repaired',false, ...
        'full_pilot_observation_count',74,'T09_PASS',false,'RTL_service_qualified',false);
    writeJson(fullfile(outputDir,'summary.json'),summary);
    writeJson(fullfile(outputDir,'code_analyzer.json'),struct('entry',checkcode(mfilename('fullpath'),'-id')));
    writeJson(fullfile(outputDir,'completion.json'),struct('complete',true,'T09_PASS',false));
catch err
    writeJson(fullfile(outputDir,'failure.json'),struct('case_id',caseId,'stage',stage, ...
        'identifier',err.identifier,'message',err.message, ...
        'report',getReport(err,'extended','hyperlinks','off'),'elapsed_seconds',toc(started)));
    rethrow(err);
end
end

function [Q,windows]=extractPilots(y,first,P,bins,k,symbols,cfo)
% All samples remain in true nominal coordinates; diagnostic CFO uses public estimate.
windows=complex(zeros(2048,74));Q=complex(zeros(820,74));
for jj=1:74
    coords=(10+symbols(jj))*2560+384+(0:2047).';
    indices=coords-first+1;assert(min(indices)>=1 && max(indices)<=numel(y));
    win=y(indices).*exp(-2j*pi*cfo*coords/500e6);
    windows(:,jj)=win;Y=fft(win);
    Q(:,jj)=Y(bins).*exp(2j*pi*k/16)./P(:,jj);
end
end

function writeJson(path,value)
% Encode before touching a file; commit only a complete UTF-8 JSON document.
payload=jsonencode(value,'PrettyPrint',true);
temporary=[path '.tmp'];
f=fopen(temporary,'w','n','UTF-8');assert(f>=0);guard=onCleanup(@()fclose(f));
fprintf(f,'%s',payload);clear guard
[ok,message]=movefile(temporary,path,'f');
assert(ok,'T09:JsonCommit','JSON commit failed: %s',message);
end



