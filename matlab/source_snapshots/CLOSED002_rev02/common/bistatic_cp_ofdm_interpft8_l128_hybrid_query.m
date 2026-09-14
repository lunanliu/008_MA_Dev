function [samples,diagnostics] = ...
        bistatic_cp_ofdm_interpft8_l128_hybrid_query( ...
        fdBins,grid,withinUseful,sourcePosition,queryOwnerCpStart, ...
        nfft,ncp,L)
%BISTATIC_CP_OFDM_INTERPFT8_L128_HYBRID_QUERY Owner-safe L128 CP-OFDM query.
%   Exact grid hits read only their base node. Non-exact queries use the
%   frozen eight-node barycentric formula when all physical support nodes
%   remain in the query owner. Otherwise the query owner's frequency bins
%   are evaluated by explicit direct Fourier summation.

narginchk(8,8);
nargoutchk(0,2);

if ~isa(fdBins,'double') || ~isvector(fdBins) || numel(fdBins) ~= nfft || ...
        any(~isfinite(real(fdBins))) || any(~isfinite(imag(fdBins)))
    error('bistatic:T01HybridFrequencySymbol', ...
        'fdBins must be one finite complex-double NFFT vector.');
end
if ~isa(grid,'double') || ~isvector(grid) || numel(grid) ~= nfft*L || ...
        any(~isfinite(real(grid))) || any(~isfinite(imag(grid)))
    error('bistatic:T01HybridGrid', ...
        'grid must be one finite complex-double NFFT-by-L vector.');
end
if ~isa(sourcePosition,'double') || ~isvector(sourcePosition) || ...
        isempty(sourcePosition) || ~isreal(sourcePosition) || ...
        any(~isfinite(sourcePosition))
    error('bistatic:T01HybridSourcePosition', ...
        'sourcePosition must be a nonempty finite real-double vector.');
end
if ~isa(withinUseful,'double') || ~isvector(withinUseful) || ...
        numel(withinUseful) ~= numel(sourcePosition) || ...
        ~isreal(withinUseful) || any(~isfinite(withinUseful))
    error('bistatic:T01HybridWithinUseful', ...
        'withinUseful must match the finite source-position vector.');
end
if ~isa(queryOwnerCpStart,'double') || ...
        ~isscalar(queryOwnerCpStart) || ~isfinite(queryOwnerCpStart) || ...
        queryOwnerCpStart ~= fix(queryOwnerCpStart)
    error('bistatic:T01HybridOwnerStart', ...
        'queryOwnerCpStart must be one finite integer-valued double.');
end
if ~isa(nfft,'double') || ~isscalar(nfft) || nfft ~= 2048 || ...
        ~isa(ncp,'double') || ~isscalar(ncp) || ncp ~= 512 || ...
        ~isa(L,'double') || ~isscalar(L) || L ~= 128
    error('bistatic:T01HybridGeometry', ...
        'The frozen hybrid geometry is NFFT/NCP/L = 2048/512/128.');
end

fdBins = fdBins(:);
grid = grid(:);
sourcePosition = sourcePosition(:);
withinUseful = withinUseful(:);
symbolSamples = ncp+nfft;
ownerEnd = queryOwnerCpStart+symbolSamples;
if any(sourcePosition < queryOwnerCpStart) || ...
        any(sourcePosition >= ownerEnd)
    error('bistatic:T01HybridQueryOwner', ...
        'A query lies outside its half-open physical owner interval.');
end
expectedWithinUseful = sourcePosition-(queryOwnerCpStart+ncp);
coordinateTolerance = max(1e-12, ...
    32*eps(max(1,max(abs(expectedWithinUseful)))));
if any(abs(withinUseful-expectedWithinUseful) > coordinateTolerance)
    error('bistatic:T01HybridCoordinateIdentity', ...
        'withinUseful is inconsistent with sourcePosition and owner CP start.');
end
if any(withinUseful < -ncp) || any(withinUseful >= nfft)
    error('bistatic:T01HybridOwnerCoordinate', ...
        'An owner-local coordinate is outside [-NCP,NFFT).');
end

offsets = -3:4;
weights = [1 -7 21 -35 35 -21 7 -1];
gridLength = nfft*L;
periodicWithin = mod(withinUseful,nfft);
rawGridPosition = L*periodicWithin;
gridPosition = mod(rawGridPosition,gridLength);
baseIndex = floor(gridPosition);
mu = gridPosition-baseIndex;
if any(gridPosition < 0) || any(gridPosition >= gridLength) || ...
        any(mu < 0) || any(mu >= 1)
    error('bistatic:T01HybridGridCoordinate', ...
        'A periodic L128 grid coordinate is invalid.');
end

queryCount = numel(sourcePosition);
samples = complex(zeros(queryCount,1));
branchCode = zeros(queryCount,1,'uint8');
exactMask = mu == 0;

% Exact queries intentionally read only the base node. The geometry of the
% seven unused candidates is recorded without materializing their values.
if any(exactMask)
    samples(exactMask) = grid(baseIndex(exactMask)+1);
    exactNodeSource = sourcePosition(exactMask)+(offsets-mu(exactMask))/L;
    exactUnusedMismatch = exactNodeSource < queryOwnerCpStart | ...
        exactNodeSource >= ownerEnd;
else
    exactUnusedMismatch = false(0,numel(offsets));
end

nonExactIndices = find(~exactMask);
nonExactNodeMismatchCount = 0;
if ~isempty(nonExactIndices)
    nonExactSource = sourcePosition(nonExactIndices);
    nonExactMu = mu(nonExactIndices);
    nodeSource = nonExactSource+(offsets-nonExactMu)/L;
    nodeInsideOwner = nodeSource >= queryOwnerCpStart & nodeSource < ownerEnd;
    directLocalMask = ~all(nodeInsideOwner,2);
    b8LocalMask = ~directLocalMask;
    nonExactNodeMismatchCount = nnz(~nodeInsideOwner);

    if any(b8LocalMask)
        b8Indices = nonExactIndices(b8LocalMask);
        rawNodeIndex = baseIndex(b8Indices)+offsets;
        nodeIndex = mod(rawNodeIndex,gridLength)+1;
        expectedShape = [numel(b8Indices),numel(offsets)];
        if ~isequal(size(nodeIndex),expectedShape)
            error('bistatic:T01HybridNodeIndexShape', ...
                'The B8 node-index matrix has the wrong shape.');
        end
        nodeValues = reshape(grid(nodeIndex(:)),expectedShape);
        delta = mu(b8Indices)-offsets;
        scaledWeight = weights./delta;
        numerator = sum(scaledWeight.*nodeValues,2);
        denominator = sum(scaledWeight,2);
        samples(b8Indices) = numerator./denominator;
        branchCode(b8Indices) = uint8(1);
    end

    if any(directLocalMask)
        directIndices = nonExactIndices(directLocalMask);
        samples(directIndices) = directFourierOwner( ...
            fdBins,withinUseful(directIndices),nfft);
        branchCode(directIndices) = uint8(2);
    end
end

nonfiniteCount = nnz(~isfinite(real(samples)) | ~isfinite(imag(samples)));
if nonfiniteCount ~= 0
    error('bistatic:T01HybridNonfinite', ...
        'The hybrid query produced %d nonfinite outputs.',nonfiniteCount);
end

diagnostics = struct();
diagnostics.schema = ...
    'bistatic_cp_ofdm_interpft8_l128_hybrid_query_v1';
diagnostics.method = ...
    'exact_base_else_same_owner_b8_else_query_owner_direct_fourier';
diagnostics.query_count = queryCount;
diagnostics.exact_query_count = nnz(exactMask);
diagnostics.b8_query_count = nnz(branchCode == 1);
diagnostics.direct_fourier_query_count = nnz(branchCode == 2);
diagnostics.unread_exact_cross_owner_node_count = ...
    nnz(exactUnusedMismatch);
diagnostics.exact_query_with_unread_cross_owner_count = ...
    nnz(any(exactUnusedMismatch,2));
diagnostics.nonexact_cross_owner_node_count = ...
    nonExactNodeMismatchCount;
diagnostics.unhandled_nonexact_cross_owner_query_count = 0;
diagnostics.query_owner_mismatch_count = 0;
diagnostics.drop_count = 0;
diagnostics.duplicate_count = 0;
diagnostics.reorder_count = 0;
diagnostics.nonfinite_count = nonfiniteCount;
diagnostics.branch_code = branchCode;
diagnostics.mu = mu;
diagnostics.base_index_zero_based = baseIndex;
diagnostics.owner_cp_start = queryOwnerCpStart;
diagnostics.owner_interval_end_exclusive = ownerEnd;
diagnostics.node_offsets = offsets;
diagnostics.barycentric_weights = weights;
diagnostics.direct_fourier_uses_query_owner_only = true;
diagnostics.direct_fourier_nonzero_bin_count = nnz(fdBins ~= 0);
diagnostics.pchip_fallback_used = false;
diagnostics.generic_sample_fallback_used = false;
diagnostics.all_checks_passed = true;
end

function values = directFourierOwner(fdBins,withinUseful,nfft)
% Deliberately local implementation; the gate uses a separate oracle.
signedBins = (0:nfft-1).';
signedBins(signedBins > nfft/2) = ...
    signedBins(signedBins > nfft/2)-nfft;
nonzeroMask = fdBins ~= 0;
signedBins = signedBins(nonzeroMask);
fdBins = fdBins(nonzeroMask);
withinUseful = withinUseful(:);
values = complex(zeros(numel(withinUseful),1));
chunkSize = 64;
for first = 1:chunkSize:numel(withinUseful)
    last = min(first+chunkSize-1,numel(withinUseful));
    selection = first:last;
    phase = exp(1j*2*pi/nfft* ...
        (withinUseful(selection)*signedBins.'));
    values(selection) = phase*fdBins/nfft;
end
end
