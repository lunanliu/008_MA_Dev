function indices = bistatic_active_indices(cfg)
%BISTATIC_ACTIVE_INDICES Return one-based unshifted active-bin indices.

positive = cfg.indexing.active_positive_zero_based_inclusive;
negative = cfg.indexing.active_negative_zero_based_inclusive;
indices = [(positive(1):positive(2)) + 1, (negative(1):negative(2)) + 1].';
end
