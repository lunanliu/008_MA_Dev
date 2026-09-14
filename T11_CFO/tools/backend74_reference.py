"""Frozen 74-point estimator backend: integer quality and actual phase/FFT merge."""
from pathlib import Path
import runpy,json,hashlib
R=Path(__file__).resolve().parents[1]
f=runpy.run_path(str(R/'tools/fft256_reference.py'));p=runpy.run_path(str(R/'tools/phase74_reference.py'))
rne=f['rne'];pack=f['pack']
def estimator(z):
 phase=p['phase74']([tuple(x) for x in z]);ex,u=f['normalize'](z)
 nz=any(a or b for a,b in z)
 if not nz:return dict(nonzero=False,exponent=0,normalized=[],fft=[],power=[],peak_bin=0,delta_q16=0,peak=0,secondary=0,energy=0,fft_saturations=0,normal_saturations=0,coherent=False,unambiguous=False,spectrum=False,phase=phase,fft_q16=0,consistent=False,mode=3,valid=False,frequency_q16=0)
 fft=f['fft256'](u+[[0,0]]*182);V=fft['output'];power=[a*a+b*b for a,b in V];peakbin=max(range(256),key=power.__getitem__);peak=power[peakbin]
 secondary=max([v for j,v in enumerate(power) if 4<(j-peakbin)%256<252]);energy=sum(a*a+b*b for a,b in u)
 coherent=5*65536*peak>=74*energy;unambiguous=4*secondary<=peak;spectrum=coherent and unambiguous and fft['saturations']==0
 l,rr=power[(peakbin-1)%256],power[(peakbin+1)%256];den=2*peak-l-rr
 delta=max(-32768,min(32768,rne((rr-l)*32768,den))) if den>0 else 0
 bn=peakbin if peakbin<128 else peakbin-256;fftcode=rne((bn*65536+delta)*500000000,4587520);phasecode=phase['phase_q16'];consistent=abs(phasecode-fftcode)*4587520<=500000000*65536
 if spectrum and phase['phase_linear'] and consistent and abs(phasecode)<=851968000:mode=1;freq=phasecode;valid=True
 elif spectrum and abs(fftcode)<=851968000:mode=2;freq=fftcode;valid=True
 else:mode=0;freq=0;valid=False
 return dict(nonzero=True,exponent=ex,normalized=u,fft=V,power=power,peak_bin=peakbin,delta_q16=delta,peak=peak,secondary=secondary,energy=energy,fft_saturations=fft['saturations'],normal_saturations=0,coherent=coherent,unambiguous=unambiguous,spectrum=spectrum,phase=phase,fft_q16=fftcode,consistent=consistent,mode=mode,valid=valid,frequency_q16=freq)
def result_word(c):
 e=c['expected'];return pack([(c['frame'],32),(c['generation'],32),(0,4),(e['mode'],2),(e['valid'],1),(e['frequency_q16'],32),(e['phase']['phase_q16'],32),(e['fft_q16'],32),(e['spectrum'],1),(e['phase']['phase_linear'],1),(e['consistent'],1)])
def quality_word(e):return pack([(e['exponent'],6),(e['peak_bin'],8),(e['delta_q16'],32),(e['peak'],40),(e['secondary'],40),(e['energy'],48),(e['fft_saturations'],13),(e['normal_saturations'],8),(e['coherent'],1),(e['unambiguous'],1)])
def phase_word(e):
 q=e['phase'];return pack([(q['weighted_sum'],56),(q['max_centered'],64),(q['cordic_saturation'],12)])
def sha(x):return hashlib.sha256(x.read_bytes()).hexdigest().upper()
def division_cases():
 pairs=[(0,0),(0,2**63+1),(1,2),(-1,2),(3,2),(-3,2),(2**63-1,1),(-2**63,1),(2**63-1,2**32+1),(-2**63,2**63+1),(2**62+1,2**63),(2**62,2**63),(2**62-1,2**63),(-2**63,2**64-1)]
 return [dict(numerator=n,denominator=d,quotient=rne(n,d) if d else 0,error=int(d==0)) for n,d in pairs]
def build():
 pc=R/'sim/vectors/phase74_cases.json';data=json.loads(pc.read_text());cases=[];checks=0;sourcehashes=dict(data['source_hashes']);sourcehashes[pc.relative_to(R).as_posix()]=sha(pc)
 mf=R/'sim/vectors/fft256_published/manifest.json';mfdata=json.loads(mf.read_text());sourcehashes[mf.relative_to(R).as_posix()]=sha(mf)
 pub={}
 for row in mfdata['files']:
  fp=Path(row['path']);assert sha(fp)==row['sha256'];d=json.loads(fp.read_text());pub[f"{d['family']}_case_{d['case_id']:03d}"]=d;sourcehashes[fp.relative_to(R).as_posix()]=sha(fp)
 for c in data['cases']:
  z=c['z'];e=estimator(z)
  # Original phase arithmetic is compared unchanged, even for zero input.
  assert e['phase']==c['expected'];label=c['label']
  if c['published']:
   d=pub[label];ds=d['datasets'];ctx=d['context'];assert [e['exponent']]==ds['block_exponent']['values']
   assert e['normalized']==[[x['real'],x['imag']] for x in ds['fft_input_codes']['values']]
   assert e['fft']==[[x['real'],x['imag']] for x in ds['fft_codes']['values']];assert e['power']==ds['power']['values'];assert [e['peak_bin']]==ds['peak_bin_zero_based']['values'];assert [e['delta_q16']]==ds['delta_q16']['values']
   mode_names=['INVALID','MAIN_PHASE','DEGRADED_FFT','INVALID_ZERO'];assert mode_names[e['mode']]==ctx['bittrue.mode']['value'];assert e['valid']==ctx['bittrue.valid']['value']
   for ours,key in [('frequency_q16','frequency_q16'),('fft_q16','fft_q16'),('spectrum','spectrum_valid'),('consistent','phase_fft_consistent')]:assert e[ours]==ctx['bittrue.estimate.'+key]['value'],(label,ours,e[ours],ctx)
   checks+=925
  cases.append(dict(label=label,published=c['published'],z=z,expected=e))
 if not any(c['expected']['mode']==2 for c in cases):
  z=[[1<<34,0] for _ in range(74)];z[37]=[0,1<<34];cases.append(dict(label='single_phase_outlier_fallback',published=False,z=z,expected=estimator(z)))
 for k,c in enumerate(cases):c.update(index=k,frame=4000+k,generation=0x789a0000+k)
 O=R/'sim/vectors'
 def mem(name,rows,width):(O/name).write_text(''.join(f'{x:0{width}x}\n' for x in rows),encoding='ascii')
 mem('backend74_z.mem',[pack([(a,38),(b,38)]) for c in cases for a,b in c['z']],19)
 mem('backend74_normal.mem',[pack([(a,20),(b,20)]) for c in cases for a,b in (c['expected']['normalized'] or [[0,0]]*74)],10)
 mem('backend74_fft.mem',[pack([(a,20),(b,20),(pw,40)]) for c in cases for (a,b),pw in zip(c['expected']['fft'] or [[0,0]]*256,c['expected']['power'] or [0]*256)],20)
 mem('backend74_result.mem',[result_word(c) for c in cases],43)
 mem('backend74_quality.mem',[quality_word(c['expected']) for c in cases],50)
 mem('backend74_phase.mem',[phase_word(c['expected']) for c in cases],33)
 (O/'backend74_config.svh').write_text('localparam integer BACKEND_CASES = '+str(len(cases))+';\n',encoding='ascii')
 div=division_cases();mem('backend74_div_input.mem',[pack([(d['numerator'],64),(d['denominator'],64)]) for d in div],32);mem('backend74_div_output.mem',[pack([(d['quotient'],64),(d['error'],1)]) for d in div],17)
 (O/'backend74_div_config.svh').write_text('localparam integer DIV_CASES = '+str(len(div))+';\n',encoding='ascii')
 (O/'backend74_cases.json').write_text(json.dumps({'schema':'backend74_vectors_v1','source_hashes':sourcehashes,'division_cases':div,'cases':cases},separators=(',',':'))+'\n',encoding='utf-8')
 counts={i:sum(c['expected']['mode']==i for c in cases) for i in range(4)};assert all(counts.values()),counts
 report={'status':'BACKEND74_REFERENCE_PASS','cases':len(cases),'published':19,'modes_0invalid_1main_2fft_3zero':counts,'matched_published_scalar_fields':checks,'new_matlab_run':False,'new_native_run':False,'spectrum_cases':sum(c['expected']['spectrum'] for c in cases)}
 (R/'reports/BACKEND74_VECTOR_CHECK.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
if __name__=='__main__':build()