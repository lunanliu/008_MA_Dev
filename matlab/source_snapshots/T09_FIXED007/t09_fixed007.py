"""Bounded T09 fixed arithmetic study. Execution belongs to sole T09 Luna."""
import os
os.environ["OPENBLAS_NUM_THREADS"]="1"
os.environ["OMP_NUM_THREADS"]="1"
from pathlib import Path
import sys, json, hashlib, time, math, csv, traceback, argparse
R=Path(__file__).resolve().parent
# NumPy/SciPy are supplied by the selected Python environment, not an old checkout.
import numpy as np
import scipy
from scipy.io import loadmat
from t09_xfft_cmodel007 import XFFT

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p): return json.loads(Path(p).read_text(encoding="utf-8-sig"))
def write(p,x):
    t=Path(str(p)+".tmp");t.write_text(json.dumps(x,indent=2,allow_nan=False)+"\n",encoding="utf8");t.replace(p)
def rne(n,d):
    n=int(n);d=int(d);assert d>0
    q,r=divmod(abs(n),d);q+=2*r>d or (2*r==d and q%2==1)
    return -q if n<0 else q
def bound(v,bits,signed=True):
    a=np.asarray(v);low=-(1<<(bits-1)) if signed else 0;high=(1<<(bits-int(signed)))-1
    assert np.all(a>=low) and np.all(a<=high),f"{bits}-bit range"
def normalize(v,g):
    if g>=0: return v*(1<<g)
    return np.fromiter((rne(x,1<<(-g)) for x in v.ravel()),np.int64).reshape(v.shape)

def backend(dtp):
    # IFFT output S16; power U32; interpolation Q16; signed delay S24 F16.
    assert dtp.shape==(2048,74,2)
    power=np.sum(dtp*dtp,axis=2);bound(power,32,False)
    offsets=np.arange(-48,49);rows=offsets%2048
    selected=np.argmax(power[rows],axis=0);bins=rows[selected]
    delay=[];valids=[];ratios=[];triplets=[];deltas=[]
    threshold=math.ceil(10**(3/10)*(1<<24))
    for j in range(74):
        p=int(bins[j]);a,b,c=[int(power[(p+u)%2048,j]) for u in (-1,0,1)]
        curv=a-2*b+c;num=a-c
        interpolated=curv<0 and abs(num)<=-curv
        delta=rne(-num*(1<<16),-2*curv) if interpolated else 0
        dq=rne(int(offsets[selected[j]])*(1<<16)+delta,2)
        far=np.abs((np.arange(2048)-p+1024)%2048-1024)>8
        competing=int(np.max(power[far,j]))
        ratio_ok=b>0 and b*(1<<24)>=competing*threshold
        valid=ratio_ok and 0<int(selected[j])<96 and interpolated
        delay.append(dq);valids.append(bool(valid));deltas.append(delta)
        triplets.append([a,b,c,competing])
        ratios.append(10*math.log10(b/max(competing,1e-300)) if b else None)
    bound(delay,24);bound(deltas,18)
    w=list(range(-73,74,2));sw2=sum(x*x for x in w);sd=sum(delay)
    swd=sum(x*y for x,y in zip(w,delay));sd2=sum(x*x for x in delay)
    bound([sd,swd],40)
    bn=2*swd;bd=17920*sw2*(1<<16)
    numerator=bn*1000000*(1<<18);denominator=bd-bn
    bound([numerator],80);bound([denominator],49,False)
    assert denominator>0
    ppm_code=rne(numerator,denominator);bound([ppm_code],32)
    step=(1<<28)+rne(ppm_code*16,15625);bound([step],32,False)
    sse_num=74*sw2*sd2-sw2*sd*sd-74*swd*swd
    assert sse_num>=0
    rmse_ok=16*sse_num<=74*(74*sw2)*(1<<32)
    rmse=math.sqrt(sse_num/(74*74*sw2))/(1<<16)
    jump=max(abs(b-a) for a,b in zip(delay[:-1],delay[1:]))
    valid=all(valids) and abs(delay[0])<=4*(1<<16) and rmse_ok and jump<=(1<<16)
    return dict(ppm_code_q18=ppm_code,ppm=ppm_code/(1<<18),step_q28=step,
                delay_q16=delay,delta_bin_q16=deltas,peak_triplets_and_competitor=triplets,
                peak_ratio_db=ratios,quality_ratio_q24=threshold,valid_per_symbol=valids,
                valid_symbols=sum(valids),valid=bool(valid),fit_rmse_samples=rmse,
                ls_weighted_delay=swd,ls_delay_sum=sd,ls_weight_square_sum=sw2,
                beta_numerator=bn,beta_denominator=bd,sse_numerator=str(sse_num),
                max_adjacent_jump_samples=jump/(1<<16))

def validate_controls(pkg,out,main,aux):
    records=[];meta=read(pkg/"controls/controls.json")
    for c in meta["controls"]:
        v=np.load(pkg/c["path"])
        model=main if c["engine"]=="main" else aux
        y,ov=model.transform(v["input"],c["forward"],c["schedule"])
        exact=np.array_equal(y,v["expected"])
        record=dict(id=c["id"],engine=c["engine"],length=len(y),exact_equal=bool(exact),
                    max_abs_error=int(np.max(np.abs(y-v["expected"]))),overflow=ov)
        records.append(record)
        write(out/"bridge_controls.json",dict(complete=False,controls=records))
        assert exact and ov==0,f"C-model differs from existing official XSim: {c['id']}"
    # Exact signed midpoint, carry and large-integer controls for own scalar arithmetic.
    pairs=[(1,2,0),(3,2,2),(-1,2,0),(-3,2,-2),(5,2,2),(-5,2,-2),
           (7,2,4),(-7,2,-4),((1<<70)+1,2,1<<69)]
    for a,b,e in pairs: assert rne(a,b)==e
    # 74-point integer LS checks use exact grid-moving synthetic impulses:
    # complete zeros must produce invalid quality, never a valid numerical estimate.
    zero=backend(np.zeros((2048,74,2),np.int64));assert not zero["valid"] and zero["ppm_code_q18"]==0
    write(out/"bridge_controls.json",dict(complete=True,controls=records,rounding_controls=len(pairs),
        zero_quality_invalid=True,auxiliary_production_2048_inverse_xsim_matched=False))

def run(pkg,out):
    started=time.perf_counter()
    manifest=read(pkg/"manifest.json")
    for f in manifest["files"]: assert sha(pkg/f["path"])==f["sha256"],f["path"]
    out.mkdir(parents=True,exist_ok=False)
    main=XFFT(pkg/"vendor",11,False);aux=XFFT(pkg/"vendor",14,True)
    results=[]
    try:
        validate_controls(pkg,out,main,aux)
        config=read(pkg/"study.json");contract=loadmat(pkg/"inputs/pilot_contract.mat",simplify_cells=True)
        for ci,c in enumerate(config["cases"],1):
            folder=out/f"case_{ci:03d}";folder.mkdir()
            n=loadmat(pkg/c["nodes"],simplify_cells=True)
            if c["domain"]=="conditional":
                windows=n["windows"];P=contract["P"];k=contract["k"].astype(int);times=contract["times"]
                reference=n["est"][0]
            else:
                windows=n["windows1"];P=n["P"];k=n["k"].astype(int);times=n["times"];reference=n["first"][1]
            assert windows.shape==(2048,74) and P.shape==(820,74)
            assert np.array_equal(np.diff(times),np.full(73,17920))
            raw=np.stack((windows.real,windows.imag),axis=2)*c["input_code_scale"]
            rounded=np.rint(raw);clip=int(np.count_nonzero((rounded<-32768)|(rounded>32767)))
            codes=np.clip(rounded,-32768,32767).astype(np.int64)
            fft=np.empty_like(codes);main_overflow=[]
            for j in range(74):
                fft[:,j],ov=main.transform(codes[:,j],True);main_overflow.append(ov)
            # Combine A128 exactly once with unit QPSK conjugation. Eighth roots use S18 F16.
            rotation=np.exp(2j*np.pi*k[:,None]/16)/P
            coef=np.rint(np.stack((rotation.real,rotation.imag),axis=2)*(1<<16)).astype(np.int64)
            bound(coef,18)
            assert np.max(np.abs(np.abs(rotation)-1))<1e-12
            f=fft[k%2048]
            nr=f[:,:,0]*coef[:,:,0]-f[:,:,1]*coef[:,:,1]
            ni=f[:,:,0]*coef[:,:,1]+f[:,:,1]*coef[:,:,0]
            bound(nr,35);bound(ni,35)
            rot=normalize(np.stack((nr,ni),axis=2),-16);bound(rot,18)
            branch_results=[]
            save=dict(input_codes=codes.astype(np.int16),main_fft=fft.astype(np.int16),
                      rotation_coeff_q16=coef.astype(np.int32),quotient_codes=rot.astype(np.int32))
            for mode in ("unity","pow2_headroom"):
                grid=np.zeros((2048,74,2),np.int64);gains=[];aux_overflow=[];dtp=np.empty_like(grid)
                for j in range(74):
                    v=rot[:,j];gain=0
                    if mode=="pow2_headroom":
                        eligible=[g for g in range(-2,13) if np.max(np.abs(normalize(v,g)))<=16383]
                        assert eligible;gain=max(eligible)
                    normalized=normalize(v,gain);bound(normalized,16)
                    grid[(k//2)%2048,j]=normalized;gains.append(gain)
                    dtp[:,j],ov=aux.transform(grid[:,j],False);aux_overflow.append(ov)
                b=backend(dtp)
                arithmetic_valid=b["valid"]
                b.update(mode=mode,arithmetic_quality_valid=arithmetic_valid,input_clip_components=clip,
                    main_fft_overflow_symbols=sum(main_overflow),aux_ifft_overflow_symbols=sum(aux_overflow),
                    normalization_shifts=gains,aux_input_max_abs=int(np.max(np.abs(grid))),
                    ifft_output_max_abs=int(np.max(np.abs(dtp))),
                    reference_float_ppm=float(reference["ppm"]),reference_float_valid=bool(reference["valid"]),
                    fixed_minus_float_ppm=b["ppm"]-float(reference["ppm"]),
                    maximum_delay_difference_samples=float(np.max(np.abs(np.asarray(b["delay_q16"])/(1<<16)-np.ravel(reference["delay_samples"])))))
                b["valid"]=bool(arithmetic_valid and not clip and not any(main_overflow) and not any(aux_overflow))
                b["ideal_step_residual_ppm"]=((1+c["input_residual_ppm"]*1e-6)/(b["step_q28"]/(1<<28))-1)*1e6
                b["single_case_research_target"]=bool(b["valid"] and abs(b["ideal_step_residual_ppm"])<.1)
                branch_results.append(b)
                save[mode+"_ifft_input"]=grid.astype(np.int16);save[mode+"_ifft_output"]=dtp.astype(np.int16)
            np.savez_compressed(folder/"integer_nodes.npz",**save)
            rec=dict(case_id=ci,definition=c,branches=branch_results,second_resampler_executed=False)
            write(folder/"result.json",rec);results.append(rec)
            write(out/"progress.json",dict(completed_cases=ci,total_cases=len(config["cases"]),elapsed_seconds=time.perf_counter()-started))
            print(f"T09_FIXED007_CASE {ci}/{len(config['cases'])}",flush=True)
        summary=dict(schema="T09_FIXED007_v1",status="BOUNDED_OFFICIAL_CMODEL_AND_INTEGER_STUDY_COMPLETE",
            case_count=len(results),branch_count=2,results=results,elapsed_seconds=time.perf_counter()-started,
            numpy_version=np.__version__,scipy_version=scipy.__version__,python_version=sys.version,
            actual_matlab_or_vivado_executed=False,aux_2048_inverse_production_xsim_qualified=False,
            full_statistics_fixed_point_qualified=False,actual_second_resampler_executed=False,T09_PASS=False)
        write(out/"summary.json",summary);write(out/"completion.json",dict(complete=True,T09_PASS=False))
    except Exception as e:
        write(out/"failure.json",dict(type=type(e).__name__,message=str(e),traceback=traceback.format_exc(),elapsed_seconds=time.perf_counter()-started))
        raise
    finally:
        main.close();aux.close()

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--package",required=True);p.add_argument("--output",required=True)
    a=p.parse_args();run(Path(a.package),Path(a.output))