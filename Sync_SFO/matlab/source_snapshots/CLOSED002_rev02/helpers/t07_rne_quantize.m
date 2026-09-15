function [y,info]=t07_rne_quantize(x,bits,fractionalBits)
%T07_RNE_QUANTIZE Signed saturating round-to-nearest ties-to-even.
assert(bits>=2 && fractionalBits>=0 && fractionalBits<bits);
scaled=x*2^fractionalBits;
if isreal(x)
    [y,sat]=realRne(scaled,bits);
else
    [a,sa]=realRne(real(scaled),bits);[b,sb]=realRne(imag(scaled),bits);
    y=complex(a,b);sat=sa+sb;
end
y=y/2^fractionalBits;
info.saturated_component_count=sat;
info.bits=bits;info.fractional_bits=fractionalBits;
info.rounding='RNE ties-to-even';info.overflow='signed saturate';
end
function [q,sat]=realRne(x,bits)
q=floor(x);d=x-q;
q=q+(d>0.5 | (d==0.5 & mod(q,2)~=0));
lo=-2^(bits-1);hi=2^(bits-1)-1;
sat=nnz(q<lo | q>hi);
q=min(max(q,lo),hi);
end

