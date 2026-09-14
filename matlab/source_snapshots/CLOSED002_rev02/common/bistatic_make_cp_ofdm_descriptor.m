function descriptor = bistatic_make_cp_ofdm_descriptor(cfg, artifacts, options)
%BISTATIC_MAKE_CP_OFDM_DESCRIPTOR Build a fail-closed project waveform contract.
% The descriptor binds a regenerable project CP-OFDM waveform to its config,
% artifact content, frame RNG identity, returned range, and real frame context.

requireScalarStruct(cfg, 'cfg');
requireScalarStruct(artifacts, 'artifacts');
requireScalarStruct(options, 'options');
requireFields(options, {'mode', 'frame_ids', 'base_seed', ...
    'anchor_frame_id', 'config_sha256', 'waveform_numeric_sha256', ...
    'requested_global_range', 'context_frame_ids', ...
    'context_global_range'}, 'options');

configInfo = validateConfiguration(cfg, options.config_sha256);
mode = textScalar(options.mode, 'options.mode');
if ~any(strcmp(mode, {'production', 'research'}))
    error('bistatic:CpOfdmDescriptorMode', ...
        'options.mode must be exactly production or research.');
end

frameIds = contiguousIntegerVector(options.frame_ids, ...
    'options.frame_ids', 'bistatic:CpOfdmDescriptorFrameIds');
contextFrameIds = contiguousIntegerVector(options.context_frame_ids, ...
    'options.context_frame_ids', ...
    'bistatic:CpOfdmDescriptorContextFrameIds');
baseSeed = boundedIntegerScalar(options.base_seed, 0, 2^31 - 1, ...
    'options.base_seed');
anchorFrameId = boundedIntegerScalar(options.anchor_frame_id, ...
    -(2^31), 2^31 - 1, 'options.anchor_frame_id');
if anchorFrameId ~= frameIds(1)
    error('bistatic:CpOfdmDescriptorAnchorFrame', ...
        'The anchor frame ID must equal the first nominal frame ID.');
end
if ~all(ismember(frameIds, contextFrameIds)) || ...
        ~ismember(frameIds(1) - 1, contextFrameIds) || ...
        ~ismember(frameIds(end) + 1, contextFrameIds)
    error('bistatic:CpOfdmDescriptorContextFrameIds', ...
        ['Context frame IDs must contain all nominal frames and their ' ...
        'immediate previous and next frames.']);
end

requestedRange = inclusiveIntegerRange(options.requested_global_range, ...
    'options.requested_global_range');
contextRange = inclusiveIntegerRange(options.context_global_range, ...
    'options.context_global_range');
frameSamples = configInfo.frame_samples;
expectedContextRange = [(contextFrameIds(1) - anchorFrameId) * frameSamples, ...
    (contextFrameIds(end) - anchorFrameId + 1) * frameSamples - 1];
if ~isequal(contextRange, expectedContextRange)
    error('bistatic:CpOfdmDescriptorContextRange', ...
        ['options.context_global_range must exactly cover every complete ' ...
        'declared context frame relative to the anchor frame.']);
end
if requestedRange(1) < contextRange(1) || ...
        requestedRange(2) > contextRange(2)
    error('bistatic:CpOfdmDescriptorRequestedRange', ...
        'The requested range is not fully covered by real declared context.');
end

waveformSha = sha256Text(options.waveform_numeric_sha256, ...
    'options.waveform_numeric_sha256');
artifactInfo = validateArtifacts(artifacts, cfg, mode, options);

symbolIds = repmat((0:configInfo.total_symbols - 1).', ...
    numel(contextFrameIds), 1);
symbolOwnerFrameIds = repelem(contextFrameIds(:), ...
    configInfo.total_symbols);
symbolCpStarts = (symbolOwnerFrameIds - anchorFrameId) * frameSamples + ...
    symbolIds * configInfo.symbol_samples;

descriptor.schema = 'bistatic_cp_ofdm_channel_descriptor_v1';
descriptor.schema_version = 1;
descriptor.signal_class = 'project_cp_ofdm';
descriptor.mode = mode;
descriptor.reference_method = ...
    'interpft_l128_barycentric8_boundary_direct_fourier';
descriptor.generic_fallback_allowed = false;
descriptor.pchip_fallback_allowed = false;
descriptor.config_source_path = configInfo.source_path;
descriptor.config_sha256 = configInfo.sha256;
descriptor.profile_id = configInfo.profile_id;
descriptor.artifact_class = artifactInfo.artifact_class;
descriptor.production_allowed = artifactInfo.production_allowed;
descriptor.artifact_source_kind = artifactInfo.source_kind;
descriptor.artifact_source_path = artifactInfo.source_path;
descriptor.artifact_sha256 = artifactInfo.source_sha256;
descriptor.artifact_content_sha256 = artifactInfo.content_sha256;
descriptor.artifact_component_sha256 = artifactInfo.component_sha256;
descriptor.artifact_content_sha256_serialization = ...
    artifactInfo.content_serialization;
descriptor.research_artifact_id = artifactInfo.research_artifact_id;
descriptor.artifacts_snapshot = artifacts;
descriptor.base_seed = baseSeed;
descriptor.anchor_frame_id = anchorFrameId;
descriptor.frame_ids = frameIds(:).';
descriptor.context_frame_ids = contextFrameIds(:).';
descriptor.requested_output_global_range = requestedRange;
descriptor.available_context_global_range = contextRange;
descriptor.waveform_numeric_sha256 = waveformSha;
descriptor.waveform_numeric_sha256_serialization = ...
    ['bistatic_waveform_numeric_sha256_v1: exact ordered complex-double ' ...
    'sample vector with schema/shape UTF-8 header and MATLAB-column-major ' ...
    'IEEE-754 binary64 little-endian real/imaginary planes'];
descriptor.regeneration.function = 'bistatic_generate_frame';
descriptor.regeneration.requires_artifacts_snapshot = true;
descriptor.symbol_context.owner_frame_ids = symbolOwnerFrameIds;
descriptor.symbol_context.symbol_ids_zero_based = symbolIds;
descriptor.symbol_context.cp_start_global_indices = symbolCpStarts;
descriptor.context.contiguous_frame_ids = true;
descriptor.context.complete_frame_coverage = true;
descriptor.context.zero_fill_allowed = false;
descriptor.context.missing_provenance_allowed = false;
end

function info = validateConfiguration(cfg, expectedShaValue)
requireFields(cfg, {'source_path', 'sha256', 'profile_id', 'signal', ...
    'frame'}, 'cfg');
expectedSha = sha256Text(expectedShaValue, 'options.config_sha256');
configSha = sha256Text(cfg.sha256, 'cfg.sha256');
if ~strcmp(expectedSha, configSha)
    error('bistatic:CpOfdmDescriptorConfigHash', ...
        'The supplied config SHA-256 does not match cfg.sha256.');
end
sourcePath = canonicalFilePath(cfg.source_path, 'cfg.source_path');
if ~strcmp(bistatic_sha256(sourcePath, true), configSha)
    error('bistatic:CpOfdmDescriptorConfigSource', ...
        'The canonical config file bytes do not match cfg.sha256.');
end
derived = bistatic_validate_config(cfg);
requireFields(cfg.signal, {'sample_rate_hz'}, 'cfg.signal');
requiredFrame = {'fft_length', 'cyclic_prefix_samples', ...
    'active_subcarriers', 'total_symbols', 'symbol_samples_with_cp', ...
    'frame_samples'};
requireFields(cfg.frame, requiredFrame, 'cfg.frame');
if cfg.signal.sample_rate_hz ~= 500e6 || cfg.frame.fft_length ~= 2048 || ...
        cfg.frame.cyclic_prefix_samples ~= 512 || ...
        cfg.frame.active_subcarriers ~= 1640 || ...
        cfg.frame.total_symbols ~= 522 || ...
        cfg.frame.symbol_samples_with_cp ~= 2560 || ...
        cfg.frame.frame_samples ~= 1336320 || ...
        derived.frame_samples ~= cfg.frame.frame_samples
    error('bistatic:CpOfdmDescriptorProjectConfig', ...
        'cfg is not the frozen project CP-OFDM frame configuration.');
end
info.source_path = sourcePath;
info.sha256 = configSha;
info.profile_id = textScalar(cfg.profile_id, 'cfg.profile_id');
info.frame_samples = double(cfg.frame.frame_samples);
info.symbol_samples = double(cfg.frame.symbol_samples_with_cp);
info.total_symbols = double(cfg.frame.total_symbols);
end

function info = validateArtifacts(artifacts, cfg, mode, options)
required = {'artifact_class', 'production_allowed', 'resolved_by', ...
    'preamble_fd', 'pilot_mask_active_by_payload', ...
    'pilot_values_active_by_payload'};
requireFields(artifacts, required, 'artifacts');
artifactClass = textScalar(artifacts.artifact_class, ...
    'artifacts.artifact_class');
allowedClasses = {'t02_production_preamble_pilot', 't01_test_fixture'};
if ~any(strcmp(artifactClass, allowedClasses))
    error('bistatic:CpOfdmDescriptorArtifactClass', ...
        'The artifact class is not a recognized project class.');
end
if ~islogical(artifacts.production_allowed) || ...
        ~isscalar(artifacts.production_allowed)
    error('bistatic:CpOfdmDescriptorArtifactProduction', ...
        'artifacts.production_allowed must be a logical scalar.');
end
productionAllowed = artifacts.production_allowed;
if strcmp(artifactClass, 't02_production_preamble_pilot') ~= ...
        productionAllowed
    error('bistatic:CpOfdmDescriptorArtifactProduction', ...
        'Artifact class and production_allowed are inconsistent.');
end
if strcmp(mode, 'production') && ~productionAllowed
    error('bistatic:CpOfdmDescriptorProductionArtifact', ...
        'Production mode rejects non-production artifacts.');
end
if ~strcmp(textScalar(artifacts.resolved_by, ...
        'artifacts.resolved_by'), 'T02')
    error('bistatic:CpOfdmDescriptorArtifactOwner', ...
        'Project preamble and pilot artifacts must be resolved by T02.');
end
validateArtifactArrays(artifacts, cfg);
content = bistatic_artifact_content_identity(artifacts, cfg.sha256);
if isfield(options, 'artifact_content_sha256') && ...
        ~isempty(options.artifact_content_sha256)
    expectedContentSha = sha256Text(options.artifact_content_sha256, ...
        'options.artifact_content_sha256');
    if ~strcmp(expectedContentSha, content.semantic_sha256)
        error('bistatic:CpOfdmDescriptorArtifactContentHash', ...
            'The supplied artifact content SHA-256 does not match.');
    end
else
    expectedContentSha = '';
end

hasSource = isfield(artifacts, 'source_path') && ...
    ~isempty(artifacts.source_path);
if hasSource
    sourcePath = canonicalFilePath(artifacts.source_path, ...
        'artifacts.source_path');
    if isfield(options, 'artifact_source_path') && ...
            ~isempty(options.artifact_source_path)
        expectedPath = canonicalFilePath(options.artifact_source_path, ...
            'options.artifact_source_path');
        if ~strcmpi(expectedPath, sourcePath)
            error('bistatic:CpOfdmDescriptorArtifactSource', ...
                'The supplied artifact source path does not match the snapshot.');
        end
    end
    sourceSha = bistatic_sha256(sourcePath, true);
    if isfield(options, 'artifact_sha256') && ...
            ~isempty(options.artifact_sha256)
        expectedSourceSha = sha256Text(options.artifact_sha256, ...
            'options.artifact_sha256');
        if ~strcmp(expectedSourceSha, sourceSha)
            error('bistatic:CpOfdmDescriptorArtifactSourceHash', ...
                'The supplied artifact source byte SHA-256 does not match.');
        end
    end
    verifySourcedArtifactSnapshot(sourcePath, artifacts, cfg, ...
        content.semantic_sha256);
    sourceKind = 'file_bytes';
    researchArtifactId = '';
else
    if strcmp(mode, 'production')
        error('bistatic:CpOfdmDescriptorArtifactSource', ...
            'Production artifacts require a real source file path.');
    end
    if isfield(options, 'artifact_source_path') && ...
            ~isempty(options.artifact_source_path)
        error('bistatic:CpOfdmDescriptorArtifactSource', ...
            'An in-memory research artifact cannot claim a source file path.');
    end
    if isempty(expectedContentSha)
        error('bistatic:CpOfdmDescriptorArtifactContentHash', ...
            ['An in-memory research artifact requires an explicit matching ' ...
            'artifact_content_sha256.']);
    end
    if ~isfield(options, 'research_artifact_id')
        error('bistatic:CpOfdmDescriptorResearchArtifactId', ...
            'An in-memory research artifact requires research_artifact_id.');
    end
    researchArtifactId = textScalar(options.research_artifact_id, ...
        'options.research_artifact_id');
    if isfield(options, 'artifact_sha256') && ...
            ~isempty(options.artifact_sha256) && ...
            ~strcmp(options.artifact_sha256, 'NOT_APPLICABLE_RESEARCH')
        error('bistatic:CpOfdmDescriptorArtifactSourceHash', ...
            ['An in-memory research artifact must not claim a source byte ' ...
            'SHA-256.']);
    end
    sourcePath = '';
    sourceSha = 'NOT_APPLICABLE_RESEARCH';
    sourceKind = 'in_memory_research';
end

info.artifact_class = artifactClass;
info.production_allowed = productionAllowed;
info.source_kind = sourceKind;
info.source_path = sourcePath;
info.source_sha256 = sourceSha;
info.content_sha256 = content.semantic_sha256;
info.component_sha256 = content.component_sha256;
info.content_serialization = content.serialization;
info.research_artifact_id = researchArtifactId;
end

function validateArtifactArrays(artifacts, cfg)
expectedPreamble = [cfg.frame.fft_length, cfg.frame.preamble_symbols];
expectedPayload = [cfg.frame.active_subcarriers, ...
    cfg.frame.payload_symbols];
if ~isa(artifacts.preamble_fd, 'double') || ...
        ~isequal(size(artifacts.preamble_fd), expectedPreamble) || ...
        any(~isfinite(real(artifacts.preamble_fd)), 'all') || ...
        any(~isfinite(imag(artifacts.preamble_fd)), 'all') || ...
        ~islogical(artifacts.pilot_mask_active_by_payload) || ...
        ~isequal(size(artifacts.pilot_mask_active_by_payload), ...
        expectedPayload) || ...
        ~isa(artifacts.pilot_values_active_by_payload, 'double') || ...
        ~isequal(size(artifacts.pilot_values_active_by_payload), ...
        expectedPayload) || ...
        any(~isfinite(real(artifacts.pilot_values_active_by_payload)), 'all') || ...
        any(~isfinite(imag(artifacts.pilot_values_active_by_payload)), 'all')
    error('bistatic:CpOfdmDescriptorArtifactShape', ...
        'Artifact arrays have invalid project shape, type, or finite values.');
end
if isfield(artifacts, 'metadata') && ...
        isfield(artifacts.metadata, 'config_sha256') && ...
        ~strcmp(textScalar(artifacts.metadata.config_sha256, ...
        'artifacts.metadata.config_sha256'), cfg.sha256)
    error('bistatic:CpOfdmDescriptorArtifactConfigHash', ...
        'Artifact metadata does not match the canonical config SHA-256.');
end
end

function verifySourcedArtifactSnapshot(sourcePath, artifacts, cfg, snapshotSha)
[~, ~, extension] = fileparts(sourcePath);
if ~strcmpi(extension, '.mat')
    error('bistatic:CpOfdmDescriptorArtifactSource', ...
        'A sourced project artifact must be a MAT file.');
end
loaded = load(sourcePath, 'artifact_metadata', 'preamble_fd', ...
    'pilot_mask_active_by_payload', 'pilot_values_active_by_payload');
requireFields(loaded, {'artifact_metadata', 'preamble_fd', ...
    'pilot_mask_active_by_payload', 'pilot_values_active_by_payload'}, ...
    'artifact source MAT file');
requireScalarStruct(loaded.artifact_metadata, 'artifact_metadata');
requireFields(loaded.artifact_metadata, {'config_sha256'}, ...
    'artifact_metadata');
if ~strcmp(textScalar(loaded.artifact_metadata.config_sha256, ...
        'artifact_metadata.config_sha256'), cfg.sha256)
    error('bistatic:CpOfdmDescriptorArtifactConfigHash', ...
        'The artifact source MAT file has the wrong config SHA-256.');
end
sourceSnapshot = artifacts;
sourceSnapshot.preamble_fd = loaded.preamble_fd;
sourceSnapshot.pilot_mask_active_by_payload = ...
    loaded.pilot_mask_active_by_payload;
sourceSnapshot.pilot_values_active_by_payload = ...
    loaded.pilot_values_active_by_payload;
validateArtifactArrays(sourceSnapshot, cfg);
sourceContent = bistatic_artifact_content_identity( ...
    sourceSnapshot, cfg.sha256);
if ~strcmp(sourceContent.semantic_sha256, snapshotSha)
    error('bistatic:CpOfdmDescriptorArtifactContentHash', ...
        'The artifact snapshot content differs from its source MAT file.');
end
end

function values = contiguousIntegerVector(values, label, errorId)
if ~isnumeric(values) || islogical(values) || ~isvector(values) || ...
        isempty(values) || ~isreal(values) || any(~isfinite(values)) || ...
        any(values ~= fix(values)) || any(abs(double(values)) > 2^31 - 1)
    error(errorId, '%s must be a nonempty finite int32-range vector.', label);
end
values = double(values(:));
if any(diff(values) ~= 1)
    error(errorId, '%s must be strictly ascending and contiguous.', label);
end
end

function range = inclusiveIntegerRange(range, label)
if ~isnumeric(range) || islogical(range) || ~isreal(range) || ...
        numel(range) ~= 2 || any(~isfinite(range)) || ...
        any(range ~= fix(range)) || any(abs(double(range)) > flintmax)
    error('bistatic:CpOfdmDescriptorRange', ...
        '%s must contain two exactly represented finite integers.', label);
end
range = double(range(:).');
if range(1) > range(2)
    error('bistatic:CpOfdmDescriptorRange', ...
        '%s must use inclusive ascending bounds.', label);
end
end

function value = boundedIntegerScalar(value, minimum, maximum, label)
if ~isnumeric(value) || islogical(value) || ~isscalar(value) || ...
        ~isreal(value) || ~isfinite(value) || value ~= fix(value) || ...
        value < minimum || value > maximum
    error('bistatic:CpOfdmDescriptorInteger', ...
        '%s is outside its permitted integer range.', label);
end
value = double(value);
end

function value = sha256Text(value, label)
value = textScalar(value, label);
if numel(value) ~= 64 || ...
        ~all(ismember(value, '0123456789abcdef'))
    error('bistatic:CpOfdmDescriptorSha256', ...
        '%s must be a lowercase 64-digit SHA-256 value.', label);
end
end

function path = canonicalFilePath(value, label)
path = textScalar(value, label);
if ~isfile(path)
    error('bistatic:CpOfdmDescriptorFile', ...
        '%s does not name an existing file.', label);
end
path = char(java.io.File(path).getCanonicalPath());
end

function value = textScalar(value, label)
if isstring(value)
    if ~isscalar(value) || ismissing(value)
        error('bistatic:CpOfdmDescriptorText', ...
            '%s must be a nonmissing text scalar.', label);
    end
    value = char(value);
elseif ~ischar(value) || ~isrow(value)
    error('bistatic:CpOfdmDescriptorText', ...
        '%s must be a character row or string scalar.', label);
end
if isempty(value)
    error('bistatic:CpOfdmDescriptorText', ...
        '%s must not be empty.', label);
end
end

function requireScalarStruct(value, label)
if ~isstruct(value) || ~isscalar(value)
    error('bistatic:CpOfdmDescriptorType', ...
        '%s must be a scalar struct.', label);
end
end

function requireFields(value, names, label)
for index = 1:numel(names)
    if ~isfield(value, names{index})
        error('bistatic:CpOfdmDescriptorMissingField', ...
            '%s is missing required field %s.', label, names{index});
    end
end
end
