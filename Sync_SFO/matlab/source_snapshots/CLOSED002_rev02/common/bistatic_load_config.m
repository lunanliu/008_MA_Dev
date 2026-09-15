function cfg = bistatic_load_config(configPath)
%BISTATIC_LOAD_CONFIG Load and validate the canonical machine-readable config.

if nargin < 1 || isempty(configPath)
    error('bistatic:ConfigPathRequired', 'A canonical config path is required.');
end
raw = fileread(configPath);
cfg = jsondecode(raw);
cfg.source_path = char(configPath);
cfg.sha256 = bistatic_sha256(raw, false);
cfg.derived_validation = bistatic_validate_config(cfg);
end
