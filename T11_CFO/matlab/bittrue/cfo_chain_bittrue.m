function [y,info,audit]=cfo_chain_bittrue(x,desc,k,P,cfg)
% Proposed RTL arithmetic actually evaluated in MATLAB; custom IP-free model.
pc=cfo_chain_arithmetic('params','coarse',desc.coarse_hz_q8,desc,cfg.nco_bits);
[coarse,cs,ca]=cfo_chain_arithmetic('rotate',x,pc,cfg);
[z,front,fa]=cfo_chain_arithmetic('front',coarse,k,P);
[estimate,ea]=cfo_chain_arithmetic('estimate',z);
pr=cfo_chain_arithmetic('params','residual',estimate.frequency_q16,desc,cfg.nco_bits);
[y,rs,ra]=cfo_chain_arithmetic('rotate',coarse,pr,cfg);
info=struct('valid',estimate.valid,'mode',estimate.mode,'hz',estimate.hz,'coarse_parameters',pc,'residual_parameters',pr, ...
 'coarse_rotation',cs,'front',front,'estimate',estimate,'final_rotation',rs,'profile',cfg.name,'vendor_bittrue',false);
audit=struct('coarse_rotation_nodes',ca,'front',fa,'estimator',ea,'final_rotation_nodes',ra);
end