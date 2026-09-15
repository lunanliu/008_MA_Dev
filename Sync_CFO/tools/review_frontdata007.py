"""Independent FRONTDATA007 review; hashes and integer identities, no native tools."""
from pathlib import Path
import json,hashlib,csv,datetime,shutil
R=Path('D:/008_MA_Dev/T11_CFO')
A=R/'work/CFO_FRONTDATA007/attempt_20260914T173145405Z_luna_v3'
O=R/'reports/FRONTDATA007_REVIEW_20260914'
def load(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def check(d):
 p=Path(d['path']);assert p.stat().st_size==d['bytes'] and sha(p)==d['sha256'],p
 return {'path':str(p),'bytes':d['bytes'],'sha256':d['sha256']}
def rne(n,d):
 q,r=divmod(n,d);return q+int(2*r>d or (2*r==d and q%2))
def clip(n,b):return min((1<<(b-1))-1,max(-(1<<(b-1)),n))
def main():
 O.mkdir(exist_ok=True)
 c=load(A/'DATA_PREP_COMPLETION.json');assert c['status']=='COMPLETE';check(c['final_manifest']);m=load(A/'published/FINAL_MANIFEST.json');assert m['status']=='COMPLETE'
 lock=load(R/'docs/FRONTDATA007_SOURCE_LOCK.json');assert sha(R/'docs/FRONTDATA007_SOURCE_LOCK.json')=='D487D3C19FB54BCD969178D82C546648F316F321195A5883C1EDA1812343AA53'
 for x in lock['files']:check(dict(x,path=str(R/x['path'])))
 check(m['decoder']['hdf5_library']);assert sha(Path(m['decoder']['tool_path']))==m['decoder']['tool_sha256']
 files=[check(x) for x in m['published_data_files']];assert len(files)==22
 coeffs=None;cases=[]
 for x in files:
  p=Path(x['path'])
  if p.suffix!='.json':continue
  d=load(p);ds=d['datasets'];assert d['status']=='PASS' and len(ds)==5
  for src in d['source_inputs'].values():check(src)
  assert load(Path(d['source_inputs']['result_json']['path']))==d['source_result_json']
  f,co,h=[ds[k]['values'] for k in ['pilot_fft_codes','pilot_coeff_codes','pilot_product_codes']]
  assert all(len(v)==74 and all(len(w)==820 for w in v) for v in [f,co,h])
  for v,b in [(f,26),(co,18),(h,28)]:assert all(type(a)==int and -(1<<(b-1))<=a<(1<<(b-1)) for w in v for z in w for a in z)
  if coeffs is None:coeffs=co
  else:assert coeffs==co
  for fw,cw,hw in zip(f,co,h):
   for (a,b),(c0,s),hv in zip(fw,cw,hw):assert [clip(rne(a*c0-b*s,1<<17),28),clip(rne(a*s+b*c0,1<<17),28)]==hv
  z=[[sum(v[i] for v in w) for i in range(2)] for w in h]
  assert all(abs(a)<(1<<37) for q in z for a in q)
  assert z==ds['front_z_codes']['values'][0]==ds['estimator_z_codes']['values'][0]
  phase=load(Path(d['source_inputs']['verified_phase_case']['path']));assert z==[[v['real'],v['imag']] for v in phase['mat_datasets']['z_codes']['values']]
  raw=d.get('raw_windows');nraw=0
  if raw:
   check(raw['source']);check(raw['output']);original=Path(raw['source']['path']).read_bytes();copied=Path(raw['output']['path']).read_bytes()
   assert len(copied)==606208
   for j,seg in enumerate(raw['segments']):
    start=(25984+17920*j)*4;part=original[start:start+8192]
    assert part==copied[j*8192:(j+1)*8192] and hashlib.sha256(part).hexdigest().upper()==seg['sha256'];nraw+=1
  cases.append({'family':d['family'],'case_id':d['case_id'],'H_exact_complex_points':60680,'z_exact_windows':74,'raw_windows_hashchecked':nraw})
 assert len(cases)==19
 pairs=sorted(set(tuple(v) for w in coeffs for v in w));assert len(pairs)==8
 csvrows=list(csv.DictReader((R/'matlab/waveform/payload_pilot_cells.csv').open(newline='',encoding='utf-8-sig')));assert len(csvrows)==60680
 ks=list(range(2,821,2))+list(range(-820,0,2))
 for j in range(74):assert [int(x['signedSubcarrierK']) for x in csvrows[j*820:(j+1)*820]]==ks
 r=c['resource']
 out={'status':'PASS_DATA_EXTRACTION_AND_INTEGER_IDENTITIES_ONLY','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'completion_sha256':sha(A/'DATA_PREP_COMPLETION.json'),'manifest_sha256':sha(A/'published/FINAL_MANIFEST.json'),'source_files_verified':len(lock['files']),'published_files_verified':len(files),'cases':cases,'H_exact_complex_points':19*60680,'z_exact_windows':19*74,'raw_windows':222,'coefficient_pairs':pairs,'all_19_coefficient_matrices_exact':True,'resource':{'elapsed_seconds':r['elapsed_seconds'],'peak_working_set_bytes':r['max_process_peak_working_set_bytes'],'private_usage_peak':'NOT_RECORDED','minimum_available_physical_bytes':min(s['system']['available_physical_bytes'] for s in r['samples'])},'decoder_review':{'repairs':'v1 nonexistent H5Dget_layout replaced with H5Pget_layout; v2 chunk-size query crash avoided; v3 H5Dread_chunk with zlib deflate, exact shape, mask, decoded length and edge clipping checks','limitation':'Reader frozen for these compressed datasets only. Allocation equals uncompressed chunk size; this is not a general arbitrary-chunk safety proof and the reader is not approved for new data. No new extraction was run during this review.'},'boundaries':['raw windows require global-index coarse rotation before FFT','No new MATLAB or Vivado run','No FFT2048 RTL acceptance','No resource synthesis or full-frame throughput qualification']}
 (O/'INDEPENDENT_REVIEW.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
 for p in [A/'DATA_PREP_COMPLETION.json',A/'published/FINAL_MANIFEST.json',A/'EXECUTION_FREEZE.json',Path(m['decoder']['tool_path'])]:shutil.copy2(p,O/p.name)
 print(json.dumps({k:v for k,v in out.items() if k not in ['cases','decoder_review']}))
if __name__=='__main__':main()