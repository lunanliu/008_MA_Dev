"""Integer FFT256 oracle for the frozen MATLAB round/scale/saturate rules."""
from pathlib import Path
import math,json,hashlib
R=Path(__file__).resolve().parents[1]
def rne(n,d):
 assert d>0
 q,r=divmod(abs(n),d);q+=2*r>d or (2*r==d and q%2==1)
 return -q if n<0 else q
def clip(n,b):return min((1<<(b-1))-1,max(-(1<<(b-1)),n))
def pack(values):
 y=0
 for v,b in values:y=(y<<b)|(int(v)&((1<<b)-1))
 return y
def twiddles():
 return [(clip(round(math.cos(-2*math.pi*j/256)*(1<<17)),18),clip(round(math.sin(-2*math.pi*j/256)*(1<<17)),18)) for j in range(128)]
def fft256(z):
 assert len(z)==256 and all(-(1<<19)<=a<(1<<19) for x in z for a in x)
 v=[None]*256
 for j,x in enumerate(z):v[int(f'{j:08b}'[::-1],2)]=tuple(x)
 tw=twiddles();audit=[];sat=0
 for stage in range(8):
  half=1<<stage
  for bf in range(128):
   j=bf%half;a=(bf//half)*(2*half)+j;b=a+half
   ar,ai=v[a];br,bi=v[b];wr,wi=tw[j<<(7-stage)]
   pr=rne(br*wr-bi*wi,1<<17);pi=rne(br*wi+bi*wr,1<<17)
   raw=[rne(ar+pr,2),rne(ai+pi,2),rne(ar-pr,2),rne(ai-pi,2)]
   val=[clip(x,20) for x in raw];n=sum(x!=y for x,y in zip(raw,val));sat+=n
   v[a]=tuple(val[:2]);v[b]=tuple(val[2:]);audit.append({'stage':stage,'butterfly':bf,'values':val,'saturations':n})
 return {'output':[list(x) for x in v],'butterflies':audit,'saturations':sat}
def normalize(z):
 mx=max(abs(x) for p in z for x in p)
 if not mx:return 0,[[0,0] for _ in z]
 ex=16-(mx-1).bit_length()
 return ex,[[clip(v*(1<<ex) if ex>=0 else rne(v,1<<(-ex)),20) for v in p] for p in z]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def build():
 O=R/'sim/vectors';out=[];sources={};checks=0
 mf=R/'sim/vectors/fft256_published/manifest.json';m=json.loads(mf.read_text());assert m['status']=='PASS';sources[str(mf.relative_to(R)).replace('\\','/')]=sha(mf)
 for f in m['files']:
  p=Path(f['path']);assert sha(p)==f['sha256'];sources[p.relative_to(R).as_posix()]=sha(p);d=json.loads(p.read_text());ds=d['datasets']
  for src in d['source_inputs'].values():
   p=Path(src['path']);assert sha(p)==src['sha256'];sources[p.relative_to(R).as_posix()]=sha(p)
  z=[[x['real'],x['imag']] for x in ds['z_codes']['values']];ex,u=normalize(z)
  assert [ex]==ds['block_exponent']['values'];assert u==[[x['real'],x['imag']] for x in ds['fft_input_codes']['values']]
  x=u+[[0,0]]*182;e=fft256(x);assert e['output']==[[x['real'],x['imag']] for x in ds['fft_codes']['values']]
  power=[a*a+b*b for a,b in e['output']];assert power==ds['power']['values'];peak=max(range(256),key=power.__getitem__);assert [peak]==ds['peak_bin_zero_based']['values']
  l,pw,rr=power[(peak-1)%256],power[peak],power[(peak+1)%256];den=l-2*pw+rr;delta=clip(0,32) if den>=0 else max(-32768,min(32768,rne((rr-l)*32768,-den)));assert [delta]==ds['delta_q16']['values']
  checks+=1+148+512+256+1+1
  out.append({'label':f"{d['family']}_case_{d['case_id']:03d}",'published':True,'input':x,'expected':e})
 hi=(1<<19)-1;lo=-(1<<19)
 corners=[('zero',[[0,0]]*256),('unit_impulse',[[1,-1]]+[[0,0]]*255),('last_minimum_impulse',[[0,0]]*255+[[lo,lo]]),('max_dc',[[hi,hi]]*256),('min_dc',[[lo,lo]]*256),('alternating_extrema',[[hi if i%2==0 else lo,lo if i%2==0 else hi] for i in range(256)]),('small_rounding',[[((i*17)%19)-9,((i*11)%13)-6] for i in range(256)])]
 corners.append(('fullscale_quadrant_pattern',[[hi,hi] if i<64 else [lo,hi] if i<128 else [lo,lo] if i<192 else [hi,lo] for i in range(256)]))
 for label,x in corners:out.append({'label':label,'published':False,'input':x,'expected':fft256(x)})
 for i,c in enumerate(out):c.update(index=i,frame=3000+i,generation=0x67890000+i)
 def mem(name,rows,width): (O/name).write_text(''.join(f'{x:0{width}x}\n' for x in rows),encoding='ascii')
 mem('fft256_input.mem',[pack([(a,20),(b,20)]) for c in out for a,b in c['input']],10)
 mem('fft256_output.mem',[pack([(a,20),(b,20)]) for c in out for a,b in c['expected']['output']],10)
 mem('fft256_butterfly.mem',[pack([(x,20) for x in a['values']]+[(a['saturations'],3)]) for c in out for a in c['expected']['butterflies']],21)
 mem('fft256_saturation.mem',[c['expected']['saturations'] for c in out],4)
 mem('fft256_twiddle.mem',[pack([(a,18),(b,18)]) for a,b in twiddles()],9)
 (R/'ip/fft256_twiddle.mem').write_text((O/'fft256_twiddle.mem').read_text(),encoding='ascii')
 (O/'fft256_config.svh').write_text('localparam integer FFT_CASES = '+str(len(out))+';\n',encoding='ascii')
 (O/'fft256_cases.json').write_text(json.dumps({'schema':'fft256_cases_v1','published_cases':19,'integer_corner_cases':8,'source_hashes':sources,'cases':out},separators=(',',':'))+'\n',encoding='utf-8')
 summary={'status':'FFT256_ORACLE_MATCHES_PUBLISHED_MATLAB','published_cases':19,'published_scalar_nodes_checked':checks,'total_cases':len(out),'saturating_cases':{c['label']:c['expected']['saturations'] for c in out if c['expected']['saturations']},'native_rtl_tested':False,'twiddle_positive_one_code':twiddles()[0][0],'no_matlab_run':True}
 (R/'reports/FFT256_VECTOR_CHECK.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8');print(json.dumps(summary))
if __name__=='__main__':build()