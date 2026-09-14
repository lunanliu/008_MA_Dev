"""FFT2048 integer oracle and deterministic banking audit; no MATLAB/Vivado."""
from pathlib import Path
import json,math,hashlib,struct
R=Path(__file__).resolve().parents[1]
PUB=R/'work/CFO_FRONTDATA007/attempt_20260914T173145405Z_luna_v3/published'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def rne(n,d):
 q,r=divmod(abs(n),d);q+=int(2*r>d or (2*r==d and q%2));return -q if n<0 else q
def clip(n,b):return min((1<<(b-1))-1,max(-(1<<(b-1)),n))
def pack(v):
 n=0
 for x,b in v:n=(n<<b)|(int(x)&((1<<b)-1))
 return n
def twiddles():return [(clip(round(math.cos(-2*math.pi*j/2048)*(1<<17)),18),clip(round(math.sin(-2*math.pi*j/2048)*(1<<17)),18)) for j in range(1024)]
TW=twiddles()
REV=[int(f'{j:011b}'[::-1],2) for j in range(2048)]
def fft2048(x,audit=True):
 assert len(x)==2048 and all(-(1<<25)<=a<(1<<25) for z in x for a in z)
 v=[None]*2048
 for j,z in enumerate(x):v[REV[j]]=tuple(z)
 nodes=[];sat=0
 for stage in range(11):
  half=1<<stage
  for bf in range(1024):
   j=bf%half;a=(bf//half)*(2*half)+j;b=a+half
   ar,ai=v[a];br,bi=v[b];wr,wi=TW[j<<(10-stage)]
   pr=rne(br*wr-bi*wi,1<<17);pi=rne(br*wi+bi*wr,1<<17)
   raw=[rne(ar+pr,2),rne(ai+pi,2),rne(ar-pr,2),rne(ai-pi,2)]
   val=[clip(z,26) for z in raw];n=sum(i!=j for i,j in zip(raw,val));sat+=n
   v[a]=tuple(val[:2]);v[b]=tuple(val[2:])
   if audit:nodes.append(pack([(z,26) for z in val]+[(n,3)]))
 return {'output':[list(z) for z in v],'butterfly_words':nodes,'saturations':sat}
def rotate_window(raw,params,m,rom):
 assert params['width']==32
 out=[]
 for j,(a,b) in enumerate(raw):
  n=25984+m*17920+j;phase=(int(params['phase0'])+n*int(params['step']))%(1<<32)
  idx=rne(phase,1<<22)%1024;c,s=rom[idx]
  out.append([64*clip(rne(a*c-b*s,1<<14),16),64*clip(rne(a*s+b*c,1<<14),16)])
 return out
def address_audit():
 rows=[];half=1;stride=1024
 for stage in range(11):
  off=base=tw=0;seen=set()
  for bf in range(1024):
   a=base|off;b=a|half;ea=((bf>>stage)<<(stage+1))|(bf&((1<<stage)-1));eb=ea^(1<<stage);et=(bf&((1<<stage)-1))<<(10-stage)
   assert (a,b,tw)==(ea,eb,et) and a not in seen and b not in seen
   assert a.bit_count()%2 != b.bit_count()%2
   seen.update([a,b])
   if off==half-1:off=0;base+=half*2;tw=0
   else:off+=1;tw+=stride
  assert len(seen)==2048
  rows.append({'stage':stage,'butterflies':1024,'unique_addresses':2048,'bank_conflicts':0,'issue_to_commit_cycles':7,'stage_cycles':1031})
  half*=2;stride//=2
 # Every stage covers disjoint pairs, so concurrent prior commit and current read cannot alias.
 return {'stages':rows,'run_cycles':11341,'input_cycles':2048,'output_first_latency':3,'output_samples':2048,'ideal_service_cycles_with_output_handshake':15440,'qualification':'Static schedule budget only; RTL cycles and 500 MHz timing not yet measured'}
def build():
 O=R/'sim/vectors';cases=[];sources={};checks=0
 sources[(R/'reports/FRONTDATA007_REVIEW_20260914/INDEPENDENT_REVIEW.json').relative_to(R).as_posix()]=sha(R/'reports/FRONTDATA007_REVIEW_20260914/INDEPENDENT_REVIEW.json')
 rp=R/'ip/cfo_rot_lut.mem';sources[rp.relative_to(R).as_posix()]=sha(rp)
 def s16(x):return x-65536 if x&32768 else x
 rom=[(s16(int(w,16)&65535),s16(int(w,16)>>16)) for w in rp.read_text().split()];assert len(rom)==1024
 ks=list(range(2,821,2))+list(range(-820,0,2));anch=[]
 for cid in [1,3,81]:
  p=PUB/f'cases/rcfo004_case_{cid:03d}.json';d=json.loads(p.read_text());sources[p.relative_to(R).as_posix()]=sha(p)
  bp=Path(d['raw_windows']['output']['path']);sources[bp.relative_to(R).as_posix()]=sha(bp);raw=list(struct.iter_unpack('<hh',bp.read_bytes()));assert len(raw)==74*2048
  ds=d['datasets'];params=d['source_result_json']['bittrue']['coarse_parameters']
  for m in range(74):
   x=rotate_window(raw[m*2048:(m+1)*2048],params,m,rom);picked=m in [0,1,36,73];e=fft2048(x,picked)
   actual=[e['output'][k%2048] for k in ks];expected=ds['pilot_fft_codes']['values'][m];assert actual==expected,(cid,m,next((i for i,(a,b) in enumerate(zip(actual,expected)) if a!=b),None))
   checks+=820
   if picked:cases.append({'label':f'rcfo004_case_{cid:03d}_window_{m:02d}','published':True,'window':m,'input':x,'expected':e})
  anch.append({'case_id':cid,'windows':74,'pilot_complex_exact':60680})
 hi=(1<<25)-1;lo=-(1<<25)
 corners=[('zero',[[0,0]]*2048),('unit_impulse',[[1,-1]]+[[0,0]]*2047),('last_minimum_impulse',[[0,0]]*2047+[[lo,lo]]),('max_dc',[[hi,hi]]*2048),('min_dc',[[lo,lo]]*2048),('alternating_extrema',[[hi,lo] if i%2==0 else [lo,hi] for i in range(2048)]),('small_rounding',[[i*17%19-9,i*11%13-6] for i in range(2048)]),('fullscale_quadrants',[[hi,hi] if i<512 else [lo,hi] if i<1024 else [lo,lo] if i<1536 else [hi,lo] for i in range(2048)])]
 for label,x in corners:cases.append({'label':label,'published':False,'window':len(cases),'input':x,'expected':fft2048(x)})
 for j,c in enumerate(cases):c.update(index=j,frame=5000+j,generation=0x89ab0000+j)
 def mem(name,rows,width):(O/name).write_text(''.join(f'{n:0{width}x}\n' for n in rows),encoding='ascii')
 mem('fft2048_input.mem',[pack([(a,26),(b,26)]) for c in cases for a,b in c['input']],13)
 mem('fft2048_output.mem',[pack([(a,26),(b,26)]) for c in cases for a,b in c['expected']['output']],13)
 mem('fft2048_butterfly.mem',[w for c in cases for w in c['expected']['butterfly_words']],27)
 mem('fft2048_saturation.mem',[c['expected']['saturations'] for c in cases],4)
 mem('fft2048_window.mem',[c['window'] for c in cases],2)
 (R/'ip/fft2048_twiddle.mem').write_text(''.join(f'{pack([(a,18),(b,18)]):09x}\n' for a,b in TW),encoding='ascii')
 (O/'fft2048_config.svh').write_text(f'localparam integer FFT_CASES = {len(cases)};\n',encoding='ascii')
 (O/'fft2048_cases.json').write_text(json.dumps({'schema':'fft2048_vectors_v1','source_hashes':sources,'cases':cases},separators=(',',':'))+'\n',encoding='utf-8')
 summary={'status':'FFT2048_INTEGER_ORACLE_MATCHES_PUBLISHED_PILOT_NODES','source_cases':anch,'source_windows':222,'published_complex_fft_nodes_exact':checks,'native_unique_windows':len(cases),'native_published_windows':12,'integer_corners':8,'saturations':{c['label']:c['expected']['saturations'] for c in cases if c['expected']['saturations']},'address_schedule':address_audit(),'no_matlab_or_vivado_run':True,'full_fft_is_integer_oracle_not_published_matlab_full_fft':True}
 (R/'reports/FFT2048_VECTOR_CHECK.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8');print(json.dumps(summary))
if __name__=='__main__':build()