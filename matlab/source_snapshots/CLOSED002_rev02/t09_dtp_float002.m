function estimates=t09_dtp_float002(Q,k,times)
estimates=cell(8,1);counter=0;
for z=[2 4 8 16]
    L=1024*z;grid=complex(zeros(L,74));grid(mod(k/2,L)+1,:)=Q;
    D=ifft(grid,[],1)*L/820;power=abs(D).^2;
    candidates=(-24*z:24*z).';indices=mod(candidates,L)+1;
    [peak,localIndex]=max(power(indices,:),[],1);loc=indices(localIndex);loc=loc(:).';
    delayInteger=candidates(localIndex)/z;delayInteger=delayInteger(:).';
    columns=(0:73)*L;
    a=power(mod(loc-2,L)+1+columns);b=power(loc+columns);cc=power(mod(loc,L)+1+columns);
    curvature=a-2*b+cc;delta=0.5*(a-cc)./curvature;
    interpolationOK=isfinite(delta)&curvature<0&abs(delta)<=0.5;delta(~interpolationOK)=0;
    ratio=zeros(1,74);
    delayAxis=(0:L-1).'/z;delayAxis(delayAxis>=512)=delayAxis(delayAxis>=512)-1024;
    for jj=1:74
        far=abs(mod(delayAxis-delayInteger(jj)+512,1024)-512)>4;
        ratio(jj)=10*log10(peak(jj)/max(max(power(far,jj)),realmin));
    end
    for method=1:2
        counter=counter+1;delay=delayInteger;
        if method==2,delay=delay+delta/z;name='parabolic_power';else,name='grid_peak';end
        validSymbol=ratio>=3 & localIndex>1 & localIndex<numel(indices);
        if method==2,validSymbol=validSymbol & interpolationOK;end
        tc=times-mean(times);dc=delay(:)-mean(delay);
        beta=(tc.'*dc)/(tc.'*tc);ppm=beta/(1-beta)*1e6;
        fit=mean(delay)+beta*tc;rmse=sqrt(mean((delay(:)-fit).^2));
        endpoint=(delay(end)-delay(1))/(times(end)-times(1));
        endpointPlus1=(delay(end)-delay(1))/(2560*(511+1));
        estimates{counter}=struct('padding',z,'ifft_length',L,'method',name,'ppm',ppm, ...
            'beta_samples_per_sample',beta,'paper_linear_ppm',beta*1e6, ...
            'delay_samples',delay,'valid_per_symbol',validSymbol,'peak_ratio_db',ratio, ...
            'valid_symbols',sum(validSymbol),'valid',all(validSymbol)&&abs(delay(1))<=4&&rmse<=0.25&& ...
            max(abs(diff(delay)))<=1,'fit_rmse_samples',rmse,'observation_count',74, ...
            'endpoint_actual_span_ppm',endpoint/(1-endpoint)*1e6, ...
            'endpoint_paper_plus1_ppm',endpointPlus1*1e6);
    end
end
estimates=vertcat(estimates{:});
end


