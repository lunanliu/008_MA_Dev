function C=t07_lagrange_coefficients(taps)
%T07_LAGRANGE_COEFFICIENTS Ascending mu powers for an even-tap Lagrange bank.
assert(any(taps==[4 6 8]));
nodes=(-taps/2+1):(taps/2);
C=zeros(taps,taps);
for j=1:taps
    other=nodes;other(j)=[];
    C(j,:)=fliplr(poly(other)/prod(nodes(j)-other));
end
end

