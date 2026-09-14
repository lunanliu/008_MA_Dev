import os
os.environ["OPENBLAS_NUM_THREADS"]="1"
os.environ["OMP_NUM_THREADS"]="1"
"""Independent saved-result review; no MATLAB/Vivado execution."""
from pathlib import Path
import sys, json, hashlib, csv, math, statistics, datetime
from decimal import Decimal, localcontext
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"reports/t09/design/review_python_deps"))
import numpy as np
import scipy, h5py
from scipy.io import loadmat
A=ROOT/"reports/t09/execution/T09_STATS006/attempt_20260908T223909180Z_luna"
PKG=ROOT/"reports/t09/design/T09_STATS006/package"
OUT=ROOT/"reports/t09/design/T09_STATS006/INDEPENDENT_REVIEW.json"
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p): return json.loads(Path(p).read_text(encoding="utf-8-sig"))
def must(ok,note):
    if not ok: raise AssertionError(note)
def harray(f,key):
    a=np.asarray(f[key])
    if a.dtype.fields and "real" in a.dtype.fields:
        a=a["real"]+1j*a["imag"]
    return a.T
def near(actual,expected,limit,note):
    error=float(np.max(np.abs(np.asarray(actual)-np.asarray(expected))))
    must(error<=limit,f"{note}: {error} exceeds {limit}")
    return error
def round_fraction_even(num,den):
    q,r=divmod(abs(num),den)
    q+=int(2*r>den or (2*r==den and q%2))
    return -q if num<0 else q
def dtp(q,k,t,z):
    length=1024*z
    spectrum=np.zeros((length,74),complex)
    spectrum[np.mod(k//2,length)]=q
    power=np.abs(np.fft.ifft(spectrum,axis=0)*length/820)**2
    offsets=np.arange(-24*z,24*z+1)
    rows=offsets%length
    local=power[rows].argmax(axis=0)
    chosen=rows[local];cols=np.arange(74)
    pa=power[(chosen-1)%length,cols]
    pb=power[chosen,cols]
    pc=power[(chosen+1)%length,cols]
    curvature=pa-2*pb+pc
    with np.errstate(invalid="ignore",divide="ignore"):
        delta=(pa-pc)/(2*curvature)
    interp=np.isfinite(delta)&(curvature<0)&(np.abs(delta)<=.5)
    delta=np.where(interp,delta,0)
    grid_delay=offsets[local]/z
    axis=np.arange(length)/z
    axis=np.where(axis>=512,axis-1024,axis)
    ratio=np.empty(74)
    for col in range(74):
        far=np.abs((axis-grid_delay[col]+512)%1024-512)>4
        ratio[col]=10*np.log10(pb[col]/max(float(power[far,col].max()),np.finfo(float).tiny))
    estimates=[]
    for interpolate in (False,True):
        delay=grid_delay+(delta/z if interpolate else 0)
        tc=t-t.mean();dc=delay-delay.mean()
        beta=float(np.dot(tc,dc)/np.dot(tc,tc))
        ppm=beta/(1-beta)*1e6
        rmse=float(np.sqrt(np.mean((dc-beta*tc)**2)))
        valid_symbol=(ratio>=3)&(local>0)&(local<len(rows)-1)
        if interpolate: valid_symbol &=interp
        valid=bool(valid_symbol.all() and abs(delay[0])<=4 and rmse<=.25 and np.abs(np.diff(delay)).max()<=1)
        estimates.append(dict(ppm=ppm,beta=beta,delay=delay,ratio=ratio,rmse=rmse,
                              valid=valid,valid_symbol=valid_symbol))
    return estimates
def quotient(y,first,p,bins,k,symbols,cfo=0):
    coords=(10+symbols[None,:])*2560+384+np.arange(2048)[:,None]
    windows=y[coords-first]*np.exp(-2j*np.pi*cfo*coords/500e6)
    q=np.fft.fft(windows,axis=0)[bins-1]*np.exp(2j*np.pi*k[:,None]/16)/p
    return q,windows
def true_rate(physical_ppm,step1,step2=2**28):
    with localcontext() as ctx:
        ctx.prec=50
        a=Decimal(str(physical_ppm))/Decimal(10**6)+1
        b=Decimal(int(step1))*Decimal(int(step2))/Decimal(2**56)
        return float((a/b-1)*Decimal(10**6))

from scipy.signal import czt
import time
started=time.monotonic()
manifest=read(PKG/"manifest.json")
must(sha(PKG/"manifest.json")=="271EAFE985DA24E9E56254C7766ADF1DD88AA8C9A8B89931E81CF695813CDC07","package identity")
for f in manifest["files"]:
    p=PKG/f["path"];must(p.stat().st_size==f["bytes"] and sha(p)==f["sha256"],str(p))
complete=read(A/"COMPLETE.json")
must(complete["complete"] and not complete["T09_PASS"] and sha(A/"result_manifest.json")==complete["result_manifest_sha256"],"completion and result manifest")
files=read(A/"result_manifest.json")
for f in files:
    p=A/f["path"];must(p.stat().st_size==f["bytes"] and sha(p)==f["sha256"],str(p))
exit_record=read(A/"supervisor_exit.json")
must(sha(A/"supervisor_exit.json")==complete["supervisor_exit_sha256"] and exit_record["root"]["returncode"]==0 and exit_record["owned_active_processes_after"]==0 and not exit_record["timed_out"],"native execution")
summary=read(A/"results/summary.json")
must(summary["case_count"]==300 and summary["estimate_count"]==600 and len(summary["groups"])==60 and not summary["second_resampler_executed"] and not summary["T09_PASS"],"statistics scope")
contract=loadmat(A/"results/pilot_contract.mat",simplify_cells=True)
P=contract["P"];k=contract["k"].astype(int).ravel();bins=contract["bins"].astype(int).ravel()
symbols=contract["symbols"].astype(int).ravel();t=contract["times"].ravel()
must(np.array_equal(symbols,np.arange(0,512,7)) and np.array_equal(t,(10+symbols)*2560+384+1023.5),"74 true pilot times")
ks=np.arange(-1024,1024)[:,None];n=np.arange(2048)[:,None]
starts=(10+symbols)*2560+384;useful=(10+symbols)*2560+512
cache={};rows=[];errors=dict(quotient=0.,delay_samples=0.,ppm=0.,ideal_step_ppm=0.,noise_power_relative=0.,measured_snr_db=0.)
for ci in range(1,301):
    folder=A/"results"/f"case_{ci:03d}";r=read(folder/"result.json");c=r["definition"]
    must(c["residual_ppm"] in (-5,-1,0,1,5) and c["cfo_hz"]==100000 and c["delay_origin"]==.37,"stimulus domain")
    seeds=range(31001,31011) if c["family"]=="paper_reference" else range(41001,41011)
    must(c["seed"] in seeds and c["channel_seed"]==c["seed"] and c["noise_seed"]==909200+c["seed"] and c["payload_seed"]==909001+c["seed"],"explicit seed mapping")
    if c["payload_seed"] not in cache:
        p=loadmat(A/"results/payload_inputs"/f'seed_{c["payload_seed"]}.mat',simplify_cells=True)
        must(p["payloadSeed"]==c["payload_seed"],"payload identity")
        cache[c["payload_seed"]]=p["X"]
    X=cache[c["payload_seed"]]
    must(np.allclose(X[bins-1],P,atol=0,rtol=0),"actual production pilots")
    m=loadmat(folder/"nodes.mat",simplify_cells=True)
    windows=m["windows"];q=m["Q"];ev=m["windowEvidence"]
    qcalc=np.fft.fft(windows,axis=0)[bins-1]*np.exp(2j*np.pi*k[:,None]/16)/P
    errors["quotient"]=max(errors["quotient"],near(qcalc,q,1e-10,"FFT/quotient"))
    alpha=1/(1+c["residual_ppm"]*1e-6)
    delays=np.atleast_1d(ev["tap_delays"]).ravel();gains=np.atleast_1d(ev["tap_gains"]).ravel()
    doppler=np.atleast_1d(ev["tap_doppler_hz"]).ravel()
    local=alpha*starts-useful
    bounds=np.column_stack((local-delays.max(),local+alpha*2047-delays.min()))
    near(bounds,ev["source_bounds"],1e-9,"actual CP support")
    must(bounds[:,0].min()>=-512 and bounds[:,1].max()<=2047,"CP support")
    reference_power=(1640/2048**2)*abs(gains[0])**2
    expected_noise=reference_power*10**(-c["snr_db"]/10)
    near(expected_noise,r["noise"]["expected_noise_power"],1e-15,"LoS-referenced noise power")
    H=np.exp(-2j*np.pi*ks*delays[None,:]/2048)@(gains[:,None]*np.exp(2j*np.pi*doppler[:,None]*(starts[None,:]+1023.5)/500e6))
    F=np.fft.fftshift(X,axes=0)*H*np.exp(2j*np.pi*ks*local[None,:]/2048)
    clean=czt(F,m=2048,w=np.exp(2j*np.pi*alpha/2048),a=1,axis=0)*np.exp(-2j*np.pi*1024*alpha*n/2048)/2048
    clean*=np.exp(2j*np.pi*c["cfo_hz"]*(starts[None,:]+n)/500e6)
    measured=float(np.mean(np.abs(windows-clean)**2))
    relative=abs(measured-r["noise"]["measured_noise_power"])/r["noise"]["measured_noise_power"]
    must(relative<1e-7,"independently reconstructed noise power")
    errors["noise_power_relative"]=max(errors["noise_power_relative"],relative)
    measured_snr=10*math.log10(reference_power/measured)
    errors["measured_snr_db"]=max(errors["measured_snr_db"],near(measured_snr,r["noise"]["measured_reference_snr_db"],1e-6,"measured SNR"))
    for ei,z in enumerate((2,4)):
        calc=dtp(qcalc,k,t,z)[1];ref=r["estimates"][ei]
        must(ref["padding"]==z and ref["method"]=="parabolic_power","selected candidates")
        errors["delay_samples"]=max(errors["delay_samples"],near(calc["delay"],ref["delay_samples"],1e-9,"delay"))
        errors["ppm"]=max(errors["ppm"],near(calc["ppm"],ref["ppm"],1e-9,"LS ppm"))
        must(calc["valid"]==ref["valid"] and np.array_equal(calc["valid_symbol"],ref["valid_per_symbol"]),"quality flags")
        step=round((1+calc["ppm"]*1e-6)*2**28)
        must(step==ref["step_q28"],"Q28 RNE step")
        ideal=true_rate(c["residual_ppm"],step)
        errors["ideal_step_ppm"]=max(errors["ideal_step_ppm"],near(ideal,ref["ideal_step_residual_ppm"],1e-9,"ideal rate"))
        rows.append(dict(case_id=ci,family=c["family"],snr_db=c["snr_db"],residual_ppm=c["residual_ppm"],seed=c["seed"],padding=z,valid=calc["valid"],ppm=calc["ppm"],ideal=ideal))
    if ci%50==0:print(json.dumps(dict(reviewed_cases=ci,elapsed_seconds=round(time.monotonic()-started,2))),flush=True)
group_errors=0.;all_pass=True
for g in summary["groups"]:
    selected=[r for r in rows if all(r[f]==g[f] for f in ("family","snr_db","residual_ppm","padding"))]
    must(len(selected)==10 and len({r["seed"] for r in selected})==10,"10 distinct seeds")
    usable=[r["ideal"] for r in selected if r["valid"]]
    must(g["valid_count"]==len(usable) and g["invalid_count"]==10-len(usable),"valid count")
    mae=statistics.mean(abs(x) for x in usable) if usable else None
    if usable:group_errors=max(group_errors,near(mae,g["valid_mean_absolute_ideal_step_ppm"],1e-9,"group MAE"))
    passed=len(usable)==10 and mae<.1
    must(passed==g["conditional_float_target_met"],"group gate")
    all_pass &=passed
by_padding={}
for z in (2,4):
    groups=[g for g in summary["groups"] if g["padding"]==z]
    by_padding[str(z)]=dict(worst_group_mae=max(g["valid_mean_absolute_ideal_step_ppm"] for g in groups),worst_sample=max(abs(r["ideal"]) for r in rows if r["padding"]==z),overall_mae=statistics.mean(abs(r["ideal"]) for r in rows if r["padding"]==z))
analyzer=read(A/"results/code_analyzer.json")
must(analyzer["entry"]["id"]=="MSNU" and analyzer["entry"]["line"]==48,"only obsolete NASGU suppression")
out=dict(status="ACCEPT_CONDITIONAL_FLOATING_STATISTICS_300_CASES",package_files_verified=len(manifest["files"]),result_files_verified=len(files),windows_independently_fft_checked=300*74,delays_and_ls_checked=600,clean_window_noise_power_reconstructed_with_independent_scipy_czt=True,maximum_numerical_difference=errors,maximum_group_mae_difference=group_errors,statistical_groups_verified=60,all_groups_pass=bool(all_pass),by_padding=by_padding,payload_matrices_verified=len(cache),analyzer_note="MSNU at line48 is obsolete NASGU suppression on payloadSeed; remove in a future source revision, do not rerun completed statistics",review_elapsed_seconds=time.monotonic()-started,matlab_elapsed_seconds=summary["elapsed_seconds"],physical_upstream_closed_loop_qualified=False,actual_second_resampler_executed=False,fixed_point_qualified=False,T09_PASS=False,summary_sha256=sha(A/"results/summary.json"),result_manifest_sha256=sha(A/"result_manifest.json"),script_sha256=sha(Path(__file__)))
OUT.write_text(json.dumps(out,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps(out,ensure_ascii=False,indent=2))
