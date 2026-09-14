"""Read-only FRONT009 source, coefficient reconstruction, integer and native checks."""
from pathlib import Path
import json,hashlib,csv,runpy,argparse
R=Path(__file__).resolve().parents[1]
def load(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--sources',type=Path);ap.add_argument('--identity',type=Path);ap.add_argument('--actual',type=Path);a=ap.parse_args()
 lock=load(R/'docs/FRONT009_SOURCE_LOCK.json')
 for x in lock['files']:assert (R/x['path']).stat().st_size==x['bytes'] and sha(R/x['path'])==x['sha256'],x['path']
 d=load(R/'sim/vectors/front2048_cases.json');cs=d['cases'];assert len(cs)==90
 for p,h in d['source_hashes'].items():assert sha(R/p)==h,p
 ref=runpy.run_path(str(R/'tools/front2048_reference.py'));pack=ref['pack'];co=ref['coeffs']()
 for c in cs:assert ref['front'](c['input'],co[c['window']])==c['expected'],c['label']
 assert [c['window'] for c in cs[:74]]==list(range(74)) and len({(c['frame'],c['generation']) for c in cs[:74]})==1
 def mem(path):return [int(x,16) for x in (R/path).read_text().split()]
 assert mem('sim/vectors/front2048_input.mem')==[pack([(i,26),(q,26)]) for c in cs for i,q in c['input']]
 assert mem('sim/vectors/front2048_pilot.mem')==[w for c in cs for w in c['expected']['pilot_words']]
 assert mem('sim/vectors/front2048_result.mem')==[ref['result_word'](c) for c in cs]
 assert mem('sim/vectors/front2048_metadata.mem')==[pack([(c['frame'],32),(c['generation'],32),(c['window'],7)]) for c in cs]
 pairs=d['coefficient_pairs'];indices=mem('ip/front2048_coefficient_index.mem');table=mem('ip/front2048_coefficient_table.mem')
 assert len(indices)==60680 and len(pairs)==8 and table==[pack([(i,18),(q,18)]) for i,q in pairs]
 assert [pairs[v] for v in indices]==[x for w in co for x in w]
 result={'status':'FRONT2048_SOURCE_ORACLE_PASS','frozen_files':len(lock['files']),'reference_identities':len(d['source_hashes']),'unique_cases':90,'coefficient_entries_exact':60680,'native_checked':False}
 if a.sources:
  rows=list(csv.DictReader(a.sources.open(newline='',encoding='utf-8-sig')));actual={(x['fileset'],str(Path(x['path']).resolve()).casefold()) for x in rows};wanted={(x['fileset'],str((R/x['path']).resolve()).casefold()) for x in lock['project_members']}
  assert actual==wanted and len(rows)==len(actual),dict(extra=sorted(actual-wanted),missing=sorted(wanted-actual));result['actual_project_members']=len(rows)
 if a.identity:
  props=dict(x.split('=',1) for x in a.identity.read_text('utf-8-sig').splitlines())
  for k,v in {'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_front2048_window','simulation_top':'cfo_front2048_tb','vivado':'2021.1','xelab_jobs':'16'}.items():assert props[k]==v,(k,props[k])
  assert Path(props['project']).resolve()==(R/'vivado/CFO_FRONT2048/CFO_FRONT2048.xpr').resolve();result['project_identity']='PASS'
 if a.actual:
  runs={};counts={k:0 for k in ['P','Z','D','E']};stalls=0;max_tail=max_total=max_adjusted=0
  with a.actual.open(encoding='utf-8-sig') as f:
   for line in f:
    it=line.split();tag=it[0];assert tag in counts,line;rid,k=map(int,it[1:3]);assert 0<=k<90
    c=cs[k];e=c['expected'];r=runs.setdefault(rid,{'case':k,'P':0,'ended':False});assert r['case']==k and not r['ended'],line
    if tag=='P':
     n=r['P'];assert len(it)==5 and int(it[3])==n and int(it[4],16)==e['pilot_words'][n],line;r['P']+=1
    elif tag=='Z':
     assert len(it)==9 and r['P']==820 and int(it[3],16)==ref['result_word'](c),line
     tail,total,stall,gap,adj=map(int,it[4:]);assert 0<tail<=13500 and 0<total<=19000 and 0<adj<=15600 and adj==total-stall-gap
     assert stall==k%5+(0 if rid<90 else 7) and gap==(0 if k%3==0 else 2047)
     stalls+=stall;max_tail=max(max_tail,tail);max_total=max(max_total,total);max_adjusted=max(max_adjusted,adj);r.update(ended=True,kind=tag)
    elif tag=='D':
     assert len(it)==7 and r['P']==int(it[6]),line;r.update(ended=True,kind=tag,abort=int(it[3]),where=int(it[4]),B=int(it[5]))
    else:
     assert len(it)==5 and k==0 and r['P']==0,line;err=int(it[3]);win=74 if rid==112 else cs[0]['window']
     wanted=pack([(cs[0]['frame'],32),(cs[0]['generation'],32),(win,7),(0,76),(0,10),(0,16),(err,4)]);assert int(it[4],16)==wanted,line;r.update(ended=True,kind=tag,error=err)
    counts[tag]+=1
  assert sorted(runs)==list(range(113)) and all(r['ended'] for r in runs.values())
  for i in range(90):assert runs[i]['kind']=='Z' and runs[i]['case']==i
  for i in range(8):
   r=runs[90+2*i];g=runs[91+2*i];assert r['kind']=='D' and r['case']==2*i and r['abort']==i%2 and r['where']==i//2 and g['kind']=='Z' and g['case']==2*i+1
   if r['where']==0:assert r['B']==r['P']==0
   elif r['where']==1:assert 1401<=r['B']<=1403 and r['P']==0
   elif r['where']==2:assert r['B']==11264 and 13<=r['P']<=14
   else:assert r['B']==11264 and r['P']==820
  assert [runs[i]['error'] for i in range(106,113)]==[1,2,2,1,2,1,3]
  assert counts['Z']==98 and counts['D']==8 and counts['E']==7 and 82026<=counts['P']<=82028 and stalls==250
  result.update(status='FRONT2048_NUMERIC_PASS_LIMITED_SCOPE',native_checked=True,rows=counts,complete_transactions=98,discarded_transactions=8,protocol_errors=7,output_stall_cycles=stalls,max_tail_cycles=max_tail,max_total_cycles=max_total,max_adjusted_service_cycles=max_adjusted,all_74_window_coefficient_rows_tested=True,pilot_multiply_sum_integrated=True,whole_frame_waveform_tested=False,clock500_timing_qualified=False,cdc_or_estimator_backend_integrated=False,formal_T11_T12_T13_PASS=False)
 print(json.dumps(result))
if __name__=='__main__':main()