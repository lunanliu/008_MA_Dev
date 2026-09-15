function varargout=cfo_chain_arithmetic(op,varargin)
% Explicit custom finite-word arithmetic; no vendor IP equivalence claimed.
switch op
 case 'params',varargout{1}=parameters(varargin{:});
 case 'rotate',[varargout{1:nargout}]=rotate(varargin{:});
 case 'fft',[varargout{1:nargout}]=fixedFft(varargin{:});
 case 'front',[varargout{1:nargout}]=front(varargin{:});
 case 'estimate',[varargout{1:nargout}]=estimate(varargin{:});
 case 'rne',varargout{1}=rne(varargin{1});
 otherwise,error('CFO:Operation','Unknown operation');
end
end
function p=parameters(kind,fcode,desc,width)
% Coarse Hz S32/F8; residual Hz S32/F16. Q28 steps and raw origin.
Fs=uint64(500000000);s1=desc.step1_q28;s2=desc.step2_q28;o=desc.raw_origin_q28;
assert(ismember(width,[32 48]) && abs(fcode)<2^31 && all([s1 s2]>0) && all([s1 s2]<2^32));
assert(all([fcode s1 s2 o]==fix([fcode s1 s2 o])) && abs(o)<2^53);
if strcmp(kind,'coarse')
 step48=-sign(fcode)*double(divProduct([abs(fcode) s1 s2],Fs.*uint64(65536),48));
 phi48=-sign(fcode)*sign(o)*double(divProduct([abs(fcode) abs(o) 4096],Fs,48));
 originOut=sign(o)*double(divProduct([abs(o) 2^44],uint64(s1).*uint64(s2),48));
else
 assert(strcmp(kind,'residual'));
 originOut=sign(o)*double(divProduct([abs(o) 2^44],uint64(s1).*uint64(s2),48));
 step48=-sign(fcode)*double(divProduct([abs(fcode) 2^32],Fs,48));
 phi48=-sign(fcode)*sign(originOut)*double(divProduct([abs(fcode) abs(originOut) 65536],Fs,48));
end
assert(abs(step48)<2^47);sh=48-width;
step=rneInt(int64(step48),int64(2^sh));phi=mod(rneInt(int64(mod(phi48,2^48)),int64(2^sh)),int64(2^width));
p=struct('width',width,'step',step,'phase0',phi,'origin_output_q16',originOut, ...
 'effective_correction_hz',-double(step)*500e6/2^width,'frequency_code',fcode,'kind',kind);
end
function q=divProduct(factors,D,bits)
% Unsigned exact product in base2^16; restoring divide with uint64 remainder.
% D<2^62 ensures every remainder shift is exact. Quotient kept modulo2^bits.
assert(D>0 && D<bitshift(uint64(1),62) && bits<=48 && all(factors>=0) && all(factors<2^53) && all(factors==fix(factors)));
B=65536;v=1;
for f=factors
 if f==0,q=uint64(0);return;end
 a=[];while f>0,a(end+1)=mod(f,B);f=floor(f/B);end %#ok<AGROW>
 w=zeros(1,numel(v)+numel(a));
 for i=1:numel(v),for j=1:numel(a),w(i+j-1)=w(i+j-1)+v(i)*a(j);end,end
 for i=1:numel(w)-1,carry=floor(w(i)/B);w(i)=mod(w(i),B);w(i+1)=w(i+1)+carry;end
 assert(w(end)<B);while numel(w)>1 && w(end)==0,w(end)=[];end;v=w;
end
q=uint64(0);r=uint64(0);mask=bitshift(uint64(1),bits)-1;
for i=numel(v):-1:1
 for b=15:-1:0
  r=bitshift(r,1)+uint64(bitget(uint16(v(i)),b+1));q=bitand(bitshift(q,1),mask);
  if r>=D,r=r-D;q=q+1;end
 end
end
twice=bitshift(r,1);if twice>D || (twice==D && bitand(q,uint64(1))~=0),q=bitand(q+1,mask);end
end
function [y,stat,audit]=rotate(x,p,cfg)
% LUT codes define the proposed RTL ROM, ordinary complex multiplication.
B=65536;N=numel(x);y=complex(zeros(size(x)));sat=0;coefSat=0;
values=exp(2j*pi*(0:2^cfg.address_bits-1).'/2^cfg.address_bits)*2^cfg.coef_frac;
[lut,~]=quant(values,cfg.coef_bits);clip=(rne(real(values))>2^(cfg.coef_bits-1)-1)+(rne(imag(values))>2^(cfg.coef_bits-1)-1);
keep=unique([0:15 127:129 255:257 65534:65537 N-16:N-1]).';keep=keep(keep>=0 & keep<N);audit=zeros(numel(keep),11);cursor=0;
for first=1:B:N
 last=min(first+B-1,N);ix=first:last;n=int64((first-1:last-1).');
 assert(abs(double(p.step))*double(n(end))+double(p.phase0)<2^62);
 phase=mod(p.phase0+n.*p.step,int64(2^p.width));addr=mod(rneInt(phase,int64(2^(p.width-cfg.address_bits))),int64(2^cfg.address_bits));
 coef=lut(double(addr)+1);raw=x(ix)*32768;assert(all(real(raw)==fix(real(raw))) && all(imag(raw)==fix(imag(raw))));
 prodI=real(raw).*real(coef)-imag(raw).*imag(coef);prodQ=real(raw).*imag(coef)+imag(raw).*real(coef);
 assert(all(abs(prodI)<2^53) && all(abs(prodQ)<2^53));[out,ss]=quant(complex(prodI,prodQ)/2^cfg.coef_frac,16);y(ix)=out/32768;sat=sat+ss;coefSat=coefSat+sum(clip(double(addr)+1));
 use=keep(keep>=first-1 & keep<last);local=use-first+2;k=numel(use);
 if k,audit(cursor+(1:k),:)=[use double(phase(local)) double(addr(local)) real(raw(local)) imag(raw(local)) real(coef(local)) imag(coef(local)) prodI(local) prodQ(local) real(out(local)) imag(out(local))];cursor=cursor+k;end
end
stat=struct('output_saturation_components',sat,'coefficient_clipped_queries',coefSat,'rom_entries',numel(lut));
end
function [z,stat,audit]=front(x,k,P)
N=2048;starts=25984+(0:73)*17920;ix=starts+(0:N-1).';
raw=x(ix+1)*32768;assert(all(real(raw(:))==fix(real(raw(:)))) && all(imag(raw(:))==fix(imag(raw(:)))));
[F,st]=fixedFft(raw*64,26);bins=mod(k,N)+1;
coeff=conj(P).*exp(2j*pi*k*128/N);[c,~]=quant(coeff*2^17,18);a=F(bins,:);
H=complex(rne((real(a).*real(c)-imag(a).*imag(c))/2^17),rne((real(a).*imag(c)+imag(a).*real(c))/2^17));
[H,hs]=quant(H,28);z=sum(H,1).';assert(all(abs(real(z))<2^37 & abs(imag(z))<2^37));
stat=struct('fft_data_saturation',st.data_sat,'pilot_product_saturation',hs,'fractional_bits',21,'sum_width',38);
audit=struct('pilot_fft_codes',a,'pilot_coeff_codes',c,'pilot_product_codes',H,'z_codes',z);
end
function [v,stat]=fixedFft(v,bits)
% Integer complex double values below2^53; radix2 DIT /2 per stage.
N=size(v,1);M=size(v,2);assert(N==2^round(log2(N)));assert(all(real(v(:))==fix(real(v(:)))) && all(imag(v(:))==fix(imag(v(:)))));
rev=zeros(N,1);a=(0:N-1).';for b=1:log2(N),rev=2*rev+mod(a,2);a=floor(a/2);end
v=v(rev+1,:);sat=0;
for stage=1:log2(N)
 L=2^stage;ix=reshape(1:N,L,[]);ia=ix(1:L/2,:);ib=ix(L/2+1:end,:);
 [tw,~]=quant(exp(-2j*pi*(0:L/2-1).'/L)*2^17,18);
 va=reshape(v(ia(:),:),L/2,N/L,M);vb=reshape(v(ib(:),:),L/2,N/L,M);
 prodI=real(vb).*real(tw)-imag(vb).*imag(tw);prodQ=real(vb).*imag(tw)+imag(vb).*real(tw);
 assert(all(abs(prodI(:))<2^53) && all(abs(prodQ(:))<2^53));p=complex(rne(prodI/2^17),rne(prodQ/2^17));
 [up,s1]=quant((va+p)/2,bits);[dn,s2]=quant((va-p)/2,bits);v(ia(:),:)=reshape(up,N/2,M);v(ib(:),:)=reshape(dn,N/2,M);sat=sat+s1+s2;
end
stat=struct('data_sat',sat,'stages',log2(N),'scaling','one_bit_each_stage','twiddle','S18F17_RNE_sat');
end
function [out,audit]=estimate(z)
M=74;assert(numel(z)==M);z=z(:);mx=max([abs(real(z));abs(imag(z))]);
if mx==0,out=struct('valid',false,'mode','INVALID_ZERO','frequency_q16',0,'hz',0,'phase_q16',0,'fft_q16',0,'spectrum_valid',false,'phase_linear',false);audit=struct;return;end
ex=floor(log2(.5*2^17/mx));[u,us]=quant(z*2^ex,20);v=complex(zeros(256,1));v(1:M)=u;[V,st]=fixedFft(v,20);power=real(V).^2+imag(V).^2;[peak,p]=max(power);other=power;other(mod((p-1)+(-4:4),256)+1)=0;secondary=max(other);
energy=sum(real(u).^2+imag(u).^2);coherent=(5*256^2*peak>=M*energy);unambiguous=(4*secondary<=peak);spectrum=coherent && unambiguous && us==0 && st.data_sat==0;
l=power(mod(p-2,256)+1);r=power(mod(p,256)+1);den=l-2*peak+r;delta=0;
if den<0,delta=double(rneInt(int64(l-r).*int64(32768),int64(den)));delta=max(-32768,min(32768,delta));end
bin=p-1;if bin>=128,bin=bin-256;end
fftCode=double(rneInt(int64(bin*65536+delta).*int64(500000000),int64(256*17920)));
[angles,cordic]=phaseCordic(z);unwrapped=angles;offset=0;
for m=2:M,d=angles(m)-angles(m-1);if d>2^30,offset=offset-2^31;elseif d< -2^30,offset=offset+2^31;end;unwrapped(m)=angles(m)+offset;end
w=(2*(0:M-1)-(M-1)).';dot=sum(w.*unwrapped);assert(abs(dot)<2^49);
num=int64(dot).*int64(15625);phaseCode=double(rneInt(num,int64(1239089152)));
pred=rneInt(int64(phaseCode).*int64((0:M-1).').*int64(458752),int64(390625));res=unwrapped-double(pred);centered=M*res-sum(res);linear=(20*max(abs(centered))<=M*2^31) && cordic.saturation==0;
consistent=abs(int64(phaseCode)-int64(fftCode)).*int64(256*17920)<=int64(500000000).*int64(65536);
if spectrum && linear && consistent && abs(phaseCode)<=13000*65536,chosen=phaseCode;mode='MAIN_PHASE';valid=true;
elseif spectrum && abs(fftCode)<=13000*65536,chosen=fftCode;mode='DEGRADED_FFT';valid=true;
else,chosen=0;mode='INVALID';valid=false;end
out=struct('valid',valid,'mode',mode,'frequency_q16',chosen,'hz',chosen/65536,'phase_q16',phaseCode,'fft_q16',fftCode, ...
 'spectrum_valid',spectrum,'phase_linear',linear,'phase_fft_consistent',consistent,'coherence_grid',256^2*peak/(M*energy),'secondary_power_ratio',secondary/max(1,peak));
audit=struct('z_codes',z,'block_exponent',ex,'fft_input_codes',u,'fft_codes',V,'power',power,'peak_bin_zero_based',p-1, ...
 'delta_q16',delta,'angle_turn_q31',angles,'unwrapped_turn_q31',unwrapped,'weighted_sum',dot,'predicted_turn_q31',pred, ...
 'centered_residual_times74',centered,'cordic',cordic);
end
function [a,stat]=phaseCordic(z)
% S40 Cartesian vectoring, 24 stages; turn angles S32/F31, no gain correction.
x=real(z);y=imag(z);a=zeros(size(x));neg=x<0;a(neg & y>=0)=2^30;a(neg & y<0)=-2^30;x(neg)=-x(neg);y(neg)=-y(neg);sat=0;
constants=rne(atan(2.^-(0:23))/(2*pi)*2^31);
for i=0:23
 d=ones(size(y));d(y<0)=-1;xn=x+d.*floor(y/2^i);yn=y-d.*floor(x/2^i);an=a+d*constants(i+1);
 sat=sat+nnz(xn< -2^39|xn>2^39-1|yn< -2^39|yn>2^39-1);x=max(-2^39,min(2^39-1,xn));y=max(-2^39,min(2^39-1,yn));a=an;
end
stat=struct('saturation',sat,'iterations',24,'atan_turn_q31',constants,'final_x',x,'final_y',y);
end
function q=rneInt(x,d)
assert(isa(x,'int64') && isa(d,'int64') && isscalar(d) && d~=0);
sg=int64(sign(x)).*int64(sign(d));a=abs(x);den=abs(d);q=idivide(a,den,'floor');rem=a-q.*den;inc=rem>idivide(den,int64(2),'floor');tie=bitand(den,int64(1))==0 & rem==idivide(den,int64(2),'floor');inc=inc | (tie & bitand(q,int64(1))~=0);q=(q+int64(inc)).*sg;
end
function [q,s]=quant(x,bits)
a=rne(real(x));b=rne(imag(x));lo=-2^(bits-1);hi=2^(bits-1)-1;s=nnz(a<lo|a>hi)+nnz(b<lo|b>hi);q=complex(max(lo,min(hi,a)),max(lo,min(hi,b)));
end
function y=rne(x)
f=floor(x);r=x-f;y=f+(r>.5 | (r==.5 & mod(f,2)~=0));
end