"""Read-only FFT005 source, oracle and native trace verification."""
from pathlib import Path
import argparse,csv,json,hashlib,runpy
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--actual',type=Path);ap.add_argument('--sources',type=Path);ap.add_argument('--identity',type=Path);a=ap.parse_args()
 lock=load(R/'docs/FFT005_SOURCE_LOCK.json')
 for x in lock['files']:assert sha(R/x['path'])==x['sha256'],x['path']
 data=load(R/'sim/vectors/fft256_cases.json');cases=data['cases'];assert len(cases)==27
 for p,h in data['source_hashes'].items():assert sha(R/p)==h,p
 ref=runpy.run_path(str(R/'tools/fft256_reference.py'));pack=ref['pack']
 for c in cases:assert ref['fft256'](c['input'])==c['expected'],c['label']
 result={'status':'FFT256_SOURCE_AND_ORACLE_PASS','frozen_files':len(lock['files']),'published_source_identities':len(data['source_hashes']),'unique_vectors':27,'published_cases':19,'native_checked':False}
 if a.sources:
  actual={(x['fileset'],str(Path(x['path']).resolve()).casefold()) for x in csv.DictReader(a.sources.open(encoding='utf-8-sig',newline=''))}
  expected={(x['fileset'],str((R/x['path']).resolve()).casefold()) for x in lock['project_members']}
  assert actual==expected,dict(extra=sorted(actual-expected),missing=sorted(expected-actual));result['actual_project_members']=len(actual)
 if a.identity:
  props=dict(x.split('=',1) for x in a.identity.read_text(encoding='utf-8-sig').splitlines())
  for k,v in {'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_fft256_core','simulation_top':'cfo_fft256_tb','vivado':'2021.1','xelab_jobs':'16'}.items():assert props[k]==v,(k,props[k])
  result['project_identity']='PASS'
 if a.actual:
  runs={};counts={k:0 for k in ['B','O','F','D','E']};maxt=maxtotal=stalls=0
  for line in a.actual.read_text(encoding='utf-8-sig').splitlines():
   it=line.split();tag=it[0];rid=int(it[1]);k=int(it[2]);assert tag in counts and 0<=k<27,line
   c=cases[k];e=c['expected'];r=runs.setdefault(rid,{'case':k,'B':0,'O':0,'ended':False});assert r['case']==k and not r['ended'],line
   if tag=='B':
    j=r['B'];assert len(it)==5 and int(it[3])==j and j<1024,line;node=e['butterflies'][j]
    wanted=pack([(v,20) for v in node['values']]+[(node['saturations'],3)]);assert int(it[4],16)==wanted,line;r['B']+=1
   elif tag=='O':
    j=r['O'];assert len(it)==5 and int(it[3])==j and j<256 and r['B']==1024,line
    wanted=pack([(c['frame'],32),(c['generation'],32),(j,8),(j==255,1)]+[(v,20) for v in e['output'][j]]+[(e['saturations'],13),(0,4)])
    assert int(it[4],16)==wanted,line;r['O']+=1
   elif tag=='F':
    assert len(it)==6 and r['B']==1024 and r['O']==256,line
    tail,total,stall=map(int,it[3:]);assert 0<tail<=5200 and 0<total<=8000,line
    assert stall==4*(k%4)+(0 if rid<27 else 7),line
    maxt=max(maxt,tail);maxtotal=max(maxtotal,total);stalls+=stall;r.update(ended=True,kind=tag)
   elif tag=='D':
    assert len(it)==6 and [r['B'],r['O']]==list(map(int,it[4:])),line
    r.update(ended=True,kind=tag,abort=int(it[3]));assert r['abort'] in [0,1]
   else:
    assert len(it)==5 and k==0 and r['B']==0 and r['O']==0,line;error=int(it[3]);assert error in [1,2]
    wanted=pack([(3000,32),(0x67890000,32),(0,8),(1,1),(0,40),(0,13),(error,4)])
    assert int(it[4],16)==wanted,line;r.update(ended=True,kind=tag,error=error)
   counts[tag]+=1
  assert sorted(runs)==list(range(44)) and all(r['ended'] for r in runs.values())
  for i in range(27):assert runs[i]['case']==i and runs[i]['kind']=='F'
  for i in range(6):
   d=runs[27+2*i];g=runs[28+2*i];assert d['case']==2*i and d['kind']=='D' and d['abort']==i%2 and g['case']==2*i+1 and g['kind']=='F'
   if i<2:assert d['B']==0 and d['O']==0
   elif i<4:assert 401<=d['B']<=402 and d['O']==0
   else:assert d['B']==1024 and d['O']==13
  assert [runs[i]['error'] for i in range(39,44)]==[1,2,2,1,2]
  assert counts['F']==33 and counts['D']==6 and counts['E']==5 and stalls==246
  result.update(status='FFT256_NUMERIC_PASS_LIMITED_SCOPE',native_checked=True,rows=counts,max_tail_cycles=maxt,max_total_cycles=maxtotal,output_stall_cycles=stalls,full_transactions=33,discarded_transactions=6,protocol_errors=5,saturation_extreme_count=cases[26]['expected']['saturations'],quality_gate_tested=False,final_mode_tested=False,formal_T11_T12_T13_PASS=False)
 print(json.dumps(result))
if __name__=='__main__':main()