function [y,info,capture]=t07_fixed_arithmetic_window(x,xFirst,epsilonHat,outputFirst,outputCount,q0,profile)
%T07_FIXED_ARITHMETIC_WINDOW Guard-aware integer research oracle, not RTL qualified.
% q0 is integerTO + fractionalQ0, fractionalQ0 in {0,.5}; added exactly once.
% outputFirst is an absolute output coordinate, not another timing correction.
% First two outputs use the unchanged shortest Farrow convolution path.
% Optional capture recomputes real phase continuation padded to16 temporal lanes.
% Its physical pre-crop and post-crop values are not newly certified guard.
assert(isnumeric(x) && isvector(x) && ~isempty(x) && all(isfinite(x(:))));
assert(isscalar(xFirst) && isreal(xFirst) && isfinite(xFirst) && xFirst==fix(xFirst));
assert(isscalar(outputFirst) && isreal(outputFirst) && isfinite(outputFirst) && outputFirst==fix(outputFirst));
assert(isscalar(outputCount) && isreal(outputCount) && isfinite(outputCount) && outputCount>=1 && outputCount==fix(outputCount));
assert(isscalar(epsilonHat) && isreal(epsilonHat) && isfinite(epsilonHat) && epsilonHat>-1);
assert(isscalar(q0) && isreal(q0) && isfinite(q0) && 2*q0==fix(2*q0), ...
    'q0 must contain one integer timing offset plus a fraction of0 or0.5.');
assert(max(abs([xFirst outputFirst outputCount q0]))<2^48, ...
    'Coordinate inputs exceed exact integer construction headroom.');
x=x(:);capture=[];
% External I16 Q1.15, signed D-bit Q1.(D-1) at FIR outputs.
% HB interpolation coefficient Q2.(C-2); decimation Q1.(C-1).
% Cubic Farrow coefficient Q2.(C-2), branch/Horner data Q4.(D-1).
% Every narrowing uses RNE and saturation; ratio and mu precisions differ.
C=profile.coefficient_bits;D=profile.data_bits;M=profile.mu_bits;R=profile.ratio_bits;
assert(any(C==[14 16 18]) && any(D==[16 18 20 24]));
assert(any(M==[8 12 16]) && any(R==[28 32 36]));
apriori.fir_component_sum_bound=47*2^(D-1)*2^(C-1);
apriori.farrow_branch_component_sum_bound=4*2^(D-1)*2^(C-1);
apriori.horner_component_sum_bound=2*2^(D+2)*2^M;
assert(max(struct2array(apriori))<2^53, ...
    'A priori no-cancellation integer arithmetic bound exceeds double exactness.');
fp=(820/2048)/(1-150e-6);
h1=firhalfband(46,fp);h2=firhalfband(14,fp/2);
q1=rneShift(h1*2^(C-1),0);q2=rneShift(h2*2^(C-1),0);
F=t07_lagrange_coefficients(4);
fq=rneShift(F*2^(C-2),0);
assert(max(abs([q1(:);q2(:);fq(:)]))<2^(C-1));
[inputQ,inputInfo]=t07_rne_quantize(x,16,15);
xInt=inputQ*2^(D-1);
stats=struct();stats.input_saturated_components=inputInfo.saturated_component_count;
[u2,stats.up_hb1]=firStage(xInt,q1,2,1,C-2,D);
[u4,stats.up_hb2]=firStage(u2,q2,2,1,C-2,D);
if nargout>=3
    up2Capture=u2;
end
clear u2
d1=23;d2=7;delay4=2*d1+d2;
G=ceil(delay4/2)+4;k0=4*outputFirst+delay4-4*G;kEnd=delay4+4*(outputFirst+outputCount-1);
zCount=kEnd-k0+1;z=complex(zeros(zCount,1));
stepInt=int64(rneShift((1+epsilonHat)*2^R,0));
assert(stepInt>0,'Quantized phase step must be positive.');
originUnits=-4*xFirst+delay4+4*q0;
assert(originUnits==fix(originUnits) && abs(originUnits)<2^(62-R), ...
    'Integer origin exceeds int64 phase construction headroom.');
originInt=int64(originUnits)*int64(2^R);
apriori.phase_absolute_bound=max(abs([k0 kEnd]))*abs(double(stepInt))+abs(double(originInt));
assert(apriori.phase_absolute_bound<2^62, 'int64 coordinate headroom is insufficient.');
muMod=int64(2^M);pMin=Inf;pMax=-Inf;
stats.farrow_branch=emptyStat();stats.farrow_horner=emptyStat();stats.farrow_output=emptyStat();
stats.mu_carry_count=0;
chunk=65536;
for first=1:chunk:zCount
    last=min(first+chunk-1,zCount);
    k=int64(k0+(first-1:last-1).');
    phase=k.*stepInt+originInt;
    base=bitshift(phase,-R);frac=phase-bitshift(base,R);
    mu=integerRneShift(frac,R-M);
    carry=mu==muMod;base=base+int64(carry);mu(carry)=0;
    stats.mu_carry_count=stats.mu_carry_count+nnz(carry);
    base=double(base);mu=double(mu);
    assert(min(base)-1>=0 && max(base)+2<numel(u4),'Missing input context.');
    sampleMatrix=[u4(base) u4(base+1) u4(base+2) u4(base+3)];
    rawBranch=sampleMatrix*fq;
    [branches,st]=narrow(rawBranch,C-2,D+3);
    stats.farrow_branch=mergeStat(stats.farrow_branch,st);
    value=branches(:,4);
    for order=3:-1:1
        raw=value.*mu+branches(:,order)*2^M;
        [value,st]=narrow(raw,M,D+3);
        stats.farrow_horner=mergeStat(stats.farrow_horner,st);
    end
    [z(first:last),st]=narrow(value,0,D);
    stats.farrow_output=mergeStat(stats.farrow_output,st);
    pMin=min(pMin,min(base)-1);pMax=max(pMax,max(base)+2);
end
if nargout>=3
    capture=transportCapture(inputQ*32768,up2Capture,u4,xFirst, ...
        outputFirst,outputCount,q0,k0,zCount,G,stepInt,originInt,q1,q2,fq,C,D,M,R);
    clear up2Capture
end
clear u4
[v2,stats.down_hb2]=firStage(z,q2,1,2,C-1,D);
clear z
[v,stats.down_hb1]=firStage(v2,q1,1,2,C-1,D);
y=v(G+(1:outputCount))/2^(D-1);
assert(numel(y)==outputCount && all(isfinite(y)));
info.schema='t07_integer_exact_fir_farrow_window_research_v1';
info.profile=profile;
info.input_format='I16/Q16 signed Q1.15';
info.fir_output_format=sprintf('signed Q1.%d, %d bits',D-1,D);
info.farrow_branch_horner_format=sprintf('signed Q4.%d, %d bits',D-1,D+3);
info.interpolation_coefficient_format=sprintf('signed Q2.%d',C-2);
info.decimation_coefficient_format=sprintf('signed Q1.%d',C-1);
info.farrow_coefficient_format=sprintf('signed Q2.%d',C-2);
info.rounding='RNE ties-to-even at input, every FIR output, Farrow branch, every Horner product/sum, final Farrow output';
info.overflow='signed saturate at every declared narrowing, counted per real component';
info.accumulator='a priori no-cancellation component bounds <2^53 plus observed integer assertions';
info.a_priori_bounds=apriori;
info.coordinate='int64 ratio phase; RNE mu with base-index carry';
info.step_integer=double(stepInt);
info.step_fractional_bits=R;
info.epsilon_hat_exact=epsilonHat;
info.epsilon_hat_quantized=double(stepInt)/2^R-1;
info.ratio_end_position_error_raw_samples=(outputCount-1)*(info.epsilon_hat_quantized-epsilonHat);
info.required_input_first=xFirst+ceil((pMin-2*delay4)/4);
info.required_input_last=xFirst+floor(pMax/4);
assert(info.required_input_first>=xFirst && info.required_input_last<xFirst+numel(x));
info.output_count=numel(y);
info.output_first=outputFirst;info.output_last=outputFirst+outputCount-1;
info.q0_raw_samples=q0;info.integer_timing_offset=floor(q0);
info.fractional_q0=q0-floor(q0);
info.timing_offset_policy='q0=integerTO+fractionalQ0 appears once in origin; outputFirst is output addressing';
info.original_z_count=zCount;info.k_first=k0;info.k_last=kEnd;
info.transport_capture_requested=nargout>=3;
info.stats_scope='Original shortest zCount path; FIR statistics retain original full convolution semantics';
info.legacy_output0_q00_equivalence_fixture_required=true;
info.legacy_output0_q00_equivalence_executed=false;
if nargout>=3
    assert(isequal(capture.requested_output_iq,y*2^(D-1)), ...
        'Padded transport crop differs from original shortest convolution output.');
    capture.requested_crop_equals_shortest_path=true;
end
info.stats=stats;
fields={'up_hb1','up_hb2','farrow_branch','farrow_horner','farrow_output','down_hb2','down_hb1'};
sat=stats.input_saturated_components;
peak=0;
for i=1:numel(fields)
    sat=sat+stats.(fields{i}).saturated_components;
    peak=max(peak,stats.(fields{i}).maximum_absolute_integer_accumulator);
end
info.total_saturated_components=sat;
info.maximum_absolute_integer_accumulator=peak;
info.whole_t07_pass=false;
info.rtl_bittrue_comparison_executed=false;
end

function [y,st]=firStage(x,h,up,down,shift,bits)
raw=upfirdn(x,h,up,down);
[y,st]=narrow(raw,shift,bits);
end
function [q,st]=narrow(x,shift,bits)
peak=max([abs(real(x(:)));abs(imag(x(:)))]);
assert(peak<2^53,'Integer arithmetic exceeds exact IEEE double domain.');
assert(all(real(x(:))==fix(real(x(:)))) && all(imag(x(:))==fix(imag(x(:)))), ...
    'A declared integer accumulator contains fractional data.');
a=rneShift(real(x),shift);b=rneShift(imag(x),shift);
lo=-2^(bits-1);hi=2^(bits-1)-1;
sat=nnz(a<lo | a>hi)+nnz(b<lo | b>hi);
q=complex(min(max(a,lo),hi),min(max(b,lo),hi));
st.maximum_absolute_integer_accumulator=peak;
st.saturated_components=sat;
st.output_bits=bits;st.shift=shift;
end
function q=rneShift(x,shift)
if shift==0
    q=floor(x);r=x-q;
    q=q+(r>.5 | (r==.5 & mod(q,2)~=0));
else
    scale=2^shift;q=floor(x/scale);r=x-q*scale;
    q=q+(r>scale/2 | (r==scale/2 & mod(q,2)~=0));
end
end
function q=integerRneShift(x,shift)
q=bitshift(x,-shift);rem=x-bitshift(q,shift);half=int64(2^(shift-1));
q=q+int64(rem>half | (rem==half & bitand(q,int64(1))~=0));
end
function s=emptyStat()
s.maximum_absolute_integer_accumulator=0;s.saturated_components=0;s.output_bits=0;s.shift=0;
end
function out=mergeStat(a,b)
out=b;
out.maximum_absolute_integer_accumulator=max(a.maximum_absolute_integer_accumulator,b.maximum_absolute_integer_accumulator);
out.saturated_components=a.saturated_components+b.saturated_components;
end


function capture=transportCapture(rawIQ,u2Full,u4Full,xFirst, ...
    outputFirst,outputCount,q0,k0,originalCount,G,stepInt,originInt,q1,q2,fq,C,D,M,R)
% This output describes accepted stream prefixes, not implicit FIR tail flushing.
rawCount=numel(rawIQ);
assert(mod(rawCount,4)==0,'RTL capture needs complete four-complex raw beats.');
assert(numel(u2Full)>=2*rawCount && numel(u4Full)>=4*rawCount);
u2=u2Full(1:2*rawCount);u4=u4Full(1:4*rawCount);
zCount=16*ceil(originalCount/16);
apriori=max(abs([k0 k0+zCount-1]))*abs(double(stepInt))+abs(double(originInt));
assert(apriori<2^62,'Padded int64 coordinate headroom is insufficient.');
z=complex(zeros(zCount,1));
phaseAll=zeros(zCount,1,'int64');baseAll=phaseAll;muAll=phaseAll;
baseBeforeAll=phaseAll;fracAll=phaseAll;muUnwrappedAll=phaseAll;
carryAll=false(zCount,1);requiredFirst=Inf;requiredLast=-Inf;
muMod=int64(2^M);pMin=Inf;pMax=-Inf;
stats.farrow_branch=emptyStat();stats.farrow_horner=emptyStat();stats.farrow_output=emptyStat();
stats.mu_carry_count=0;
chunk=65536;
for first=1:chunk:zCount
    last=min(first+chunk-1,zCount);
    k=int64(k0+(first-1:last-1).');
    phase=k.*stepInt+originInt;
    base=bitshift(phase,-R);frac=phase-bitshift(base,R);
    mu=integerRneShift(frac,R-M);
    baseBeforeAll(first:last)=base;fracAll(first:last)=frac;
    muUnwrappedAll(first:last)=mu;
    carry=mu==muMod;base=base+int64(carry);mu(carry)=0;
    stats.mu_carry_count=stats.mu_carry_count+nnz(carry);
    phaseAll(first:last)=phase;baseAll(first:last)=base;muAll(first:last)=mu;
    carryAll(first:last)=carry;
    base=double(base);mu=double(mu);
    assert(min(base)-1>=0 && max(base)+2<numel(u4),'Missing real input stream prefix for padded request.');
    indexes=base+[-1 0 1 2];
    [lo,hi]=checkRawSupport(indexes,q1,q2,rawCount,xFirst);
    requiredFirst=min(requiredFirst,lo);requiredLast=max(requiredLast,hi);
    sampleMatrix=[u4(base) u4(base+1) u4(base+2) u4(base+3)];
    rawBranch=sampleMatrix*fq;
    [branches,st]=narrow(rawBranch,C-2,D+3);
    stats.farrow_branch=mergeStat(stats.farrow_branch,st);
    value=branches(:,4);
    for order=3:-1:1
        raw=value.*mu+branches(:,order)*2^M;
        [value,st]=narrow(raw,M,D+3);
        stats.farrow_horner=mergeStat(stats.farrow_horner,st);
    end
    [z(first:last),st]=narrow(value,0,D);
    stats.farrow_output=mergeStat(stats.farrow_output,st);
    pMin=min(pMin,min(base)-1);pMax=max(pMax,max(base)+2);
end
[v2Full,down2FullStats]=firStage(z,q2,1,2,C-1,D);
v2=v2Full(1:zCount/2);
[vFull,down1FullStats]=firStage(v2,q1,1,2,C-1,D);
v=vFull(1:zCount/4);
assert(G+outputCount<=numel(v));
capture.schema='t07_guard_window_padded_stream_capture_v1';
capture.profile=struct('coefficient_bits',C,'data_bits',D,'mu_bits',M,'ratio_bits',R);
capture.raw_first=xFirst;capture.raw_last=xFirst+rawCount-1;
capture.raw_iq=rawIQ;capture.raw_external_fractional_bits=15;
capture.up2_iq=u2;capture.u4_iq=u4;capture.internal_fractional_bits=D-1;
capture.original_z_count=originalCount;capture.request_count=zCount;
capture.transport_extension_count=zCount-originalCount;
capture.transport_extension_rule='Real phase continuation and existing nonzero-tap raw support; never zero padding';
capture.request_j=(0:zCount-1).';capture.request_k=int64(k0)+int64(capture.request_j);
capture.phase=phaseAll;capture.base_before=baseBeforeAll;capture.frac=fracAll;
capture.mu_unwrapped=muUnwrappedAll;capture.carry=carryAll;
capture.base=baseAll;capture.mu=muAll;
capture.transport_extension=capture.request_j>=originalCount;
capture.step_integer=stepInt;capture.origin_integer=originInt;
capture.output_first=outputFirst;capture.output_count=outputCount;capture.q0_raw_samples=q0;
capture.farrow_iq=z;capture.down15_iq=v2;capture.physical_down47_iq=v;
capture.requested_output_iq=v(G+(1:outputCount));
capture.requested_output_first_physical_index=G;
capture.requested_output_last_physical_index=G+outputCount-1;
capture.physical_output_beat=(0:numel(v)/4-1).';
physicalIndex=(0:numel(v)-1).';
requested=physicalIndex>=G & physicalIndex<G+outputCount;
capture.physical_requested_mask=reshape(requested,4,[]).'*(2.^(0:3)).';
capture.physical_pre_crop_count=G;
capture.physical_post_crop_count=numel(v)-G-outputCount;
capture.physical_tail_guard_qualified=false;
capture.window_first=pMin;capture.window_last=pMax;
capture.required_raw_first=requiredFirst;capture.required_raw_last=requiredLast;
capture.all_padded_requested_raw_support_present=true;
capture.farrow_padded_stats=stats;
capture.down_hb2_full_convolution_stats=down2FullStats;
capture.down_hb1_full_convolution_stats=down1FullStats;
capture.fir_stats_scope='Full upfirdn convolution statistics; accepted-prefix counts are separately captured';
% Reapply the unchanged narrowing to actual accepted FIR prefixes for SAT audit.
raw=upfirdn(rawIQ*2^(D-16),q1,2,1);
[checked,transportStats.up_hb1]=narrow(raw(1:2*rawCount),C-2,D);
assert(isequal(checked,u2));
raw=upfirdn(u2,q2,2,1);
[checked,transportStats.up_hb2]=narrow(raw(1:4*rawCount),C-2,D);
assert(isequal(checked,u4));
raw=upfirdn(z,q2,1,2);
[checked,transportStats.down_hb2]=narrow(raw(1:zCount/2),C-1,D);
assert(isequal(checked,v2));
raw=upfirdn(v2,q1,1,2);
[checked,transportStats.down_hb1]=narrow(raw(1:zCount/4),C-1,D);
assert(isequal(checked,v));
transportStats.farrow_branch=stats.farrow_branch;
transportStats.farrow_horner=stats.farrow_horner;
transportStats.farrow_output=stats.farrow_output;
capture.transport_narrow_stats=transportStats;
capture.transport_stats_scope='All accepted FIR prefixes and all padded Farrow branch/Horner/output narrowings';
capture.coefficients=struct('q47',q1(:),'q15',q2(:),'farrow_matrix',fq);
capture.stream_complex_counts=struct('raw',rawCount,'up47',numel(u2),'up15',numel(u4), ...
    'farrow',numel(z),'down15',numel(v2),'down47',numel(v));
capture.stream_temporal_lanes=struct('raw',4,'up47',8,'up15',16,'farrow',16,'down15',8,'down47',4);
capture.rtl_comparison_executed=false;capture.whole_t07_pass=false;
end

function [lo,hi]=checkRawSupport(indexes,q47,q15,rawCount,rawFirst)
[a,b]=ndgrid(find(q47~=0)-1,find(q15~=0)-1);
offsets=unique(2*a(:)+b(:));p=indexes(:);
lo=Inf;hi=-Inf;
for offset=offsets.'
    active=mod(p-offset,4)==0;
    rawIndexes=(p(active)-offset)/4;
    if ~isempty(rawIndexes)
        assert(all(rawIndexes>=0 & rawIndexes<rawCount), ...
            'Requested Farrow sample requires unavailable real raw context.');
        lo=min(lo,min(rawIndexes));hi=max(hi,max(rawIndexes));
    end
end
assert(isfinite(lo) && isfinite(hi));
lo=lo+rawFirst;hi=hi+rawFirst;
end

