function m=cfo_chain_score(y,reference,base)
% Scoring only. No phase/time/gain adjustment is applied to DUT or reference.
N=numel(y);assert(N==1336320 && numel(reference)==N && all(isfinite(y)) && all(isfinite(reference)));
idx=25984+(0:511)*2560+(0:2047).';d=y-reference;den=sum(abs(reference).^2);assert(den>0);
we=sum(abs(d(idx+1)).^2,1);wr=sum(abs(reference(idx+1)).^2,1);assert(all(wr>0));
active=[(-820:-1) (1:820)].';bins=mod(active,2048)+1;Fr=fft(reference(idx+1),2048,1);Fd=fft(d(idx+1),2048,1);
ae=sum(abs(Fd(bins,:)).^2,1);ar=sum(abs(Fr(bins,:)).^2,1);
a=sum(y(idx+1).*conj(reference(idx+1)),1).';tt=(idx(1,:).'+1023.5)/500e6;tc=tt-mean(tt);phase=unwrap(angle(a));freq=sum(tc.*phase)/sum(tc.^2)/(2*pi);
m=struct('full_evm',sqrt(sum(abs(d).^2)/den),'worst_fft_input_evm',sqrt(max(we./wr)), ...
 'active_subcarrier_evm',sqrt(sum(ae)/sum(ar)),'worst_active_subcarrier_evm',sqrt(max(ae./ar)), ...
 'measured_relative_frequency_hz',freq,'zero_error',all(d==0),'ber_applicable',~isempty(base),'dut_ber',[],'reference_ber',[],'dut_ser',[],'reference_ser',[],'extra_ber',[],'extra_ser',[],'absolute_noiseless_full_evm',[],'absolute_noiseless_worst_fft_evm',[],'oracle_noiseless_full_evm',[]);
if ~isempty(base)
 assert(numel(base)==N);db=y-base;bt=base(idx+1);m.absolute_noiseless_full_evm=sqrt(sum(abs(db).^2)/sum(abs(base).^2));m.absolute_noiseless_worst_fft_evm=sqrt(max(sum(abs(db(idx+1)).^2,1)./sum(abs(bt).^2,1)));m.oracle_noiseless_full_evm=sqrt(sum(abs(reference-base).^2)/sum(abs(base).^2));clear db bt;phaseA=exp(2j*pi*active*128/2048);Ft=fft(base(idx+1),2048,1);Ty=fft(y(idx+1),2048,1);
 tx=Ft(bins,:).*phaseA;ry=Ty(bins,:).*phaseA;rr=Fr(bins,:).*phaseA;
 ti=real(tx)>=0;tq=imag(tx)>=0;di=(real(ry)>=0)~=ti;dq=(imag(ry)>=0)~=tq;ri=(real(rr)>=0)~=ti;rq=(imag(rr)>=0)~=tq;
 m.dut_ber=(nnz(di)+nnz(dq))/(2*numel(tx));m.reference_ber=(nnz(ri)+nnz(rq))/(2*numel(tx));m.dut_ser=nnz(di|dq)/numel(tx);m.reference_ser=nnz(ri|rq)/numel(tx);m.extra_ber=m.dut_ber-m.reference_ber;m.extra_ser=m.dut_ser-m.reference_ser;
end
end