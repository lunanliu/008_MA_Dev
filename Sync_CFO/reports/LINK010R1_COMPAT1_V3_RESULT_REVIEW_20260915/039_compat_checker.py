"""Read-only exact TB equivalence and actual source-properties check; no native launch."""
from pathlib import Path
import argparse,csv,hashlib,json
R=Path(__file__).resolve().parents[1]
OLD='sim/tb/cfo_estimator_link_r1_tb.sv'
NEW='sim/tb/cfo_estimator_link_r1_compat1_tb.sv'
BASE='reports/LINK010R1_ELAB_REVIEW_20260915/030_simulate_actual_sources.csv'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--sources',type=Path);a=ap.parse_args()
 lp=R/'docs/LINK010R1_SOURCE_LOCK.json'
 assert sha(lp)=='F01D289223D90FE71F3767B1030B35809AA1C651FC249EDA3362AB5E455F3069'
 lock=json.loads(lp.read_text('utf-8'))
 for x in lock['files']+lock['vendor_dependencies']:
  p=R/x['path'];assert p.stat().st_size==x['bytes'] and sha(p)==x['sha256'],str(p)
 old=(R/OLD).read_bytes();new=(R/NEW).read_bytes()
 assert sha(R/NEW)=='4C7EC8E1FB2F194FF982130439CE90375C6414FC7B1B2C8A0F2D646A518B078E'
 changes=[(b'input bits=reset_audit_bits;',b'input reset_audit_bits;',2),(b'input epoch=reset_audit_epoch;',b'input reset_audit_epoch;',2),(b'reset_audit_fast_cb.bits',b'reset_audit_fast_cb.reset_audit_bits',1),(b'reset_audit_fast_cb.epoch',b'reset_audit_fast_cb.reset_audit_epoch',1),(b'reset_audit_slow_cb.bits',b'reset_audit_slow_cb.reset_audit_bits',1),(b'reset_audit_slow_cb.epoch',b'reset_audit_slow_cb.reset_audit_epoch',1)]
 f=old;b=new
 for x,y,n in changes:
  assert f.count(x)==n and b.count(y)==n
  f=f.replace(x,y);b=b.replace(y,x)
 assert f==new and b==old
 out={'status':'EXACT_TB_EQUIVALENCE_PASS_PENDING_NATIVE','replacement_count':8,'reverse_byte_identical':True,'base_frozen_files_verified':len(lock['files']),'vendor_dependencies_verified':len(lock['vendor_dependencies']),'tb_sha256':sha(R/NEW),'native_started':False}
 if a.sources:
  assert sha(R/BASE)=='0F28511DC926995990F8754232E9F5D0C11269A4E08029D8A2AC0420A391F92B'
  cols=['fileset','path','library','used_in_synthesis','used_in_simulation','used_in_implementation']
  def rows(p,replace):
   with p.open(newline='',encoding='utf-8-sig') as h:
    reader=csv.DictReader(h);assert reader.fieldnames==cols;res=[]
    for row in reader:
     if replace and Path(row['path']).resolve()==(R/OLD).resolve():row['path']=str(R/NEW)
     row['path']=str(Path(row['path']).resolve()).casefold()
     for k in cols[3:]:
      if row[k] in ['true','false']:row[k]='1' if row[k]=='true' else '0'
     res.append(tuple(row[k] for k in cols))
   assert len(res)==25 and len(set(res))==25
   return sorted(res)
  assert rows(a.sources,False)==rows(R/BASE,True),'Actual membership or source properties differ'
  out['actual_project_members']=25;out['all_actual_source_properties_preserved']=True
 print(json.dumps(out))
if __name__=='__main__':main()
