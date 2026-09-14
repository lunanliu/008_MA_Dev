"""Source, oracle and per-node result verification for BACKEND006. Read-only."""
from pathlib import Path
import argparse,csv,json,hashlib,runpy
R=Path(__file__).resolve().parents[1]
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--actual',type=Path);ap.add_argument('--sources',type=Path);ap.add_argument('--identity',type=Path);a=ap.parse_args()
 lock=load(R/'docs/BACKEND006_SOURCE_LOCK.json')
 for x in lock['files']:assert sha(R/x['path'])==x['sha256'],x['path']
 data=load(R/'sim/vectors/backend74_cases.json');cases=data['cases'];assert len(cases)==28
 for p,h in data['source_hashes'].items():assert sha(R/p)==h,p
 ref=runpy.run_path(str(R/'tools/backend74_reference.py'));pack=ref['pack']
 for c in cases:assert ref['estimator'](c['z'])==c['expected'],c['label']
 assert ref['division_cases']()==data['division_cases']
 def mem(name):return [int(x,16) for x in (R/'sim/vectors'/name).read_text().split()]
 assert mem('backend74_z.mem')==[pack([(a,38),(b,38)]) for c in cases for a,b in c['z']]
 assert mem('backend74_normal.mem')==[pack([(a,20),(b,20)]) for c in cases for a,b in (c['expected']['normalized'] or [[0,0]]*74)]
 assert mem('backend74_fft.mem')==[pack([(a,20),(b,20),(pw,40)]) for c in cases for (a,b),pw in zip(c['expected']['fft'] or [[0,0]]*256,c['expected']['power'] or [0]*256)]
 assert mem('backend74_result.mem')==[ref['result_word'](c) for c in cases]
 assert mem('backend74_quality.mem')==[ref['quality_word'](c['expected']) for c in cases]
 assert mem('backend74_phase.mem')==[ref['phase_word'](c['expected']) for c in cases]
 assert mem('backend74_div_input.mem')==[pack([(d['numerator'],64),(d['denominator'],64)]) for d in data['division_cases']]
 assert mem('backend74_div_output.mem')==[pack([(d['quotient'],64),(d['error'],1)]) for d in data['division_cases']]
 result={'status':'BACKEND74_SOURCE_AND_ORACLE_PASS','frozen_files':len(lock['files']),'published_source_identities':len(data['source_hashes']),'cases':len(cases),'published_cases':19,'native_checked':False}
 if a.sources:
  actual={(x['fileset'],str(Path(x['path']).resolve()).casefold()) for x in csv.DictReader(a.sources.open(encoding='utf-8-sig',newline=''))}
  wanted={(x['fileset'],str((R/x['path']).resolve()).casefold()) for x in lock['project_members']};assert actual==wanted,dict(extra=sorted(actual-wanted),missing=sorted(wanted-actual));result['actual_project_members']=len(actual)
 if a.identity:
  props=dict(x.split('=',1) for x in a.identity.read_text(encoding='utf-8-sig').splitlines())
  for k,v in {'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_estimate74_backend','simulation_top':'cfo_estimate74_backend_tb','vivado':'2021.1','xelab_jobs':'16'}.items():assert props[k]==v,(k,props[k])
  result['project_identity']='PASS'
 if a.actual:
  runs={};counts={k:0 for k in ['N','P','F','D','E','V']};max_tail=max_total=stalls=0;modes={k:0 for k in range(4)}
  for line in a.actual.read_text(encoding='utf-8-sig').splitlines():
   it=line.split();tag=it[0];assert tag in counts,line
   if tag=='V':
    assert not runs and len(it)==3 and int(it[1])==counts['V'];d=data['division_cases'][counts['V']];assert int(it[2],16)==pack([(d['quotient'],64),(d['error'],1)]);counts['V']+=1;continue
   rid=int(it[1]);k=int(it[2]);assert 0<=k<len(cases);c=cases[k];e=c['expected'];r=runs.setdefault(rid,{'case':k,'N':0,'P':0,'ended':False});assert r['case']==k and not r['ended'],line
   if tag in ['N','P']:
    j=r[tag];assert len(it)==5 and int(it[3])==j,line
    if tag=='N':
     assert j<len(e['normalized']);wanted=pack([(v,20) for v in e['normalized'][j]])
    else:
     assert j<len(e['fft']);wanted=pack([(v,20) for v in e['fft'][j]]+[(e['power'][j],40)])
    assert int(it[4],16)==wanted,line;r[tag]+=1
   elif tag=='F':
    assert len(it)==7 and r['N']==len(e['normalized']) and r['P']==len(e['fft']),line
    wanted=pack([(ref['result_word'](c),170),(ref['quality_word'](e),197),(ref['phase_word'](e),132)]);assert int(it[3],16)==wanted,line
    tail,total,stall=map(int,it[4:]);assert 0<tail<=7600 and 0<total<=12000,line;assert stall==(k%7 if rid<28 else 7),line
    max_tail=max(max_tail,tail);max_total=max(max_total,total);stalls+=stall;modes[e['mode']]+=1;r.update(ended=True,kind=tag)
   elif tag=='D':
    assert len(it)==7 and [r['N'],r['P']]==list(map(int,it[5:])),line;r.update(ended=True,kind=tag,abort=int(it[3]),where=int(it[4]));assert r['abort'] in [0,1]
   else:
    assert len(it)==5 and k==0 and r['N']==0 and r['P']==0,line;err=int(it[3]);assert err in [1,2,3]
    w=pack([(4000,32),(0x789a0000,32),(err,4),(0,2),(0,1),(0,99)]);wanted=pack([(w,170),(0,197),(0,132)]);assert int(it[4],16)==wanted,line;r.update(ended=True,kind=tag,error=err)
   counts[tag]+=1
  assert counts['V']==14 and sorted(runs)==list(range(53)) and all(r['ended'] for r in runs.values())
  for i in range(28):assert runs[i]['kind']=='F' and runs[i]['case']==i
  for i in range(10):
   d=runs[28+2*i];g=runs[29+2*i];assert d['kind']=='D' and d['case']==2*i and d['abort']==i%2 and d['where']==i//2;assert g['kind']=='F' and g['case']==2*i+1
   if d['where']==0:assert d['N']==0 and d['P']==0
   elif d['where']==1:assert 25<=d['N']<=26 and d['P']==0
   elif d['where']==2:assert d['N']==74 and 13<=d['P']<=14
   else:assert d['N']==74 and d['P']==256
  assert [runs[i]['error'] for i in range(48,53)]==[1,2,2,3,1]
  assert counts['F']==38 and counts['D']==10 and counts['E']==5 and stalls==154 and all(modes.values())
  result.update(status='BACKEND74_NUMERIC_PASS_LIMITED_SCOPE',native_checked=True,rows=counts,full_transactions=38,discarded_transactions=10,protocol_errors=5,divider_cases=14,max_tail_cycles=max_tail,max_total_cycles=max_total,output_stall_cycles=stalls,full_output_modes=modes,normalization_quality_phase_fft_merge_checked=True,fft2048_frontend_tested=False,full_frame_tested=False,synthesis_timing_throughput_qualified=False,formal_T11_T12_T13_PASS=False)
 print(json.dumps(result))
if __name__=='__main__':main()