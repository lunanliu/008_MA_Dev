function waveform = bistatic_generate_continuous_waveform(cfg, numberOfFrames, baseSeed, artifacts, options)
%BISTATIC_GENERATE_CONTINUOUS_WAVEFORM Generate zero-gap frames with true halo.

if nargin < 5
    options = struct();
end
if ~isfield(options, 'allow_nonproduction_artifacts')
    options.allow_nonproduction_artifacts = false;
end
if ~isfield(options, 'halo_samples')
    options.halo_samples = cfg.continuous_waveform.default_halo_each_side_samples;
end
if ~isfield(options, 'first_frame_id')
    options.first_frame_id = 0;
end
if numberOfFrames < 1 || numberOfFrames ~= floor(numberOfFrames)
    error('bistatic:FrameCount', 'numberOfFrames must be a positive integer.');
end
if options.halo_samples < cfg.continuous_waveform.minimum_pre_t07_halo_each_side_samples || ...
        options.halo_samples > cfg.frame.frame_samples
    error('bistatic:HaloRange', 'Halo must cover the pre-T07 lower bound and fit in one adjacent frame.');
end
if ~artifacts.production_allowed && ~options.allow_nonproduction_artifacts
    error('bistatic:NonProductionArtifacts', ...
        'T01 fixture artifacts are forbidden in production mode; supply T02 artifacts.');
end

firstId = options.first_frame_id;
lastId = firstId + numberOfFrames - 1;
previousFrame = bistatic_generate_frame(cfg, firstId - 1, baseSeed, artifacts);
nextFrame = bistatic_generate_frame(cfg, lastId + 1, baseSeed, artifacts);
nominal = complex(zeros(numberOfFrames * cfg.frame.frame_samples, 1));
for frameOffset = 0:numberOfFrames - 1
    destination = frameOffset * cfg.frame.frame_samples + (1:cfg.frame.frame_samples);
    nominal(destination) = bistatic_generate_frame(cfg, firstId + frameOffset, baseSeed, artifacts);
end

h = options.halo_samples;
waveform.samples = [previousFrame(end - h + 1:end); nominal; nextFrame(1:h)];
waveform.global_first_sample = -h;
waveform.global_last_sample = numberOfFrames * cfg.frame.frame_samples + h - 1;
waveform.nominal_start_index = h + 1;
waveform.nominal_sample_count = numberOfFrames * cfg.frame.frame_samples;
waveform.nominal_end_index = h + waveform.nominal_sample_count;
waveform.frame_start_indices = h + 1 + (0:numberOfFrames - 1) * cfg.frame.frame_samples;
waveform.frame_ids = firstId:lastId;
waveform.previous_guard_frame_id = firstId - 1;
waveform.next_guard_frame_id = lastId + 1;
waveform.halo_each_side_samples = h;
waveform.halo_source = 'true_adjacent_generated_frames';
waveform.zero_gap = true;
waveform.base_seed = baseSeed;
waveform.artifact_class = artifacts.artifact_class;
waveform.production_artifacts = artifacts.production_allowed;
waveform.config_sha256 = cfg.sha256;
end
