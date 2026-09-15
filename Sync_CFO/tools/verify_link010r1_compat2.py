"""Read-only frozen compat2 source and actual-source properties check; no native launch."""
from pathlib import Path
import argparse,csv,hashlib,json
R=Path(__file__).resolve().parents[1]
OLD='sim/tb/cfo_estimator_link_r1_compat1_tb.sv'
NEW='sim/tb/cfo_estimator_link_r1_compat2_tb.sv'
NEW_SHA='AF414075F3C976CBA25301E3C0866A098286BCC9F7AF08429DACD4B9B1792796'
BASE='reports/LINK010R1_COMPAT1_V3_RESULT_REVIEW_20260915/032_simulate_actual_sources.csv'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--sources',type=Path);a=ap.parse_args()
 lp=R/'docs/LINK010R1_COMPAT1_SOURCE_LOCK.json'
 assert sha(lp)=='4245E75E0D3049F9F7E92EDCF68B4E286BE30DE59747D8A03A0BBE14C2C3FFA3'
 lock=json.loads(lp.read_text('utf-8'))
 for x in lock['files']+lock['vendor_dependencies']:
  p=R/x['path'];assert p.stat().st_size==x['bytes'] and sha(p)==x['sha256'],str(p)
 assert sha(R/NEW)==NEW_SHA,'New TB differs from the statically reviewed bytes'
 out={'status':'COMPAT2_FROZEN_SOURCE_PASS','base_frozen_files_verified':len(lock['files']),'vendor_dependencies_verified':len(lock['vendor_dependencies']),'tb_sha256':NEW_SHA,'native_started':False,'native_behavior_qualified':False,'check_scope':'Frozen bytes and optional actual source table; not a new equivalence or behavior test'}
 if a.sources:
  assert sha(R/BASE)=='15FB0FDCC5383A297832E4EE3BD1631E5E3C811077B4B72DBC9ED24499B1008C'
  cols=['fileset','path','library','used_in_synthesis','used_in_simulation','used_in_implementation']
  def rows(p,replace):
   with p.open(newline='',encoding='utf-8-sig') as h:
    reader=csv.DictReader(h);assert reader.fieldnames==cols;res=[];replaced=0
    for row in reader:
     if replace and Path(row['path']).resolve()==(R/OLD).resolve():row['path']=str(R/NEW);replaced+=1
     row['path']=str(Path(row['path']).resolve()).casefold()
     for k in cols[3:]:
      if row[k] in ['true','false']:row[k]='1' if row[k]=='true' else '0'
     res.append(tuple(row[k] for k in cols))
   assert len(res)==25 and len(set(res))==25
   if replace:assert replaced==1,'Baseline must contain exactly one compat1 TB'
   return sorted(res)
  assert rows(a.sources,False)==rows(R/BASE,True),'Actual membership or source properties differ'
  out['actual_project_members']=25;out['all_actual_source_properties_preserved']=True
 print(json.dumps(out))
if __name__=='__main__':main()
