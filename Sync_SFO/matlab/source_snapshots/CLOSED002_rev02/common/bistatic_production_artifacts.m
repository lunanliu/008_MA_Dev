function artifacts = bistatic_production_artifacts(cfg, repoRoot)
%BISTATIC_PRODUCTION_ARTIFACTS Load and validate T02 production artifacts.

if nargin < 2 || isempty(repoRoot)
    if ~isfield(cfg, 'source_path')
        error('bistatic:T02RepoRoot', ...
            'repoRoot is required when the configuration has no source_path.');
    end
    repoRoot = fileparts(fileparts(cfg.source_path));
end
if ~isfield(cfg, 't02') || ~isfield(cfg.t02, 'artifact_relative_path')
    error('bistatic:T02Config', 'The canonical config has no T02 artifact path.');
end
relativePath = strrep(char(cfg.t02.artifact_relative_path), '/', filesep);
artifactPath = fullfile(repoRoot, relativePath);
if ~isfile(artifactPath)
    error('bistatic:T02ArtifactMissing', ...
        'T02 production artifact is missing: %s', artifactPath);
end

loaded = load(artifactPath);
required = {'artifact_metadata', 'preamble_fd', ...
    'pilot_mask_active_by_payload', 'pilot_values_active_by_payload'};
for index = 1:numel(required)
    if ~isfield(loaded, required{index})
        error('bistatic:T02ArtifactField', ...
            'T02 artifact is missing field %s.', required{index});
    end
end
if ~strcmp(loaded.artifact_metadata.config_sha256, cfg.sha256)
    error('bistatic:T02ArtifactConfigHash', ...
        'T02 artifact config hash does not match the loaded canonical config.');
end

nfft = cfg.frame.fft_length;
nPreamble = cfg.frame.preamble_symbols;
nActive = cfg.frame.active_subcarriers;
nPayload = cfg.frame.payload_symbols;
if ~isequal(size(loaded.preamble_fd), [nfft, nPreamble]) || ...
        ~isequal(size(loaded.pilot_mask_active_by_payload), [nActive, nPayload]) || ...
        ~isequal(size(loaded.pilot_values_active_by_payload), [nActive, nPayload])
    error('bistatic:T02ArtifactShape', 'T02 production artifact shape is invalid.');
end
if any(abs(loaded.pilot_values_active_by_payload(...
        loaded.pilot_mask_active_by_payload)) < eps)
    error('bistatic:T02PilotValue', 'A selected payload pilot has zero amplitude.');
end

artifacts.artifact_class = 't02_production_preamble_pilot';
artifacts.production_allowed = true;
artifacts.resolved_by = 'T02';
artifacts.description = loaded.artifact_metadata.description;
artifacts.preamble_fd = loaded.preamble_fd;
artifacts.pilot_mask_active_by_payload = loaded.pilot_mask_active_by_payload;
artifacts.pilot_values_active_by_payload = loaded.pilot_values_active_by_payload;
artifacts.metadata = loaded.artifact_metadata;
artifacts.source_path = artifactPath;
end
