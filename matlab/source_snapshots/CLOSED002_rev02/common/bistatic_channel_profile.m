function profile = bistatic_channel_profile(profileName, cfg, seed)
%BISTATIC_CHANNEL_PROFILE Build reproducible static channel tap realizations.
% TDL fixtures preserve standardized PDP/delay values but intentionally use
% static seeded coefficients. They are not a full time-varying Jakes emulator.

rs = RandStream(cfg.rng.algorithm, 'Seed', seed);
fs = cfg.signal.sample_rate_hz;
profile.name = char(profileName);
profile.seed = seed;
profile.standard_source = '';
profile.delay_spread_ns = 0;
profile.has_physical_los = true;
profile.reference_tap_index = 1;
profile.fading_implementation = 'deterministic_static';

switch char(profileName)
    case 'single_path'
        delays = 0;
        powersDb = 0;
        gains = 1;
        isLos = true;
        doppler = 0;
        profile.classification = 'deterministic_debug';
    case 'paper_offset_snr_project_grid_fixture'
        delays = [0 64];
        powersDb = [0 -35];
        gains = [1, 10^(-35 / 20) * exp(1j * 0.7)];
        isLos = [true false];
        doppler = [0 250];
        profile.classification = 'paper_derived_partial_with_engineering_path_assumptions';
        profile.paper_exact_snr_los_db = 15;
        profile.paper_exact_snr_secondary_db = -20;
        profile.engineering_assumption = ['Secondary delay, differential Doppler, and phase are not ' ...
            'published by the paper; values come from config/verification_matrix.json.'];
    case {'tdl_a_nlos_100ns', 'tdl_a_beyond_cp_300ns'}
        normalized = [0 .3819 .4025 .5868 .4610 .5375 .6708 .5750 .7618 ...
            1.5375 1.8978 2.2242 2.1718 2.4942 2.5119 3.0582 4.0810 ...
            4.4579 4.5695 4.7966 5.0066 5.3043 9.6586];
        powersDb = [-13.4 0 -2.2 -4 -6 -8.2 -9.9 -10.5 -7.5 -15.9 ...
            -6.6 -16.7 -12.4 -15.2 -10.8 -11.3 -12.7 -16.2 -18.3 ...
            -18.9 -16.6 -19.9 -29.7];
        if strcmp(profileName, 'tdl_a_nlos_100ns')
            dsNs = 100;
            profile.classification = 'standard_pdp_nlos_in_cp_stress';
        else
            dsNs = 300;
            profile.classification = 'standard_pdp_nlos_beyond_cp_stress';
        end
        delays = normalized * dsNs * 1e-9 * fs;
        gains = rayleighGains(rs, powersDb);
        isLos = false(size(delays));
        doppler = zeros(size(delays));
        profile.standard_source = 'ETSI TR 138 901 V17 Table 7.7.2-1 and Clause 7.7.3';
        profile.delay_spread_ns = dsNs;
        profile.has_physical_los = false;
        profile.reference_tap_index = 1;
        profile.fading_implementation = 'standard_pdp_seeded_static_rayleigh_fixture';
    case 'tdl_d_los_30ns'
        normalized = [0 0 .035 .612 1.363 1.405 1.804 2.596 1.775 4.042 ...
            7.937 9.424 9.708 12.525];
        powersDb = [-0.2 -13.5 -18.8 -21 -22.8 -17.9 -20.1 -21.9 -22.9 ...
            -27.8 -23.6 -24.8 -30 -27.7];
        delays = normalized * 30e-9 * fs;
        losPhase = 2 * pi * rand(rs, 1);
        gains = rayleighGains(rs, powersDb);
        gains(1) = sqrt(10^(powersDb(1) / 10)) * exp(1j * losPhase);
        isLos = [true false(1, numel(delays) - 1)];
        doppler = zeros(size(delays));
        profile.classification = 'standard_pdp_los_acceptance';
        profile.standard_source = 'ETSI TR 138 901 V17 Table 7.7.2-4 and Clause 7.7.3';
        profile.delay_spread_ns = 30;
        profile.fading_implementation = 'standard_pdp_seeded_static_ricean_fixture';
        profile.k_factor_first_tap_db = 13.3;
    otherwise
        error('bistatic:UnknownChannelProfile', 'Unknown channel profile: %s', profileName);
end

profile.tap_ids = (1:numel(delays)).';
profile.delay_samples = double(delays(:));
profile.mean_power_db = double(powersDb(:));
profile.complex_gain = complex(gains(:));
profile.doppler_hz = double(doppler(:));
profile.is_los = logical(isLos(:));
profile.maximum_delay_samples = max(profile.delay_samples);
profile.within_cp = profile.maximum_delay_samples <= cfg.frame.cyclic_prefix_samples;
end

function gains = rayleighGains(rs, powersDb)
sigma = sqrt(10.^(powersDb / 10) / 2);
gains = sigma .* (randn(rs, size(powersDb)) + 1j * randn(rs, size(powersDb)));
end
