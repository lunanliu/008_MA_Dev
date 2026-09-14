"""Read-only source, integer-oracle and native FFT2048 result verification."""
from pathlib import Path
import json,hashlib,csv,runpy,argparse
R=Path(__file__).resolve().parents[1]
def load(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--sources',type=Path);ap.add_argument('--identity',type=Path);ap.add_argument('--actual',type=Path);a=ap.parse_args()
 lock=load(R/'docs/FFT008_SOURCE_LOCK.json')
 for x in lock['files']:assert (R/x['path']).stat().st_size==x['bytes'] and sha(R/x['path'])==x['sha256'],x['path']
 d=load(R/'sim/vectors/fft2048_cases.json');cs=d['cases'];assert len(cs)==20
 for p,h in d['source_hashes'].items():assert sha(R/p)==h,p
 ref=runpy.run_path(str(R/'tools/fft2048_reference.py'));pack=ref['pack']
 for c in cs:assert ref['fft2048'](c['input'])==c['expected'],c['label']
 schedule=ref['address_audit']();assert schedule['run_cycles']==11341
 def mem(name):return [int(x,16) for x in (R/'sim/vectors'/name).read_text().split()]
 assert mem('fft2048_input.mem')==[pack([(i,26),(q,26)]) for c in cs for i,q in c['input']]
 assert mem('fft2048_output.mem')==[pack([(i,26),(q,26)]) for c in cs for i,q in c['expected']['output']]
 assert mem('fft2048_butterfly.mem')==[w for c in cs for w in c['expected']['butterfly_words']]
 assert mem('fft2048_saturation.mem')==[c['expected']['saturations'] for c in cs]
 assert mem('fft2048_window.mem')==[c['window'] for c in cs]
 assert [int(x,16) for x in (R/'ip/fft2048_twiddle.mem').read_text().split()]==[pack([(i,18),(q,18)]) for i,q in ref['TW']]
 result={'status':'FFT2048_SOURCE_ORACLE_PASS','frozen_files':len(lock['files']),'reference_identities':len(d['source_hashes']),'unique_cases':20,'native_checked':False}
 if a.sources:
  rows=list(csv.DictReader(a.sources.open(newline='',encoding='utf-8-sig')));actual={(x['fileset'],str(Path(x['path']).resolve()).casefold()) for x in rows};wanted={(x['fileset'],str((R/x['path']).resolve()).casefold()) for x in lock['project_members']}
  assert actual==wanted and len(rows)==len(actual),dict(extra=sorted(actual-wanted),missing=sorted(wanted-actual));result['actual_project_members']=len(rows)
 if a.identity:
  props=dict(x.split('=',1) for x in a.identity.read_text('utf-8-sig').splitlines())
  for k,v in {'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_fft2048_core','simulation_top':'cfo_fft2048_tb','vivado':'2021.1','xelab_jobs':'16'}.items():assert props[k]==v,(k,props[k])
  assert Path(props['project']).resolve()==(R/'vivado/CFO_FFT2048/CFO_FFT2048.xpr').resolve();result['project_identity']='PASS'
 if a.actual:
  runs={};counts={k:0 for k in ['B','O','F','D','E']};stalls=0;max_tail=max_total=max_adjusted=0
  with a.actual.open(encoding='utf-8-sig') as f:
   for line in f:
    it=line.split();tag=it[0];assert tag in counts,line;rid,k=map(int,it[1:3]);assert 0<=k<20
    c=cs[k];e=c['expected'];r=runs.setdefault(rid,{'case':k,'B':0,'O':0,'ended':False});assert r['case']==k and not r['ended'],line
    if tag in ['B','O']:
     n=r[tag];assert len(it)==5 and int(it[3])==n,line
     if tag=='B':wanted=e['butterfly_words'][n]
     else:
      assert r['B']==11264
      wanted=pack([(c['frame'],32),(c['generation'],32),(c['window'],7),(n,11),(int(n==2047),1)]+[(z,26) for z in e['output'][n]]+[(e['saturations'],16),(0,4)])
     assert int(it[4],16)==wanted,line;r[tag]+=1
    elif tag=='F':
     assert len(it)==8 and r['B']==11264 and r['O']==2048,line
     tail,total,stall,gap,adj=map(int,it[3:]);assert 0<tail<=11450 and 0<total<=19000 and 0<adj<=15550 and adj==total-stall-gap
     assert stall==4*(k%4)+(0 if rid<20 else 7) and gap==(0 if k%3==0 else 2047)
     stalls+=stall;max_tail=max(max_tail,tail);max_total=max(max_total,total);max_adjusted=max(max_adjusted,adj);r.update(ended=True,kind=tag)
    elif tag=='D':
     assert len(it)==7 and [r['B'],r['O']]==list(map(int,it[5:])),line
     r.update(ended=True,kind=tag,abort=int(it[3]),where=int(it[4]))
    else:
     assert len(it)==5 and k==0 and r['B']==r['O']==0,line;err=int(it[3]);win=74 if rid==38 else cs[0]['window']
     wanted=pack([(5000,32),(0x89ab0000,32),(win,7),(0,11),(1,1),(0,52),(0,16),(err,4)]);assert int(it[4],16)==wanted,line;r.update(ended=True,kind=tag,error=err)
    counts[tag]+=1
  assert sorted(runs)==list(range(39)) and all(r['ended'] for r in runs.values())
  for i in range(20):assert runs[i]['kind']=='F' and runs[i]['case']==i
  for i in range(6):
   r=runs[20+2*i];g=runs[21+2*i];assert r['kind']=='D' and r['case']==2*i and r['abort']==i%2 and r['where']==i//2 and g['kind']=='F' and g['case']==2*i+1
   if r['where']==0:assert r['B']==r['O']==0
   elif r['where']==1:assert 1401<=r['B']<=1403 and r['O']==0
   else:assert r['B']==11264 and r['O']==13
  assert [runs[i]['error'] for i in range(32,39)]==[1,2,2,1,2,1,3]
  assert counts['F']==26 and counts['D']==6 and counts['E']==7 and counts['O']==53274 and stalls==210
  result.update(status='FFT2048_NUMERIC_PASS_LIMITED_SCOPE',native_checked=True,rows=counts,complete_transactions=26,discarded_transactions=6,protocol_errors=7,output_stall_cycles=stalls,max_tail_cycles=max_tail,max_total_cycles=max_total,max_adjusted_service_cycles=max_adjusted,full_frame_tested=False,clock500_timing_qualified=False,pilot_multiply_sum_integrated=False,formal_T11_T12_T13_PASS=False)
 print(json.dumps(result))
if __name__=='__main__':main()