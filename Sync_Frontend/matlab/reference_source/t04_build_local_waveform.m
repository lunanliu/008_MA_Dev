function [waveform, channelDescriptor] = t04_build_local_waveform( ...
        cfg, artifacts, frameId, baseSeed)
%T04_BUILD_LOCAL_WAVEFORM Build true-adjacent local PS1/PS2 input context.

preSamples = 4096;
postSamples = 8192;
previous = bistatic_generate_frame(cfg, frameId - 1, baseSeed, artifacts);
current = bistatic_generate_frame(cfg, frameId, baseSeed, artifacts);
if preSamples > numel(previous) || postSamples > numel(current)
    error('bistatic:T04LocalWindow', 'Requested local window exceeds a frame.');
end
waveform.samples = [previous(end-preSamples+1:end); current(1:postSamples)];
waveform.global_first_sample = -preSamples;
waveform.global_last_sample = postSamples - 1;
waveform.nominal_start_index = preSamples + 1;
waveform.nominal_end_index = preSamples + 2 * ...
    cfg.frame.symbol_samples_with_cp;
waveform.expected_frame_start_sample = 0;
waveform.frame_id = frameId;
waveform.frame_ids = double(frameId);
waveform.base_seed = baseSeed;
waveform.artifact_class = artifacts.artifact_class;
waveform.production_artifacts = artifacts.production_allowed;
waveform.config_sha256 = cfg.sha256;
waveform.pre_samples = preSamples;
waveform.post_samples = postSamples;
waveform.halo_source = 'true_previous_frame_tail';
if nargout > 1
    descriptorOptions.mode = 'production';
    descriptorOptions.frame_ids = double(frameId);
    descriptorOptions.base_seed = double(baseSeed);
    descriptorOptions.anchor_frame_id = double(frameId);
    descriptorOptions.config_sha256 = cfg.sha256;
    descriptorOptions.waveform_numeric_sha256 = ...
        bistatic_waveform_numeric_sha256(waveform);
    descriptorOptions.requested_global_range = ...
        [waveform.global_first_sample, waveform.global_last_sample];
    descriptorOptions.context_frame_ids = double(frameId) + (-1:1);
    frameSamples = double(cfg.frame.frame_samples);
    descriptorOptions.context_global_range = ...
        [-frameSamples, 2 * frameSamples - 1];
    channelDescriptor = bistatic_make_cp_ofdm_descriptor( ...
        cfg, artifacts, descriptorOptions);
end
end
