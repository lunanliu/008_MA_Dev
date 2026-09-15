"""Identity and exact-result checks for the independent coordinate RTL milestone."""
from pathlib import Path
import argparse,csv,hashlib,json
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--actual',type=Path);ap.add_argument('--sources',type=Path);ap.add_argument('--identity',type=Path);a=ap.parse_args()
 lock=json.loads((R/'docs/COORD003_SOURCE_LOCK.json').read_text(encoding='utf-8-sig'))
 for item in lock['files']:
  p=R/item['path'];assert p.is_file() and sha(p)==item['sha256'],f"Source changed: {p}"
 cases=json.loads((R/'sim/vectors/coordinate_cases.json').read_text(encoding='utf-8'))
 for name,hash_value in cases['source_hashes'].items():assert sha(R/name)==hash_value,f'Published reference changed: {name}'
 expected=[int(x,16) for x in (R/'sim/vectors/coordinate_expected.mem').read_text().splitlines()]
 assert len(expected)==367 and cases['published_parameter_matches']==216
 report=dict(status='SOURCE_IDENTITIES_PASS',frozen_files=len(lock['files']),published_reference_files=len(cases['source_hashes']),unique_cases=len(expected),published_parameter_matches=216,native_result_checked=False)
 if a.sources:
  actual={(x['fileset'],str(Path(x['path']).resolve()).casefold()) for x in csv.DictReader(a.sources.open(encoding='utf-8-sig',newline=''))}
  wanted={(x['fileset'],str((R/x['path']).resolve()).casefold()) for x in lock['project_members']}
  assert actual==wanted,dict(extra=sorted(actual-wanted),missing=sorted(wanted-actual))
  report['actual_project_members']=len(actual)
 if a.identity:
  props=dict(line.split('=',1) for line in a.identity.read_text(encoding='utf-8-sig').splitlines())
  for k,v in {'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_coordinate_control','simulation_top':'cfo_coordinate_control_tb','vivado':'2021.1','xelab_jobs':'16'}.items():assert props[k]==v,(k,props[k])
  report['project_identity']='PASS'
 if a.actual:
  rows=[x.split() for x in a.actual.read_text(encoding='utf-8-sig').splitlines()]
  wanted_indices=list(range(367))+[1,3,5,7,9,11]
  assert len(rows)==len(wanted_indices)==373,len(rows)
  stalls=0;latencies=[]
  for row,k in zip(rows,wanted_indices):
   assert len(row)==4 and int(row[0])==k,row
   assert int(row[1],16)==expected[k],f'Output mismatch: case {k}'
   latency=int(row[2]);stall=int(row[3]);assert 0<=latency<=512 and stall==(k%8 if len(latencies)<367 else 5),(k,latency,stall)
   stalls+=stall;latencies.append(latency)
  report.update(status='COORDINATE_NUMERIC_PASS_LIMITED_SCOPE',native_result_checked=True,completed=373,exact_output_bits_per_result=279,max_latency_cycles=max(latencies),stalled_cycles=stalls,invalid_unique_results=sum(not x['expected']['ok'] for x in cases['rows']),reset_discards_required=3,abort_discards_required=3,formal_T11_T12_T13_PASS=False)
 print(json.dumps(report))
if __name__=='__main__':main()