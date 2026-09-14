function [y,info,audit]=cfo_chain_golden(x,desc,k,P)
% Full floating chain; explicit absolute coordinates, no output phase fitting.
Fs=500e6;N=numel(x);n=(0:N-1).';ratio=(desc.step1_q28/2^28)*(desc.step2_q28/2^28);origin=desc.raw_origin_q28/2^28;fc=desc.coarse_hz_q8/256;
coarse=x.*exp(-2j*pi*fc/Fs*(origin+ratio*n));
idx=25984+(0:73)*17920+(0:2047).';F=fft(coarse(idx+1),2048,1)/2048;
z=sum(F(mod(k,2048)+1,:).*conj(P).*exp(2j*pi*k*128/2048),1).';
M=74;dt=17920/Fs;power=abs(fft(z,256)).^2;[peak,p]=max(power);other=power;other(mod(p-1+(-4:4),256)+1)=0;secondary=max(other);energy=sum(abs(z).^2);
coh=peak/max(realmin,M*energy);ratio2=secondary/max(realmin,peak);spectrum=energy>0 && coh>=.2 && ratio2<=.25;
l=power(mod(p-2,256)+1);r=power(mod(p,256)+1);den=l-2*peak+r;delta=0;if den<0,delta=max(-.5,min(.5,.5*(l-r)/den));end
bin=p-1;if bin>=128,bin=bin-256;end;ffft=(bin+delta)/(256*dt);
phase=unwrap(angle(z))/(2*pi);w=(2*(0:M-1)-(M-1)).';fphase=2*sum(w.*phase)/(sum(w.^2)*dt);
res=phase-fphase*(0:M-1).'*dt;linear=max(abs(res-mean(res)))<=.05;
consistent=abs(fphase-ffft)<=1/(256*dt);
if spectrum && linear && consistent && abs(fphase)<=13000,f=fphase;mode='MAIN_PHASE';valid=true;
elseif spectrum && abs(ffft)<=13000,f=ffft;mode='DEGRADED_FFT';valid=true;
else,f=0;mode='INVALID';valid=false;end
y=coarse.*exp(-2j*pi*f/Fs*(n+origin/ratio));
info=struct('valid',valid,'mode',mode,'hz',f,'phase_hz',fphase,'fft_hz',ffft,'coherence_grid',coh,'secondary_power_ratio',ratio2, ...
 'coarse_effective_hz',fc*ratio,'output_time_origin_samples',origin/ratio,'algorithm','FFT256_spectral_gate_then_phaseOLS_with_flagged_FFT_fallback');
audit=struct('z',z,'power',power,'phase_turns',phase,'phase_residual_turns',res,'coarse_samples_audit',coarse(unique([1:16 65535:65538 N-15:N])));
end