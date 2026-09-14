"""Read-only source, fileset and per-node validation for CFO-PHASE004."""
from pathlib import Path
import argparse,csv,hashlib,json,runpy
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--actual',type=Path);ap.add_argument('--sources',type=Path);ap.add_argument('--identity',type=Path);a=ap.parse_args()
 lock=load(R/'docs/PHASE004_SOURCE_LOCK.json')
 for f in lock['files']:assert sha(R/f['path'])==f['sha256'],f['path']
 data=load(R/'sim/vectors/phase74_cases.json');cases=data['cases'];assert len(cases)==27
 for p,h in data['source_hashes'].items():assert sha(R/p)==h,p
 ref=runpy.run_path(str(R/'tools/phase74_reference.py'));pack=ref['pack']
 for c in cases:assert ref['phase74']([tuple(x) for x in c['z']])==c['expected'],c['label']
 result=dict(status='PHASE74_SOURCE_IDENTITIES_PASS',frozen_files=len(lock['files']),published_source_identities=len(data['source_hashes']),unique_vectors=27,published_cases=19,native_result_checked=False)
 if a.sources:
  actual={(x['fileset'],str(Path(x['path']).resolve()).casefold()) for x in csv.DictReader(a.sources.open(encoding='utf-8-sig',newline=''))}
  wanted={(x['fileset'],str((R/x['path']).resolve()).casefold()) for x in lock['project_members']}
  assert actual==wanted,dict(extra=sorted(actual-wanted),missing=sorted(wanted-actual));result['actual_project_members']=len(actual)
 if a.identity:
  props=dict(line.split('=',1) for line in a.identity.read_text(encoding='utf-8-sig').splitlines())
  for k,v in {'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_phase74_core','simulation_top':'cfo_phase74_tb','vivado':'2021.1','xelab_jobs':'16'}.items():assert props[k]==v,(k,props[k])
  result['project_identity']='PASS'
 if a.actual:
  runs={};counts={'P':0,'R':0,'C':0,'F':0,'D':0,'E':0};max_tail=max_total=stalls=0
  for line in a.actual.read_text(encoding='utf-8-sig').splitlines():
   items=line.split();tag=items[0];rid=int(items[1]);case=int(items[2]);assert tag in counts and 0<=case<len(cases)
   run=runs.setdefault(rid,dict(case=case,P=0,R=0,C=0,ended=False));assert run['case']==case and not run['ended'],line
   c=cases[case];e=c['expected']
   if tag in ('P','R','C'):
    assert len(items)==5 and int(items[3])==run[tag] and run[tag]<74,line
    j=run[tag]
    if tag=='P':wanted=pack([(e['angle_turn_q31'][j],32),(e['unwrapped_turn_q31'][j],40)])
    elif tag=='R':wanted=pack([(e['predicted_turn_q31'][j],40),(e['residual_turn_q31'][j],56)])
    else:wanted=pack([(e['centered_residual_times74'][j],64)])
    assert int(items[4],16)==wanted,line;run[tag]+=1
   elif tag=='F':
    assert len(items)==7 and all(run[k]==74 for k in ('P','R','C')),line
    wanted=pack([(c['frame'],32),(c['generation'],32),(e['nonzero'],1),(e['phase_linear'],1),(0,4),(e['phase_q16'],32),(e['weighted_sum'],56),(e['max_centered'],64),(e['cordic_saturation'],12)])
    assert int(items[3],16)==wanted,line
    tail,total,stall=map(int,items[4:]);assert 0<=tail<=6000 and 0<total<=11000,line
    expected_stall=case%9 if rid<27 else 7;assert stall==expected_stall,line
    max_tail=max(max_tail,tail);max_total=max(max_total,total);stalls+=stall;run.update(ended=True,kind='F')
   elif tag=='D':
    assert len(items)==7 and list(map(int,items[4:]))==[run[k] for k in ('P','R','C')],line
    run.update(ended=True,kind='D',abort=int(items[3]));assert run['abort'] in (0,1)
   else:
    assert len(items)==5 and case==0,line;err=int(items[3]);assert err in (1,2,3)
    wanted=pack([(2000,32),(0x56780000,32),(0,1),(0,1),(err,4),(0,32),(0,56),(0,64),(0,12)])
    assert int(items[4],16)==wanted,line;run.update(ended=True,kind='E',error=err)
   counts[tag]+=1
  assert sorted(runs)==list(range(44)) and all(r['ended'] for r in runs.values())
  for i in range(27):assert runs[i]['kind']=='F' and runs[i]['case']==i
  for i in range(6):
   drop=runs[27+2*i];good=runs[28+2*i];assert drop['kind']=='D' and drop['case']==2*i and drop['abort']==i%2
   assert good['kind']=='F' and good['case']==2*i+1
  assert [runs[i]['error'] for i in range(39,44)]==[1,2,2,3,1]
  assert counts['F']==33 and counts['D']==6 and counts['E']==5 and stalls==150
  result.update(status='PHASE74_NUMERIC_PASS_LIMITED_SCOPE',native_result_checked=True,node_rows_checked=counts,full_transactions=33,discarded_transactions=6,protocol_error_results=5,max_tail_cycles=max_tail,max_total_cycles=max_total,stalled_cycles=stalls,formal_T11_T12_T13_PASS=False,fft_quality_or_final_modes_tested=False)
 print(json.dumps(result))
if __name__=='__main__':main()