"""Integer pilot-front reference; use published coefficients without requantization."""
from pathlib import Path
import json,runpy,hashlib,struct
R=Path(__file__).resolve().parents[1]
F=runpy.run_path(str(R/'tools/fft2048_reference.py'));fft=F['fft2048'];pack=F['pack'];rne=F['rne'];clip=F['clip']
PUB=R/'work/CFO_FRONTDATA007/attempt_20260914T173145405Z_luna_v3/published'
KS=list(range(2,821,2))+list(range(-820,0,2))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def coeffs():return json.loads((PUB/'cases/rcfo004_case_001.json').read_text())['datasets']['pilot_coeff_codes']['values']
def front(x,co):
 e=fft(x,False);h=[];words=[]
 for k,(cr,ci) in zip(KS,co):
  a,b=e['output'][k%2048];hr=clip(rne(a*cr-b*ci,1<<17),28);hi=clip(rne(a*ci+b*cr,1<<17),28)
  h.append([hr,hi]);words.append(pack([(a,26),(b,26),(cr,18),(ci,18),(hr,28),(hi,28)]))
 z=[sum(v[i] for v in h) for i in range(2)];assert all(abs(v)<1<<37 for v in z)
 return {'pilot_words':words,'H':h,'z':z,'fft_saturations':e['saturations']}
def result_word(c):return pack([(c['frame'],32),(c['generation'],32),(c['window'],7)]+[(v,38) for v in c['expected']['z']]+[(820,10),(c['expected']['fft_saturations'],16),(0,4)])
def build():
 O=R/'sim/vectors';cs=[];sources={};co=coeffs();pairs=sorted(set(tuple(x) for w in co for x in w));assert len(pairs)==8 and len(co)==74
 for p in [R/'reports/FFT008_REVIEW_20260914/INDEPENDENT_REVIEW.json',R/'tools/fft2048_reference.py',R/'sim/vectors/fft2048_cases.json',R/'ip/cfo_rot_lut.mem']:
  sources[p.relative_to(R).as_posix()]=sha(p)
 def s16(x):return x-65536 if x&32768 else x
 rom=[(s16(int(w,16)&65535),s16(int(w,16)>>16)) for w in (R/'ip/cfo_rot_lut.mem').read_text().split()]
 matches=0;windows=[]
 for fi,cid in enumerate([1,3,81]):
  p=PUB/f'cases/rcfo004_case_{cid:03d}.json';d=json.loads(p.read_text());sources[p.relative_to(R).as_posix()]=sha(p);assert d['datasets']['pilot_coeff_codes']['values']==co
  bp=Path(d['raw_windows']['output']['path']);sources[bp.relative_to(R).as_posix()]=sha(bp);raw=list(struct.iter_unpack('<hh',bp.read_bytes()));params=d['source_result_json']['bittrue']['coarse_parameters']
  chosen=list(range(74)) if cid==1 else [0,1,36,73]
  for m in chosen:
   x=F['rotate_window'](raw[m*2048:(m+1)*2048],params,m,rom);e=front(x,co[m]);ds=d['datasets']
   assert e['H']==ds['pilot_product_codes']['values'][m] and e['z']==ds['front_z_codes']['values'][0][m]
   for j,w in enumerate(e['pilot_words']):assert (w>>92)==pack([(v,26) for v in ds['pilot_fft_codes']['values'][m][j]])
   cs.append({'label':f'rcfo004_case_{cid:03d}_window_{m:02d}','published':True,'frame':6000+fi,'generation':0x9abc0000+fi,'window':m,'input':x,'expected':e});matches+=820
  windows.append({'case_id':cid,'windows':chosen})
 previous=json.loads((R/'sim/vectors/fft2048_cases.json').read_text())
 for j,c in enumerate(previous['cases'][12:]):
  assert not c['published'];x=c['input'];m=c['window'];cs.append({'label':c['label'],'published':False,'frame':7000+j,'generation':0xabcd0000+j,'window':m,'input':x,'expected':front(x,co[m])})
 for j,c in enumerate(cs):c['index']=j
 assert len(cs)==90
 def mem(path,rows,width):path.write_text(''.join(f'{x:0{width}x}\n' for x in rows),encoding='ascii')
 indexes=[pairs.index(tuple(x)) for w in co for x in w]
 mem(R/'ip/front2048_coefficient_index.mem',indexes,1);mem(R/'ip/front2048_coefficient_table.mem',[pack([(a,18),(b,18)]) for a,b in pairs],9)
 mem(O/'front2048_input.mem',[pack([(a,26),(b,26)]) for c in cs for a,b in c['input']],13)
 mem(O/'front2048_pilot.mem',[w for c in cs for w in c['expected']['pilot_words']],36)
 mem(O/'front2048_result.mem',[result_word(c) for c in cs],45)
 mem(O/'front2048_metadata.mem',[pack([(c['frame'],32),(c['generation'],32),(c['window'],7)]) for c in cs],18)
 (O/'front2048_config.svh').write_text(f'localparam integer FRONT_CASES = {len(cs)};\n',encoding='ascii')
 (O/'front2048_cases.json').write_text(json.dumps({'schema':'front2048_cases_v1','source_hashes':sources,'coefficient_pairs':pairs,'cases':cs},separators=(',',':'))+'\n',encoding='utf-8')
 out={'status':'FRONT2048_ORACLE_MATCHES_PUBLISHED_NODES','published_windows':82,'published_complex_FFT_nodes':matches,'published_complex_H_nodes':matches,'published_complex_z_nodes':82,'windows':windows,'unique_native_cases':90,'integer_corners':8,'coefficient_pairs':pairs,'coefficient_index_entries':len(indexes),'coefficient_index_bits':len(indexes)*3,'full_precision_table_bits':8*36,'coefficient_reconstruction_exact':all(list(pairs[indexes[i*820+j]])==co[i][j] for i in range(74) for j in range(820)),'native_rtl_run':False,'whole_frame_waveform_or_cdc_tested':False}
 (R/'reports/FRONT2048_VECTOR_CHECK.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in out.items() if k!='windows'}))
if __name__=='__main__':build()