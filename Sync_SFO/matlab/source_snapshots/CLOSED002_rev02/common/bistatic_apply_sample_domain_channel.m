function received = bistatic_apply_sample_domain_channel( ...
        waveform, cfg, impairment, profile, noiseSeed)
%BISTATIC_APPLY_SAMPLE_DOMAIN_CHANNEL Named generic sample-domain channel.
% This wrapper deliberately preserves the complete legacy
% bistatic_apply_channel contract. Project CP-OFDM callers must use the
% separately named high-precision API and must not be auto-dispatched here.

received = bistatic_apply_channel( ...
    waveform, cfg, impairment, profile, noiseSeed);
end
