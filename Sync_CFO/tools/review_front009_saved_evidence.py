"""FRONT009 evidence review only: no FFT recomputation, MATLAB or native launch."""
from pathlib import Path
import json,hashlib,csv,datetime,shutil
R=Path('D:/008_MA_Dev/T11_CFO');A=R/'work/CFO_FRONT009/attempt_20260914T183142105831Z_luna';O=R/'reports/FRONT009_REVIEW_20260914'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def load(p):return json.loads(p.read_text('utf-8-sig'))
def pack(items):
 n=0
 for x,b in items:n=(n<<b)|(int(x)&((1<<b)-1))
 return n
def word(c):return pack([(c['frame'],32),(c['generation'],32),(c['window'],7)]+[(v,38) for v in c['expected']['z']]+[(820,10),(c['expected']['fft_saturations'],16),(0,4)])
def main():
 O.mkdir(exist_ok=True)
 assert sha(A/'ATTEMPT_COMPLETION.json')=='BD1461E85026874FC198B5007DE59237FA2E315EF68DB384048130A5B7E804EB'
 assert sha(A/'ATTEMPT_ARTIFACT_MANIFEST.json')=='05C61B6CC5C8A884C5D1A9C08BFAAFD272969F8DD738027088ABD88268F99B9B'
 c=load(A/'ATTEMPT_COMPLETION.json');manifest=load(A/'ATTEMPT_ARTIFACT_MANIFEST.json');assert c['status']=='PASS'
 for x in manifest['artifacts']:
  p=Path(x['path']);assert p.is_file() and p.stat().st_size==x['bytes'] and sha(p)==x['sha256'],p
 lock=load(R/'docs/FRONT009_SOURCE_LOCK.json');assert sha(R/'docs/FRONT009_SOURCE_LOCK.json')=='09A6A7F5AD994934B9CA30137139A7639A16638DB966AB3498AEDA9CF9765393'
 for x in lock['files']:assert (R/x['path']).stat().st_size==x['bytes'] and sha(R/x['path'])==x['sha256'],x['path']
 assert sha(R/'tools/cfo_front2048_guard_v1.py')==sha(A/'cfo_front2048_guard_v1_frozen.py')=='9F3430079FBE5DEE3436C87B6E5BB7221FD03778458B10271B79A06B8195ADC9'
 data=load(R/'sim/vectors/front2048_cases.json');cs=data['cases'];assert len(cs)==90
 for p,h in data['source_hashes'].items():assert sha(R/p)==h,p
 expected={(x['fileset'],str((R/x['path']).resolve()).casefold()) for x in lock['project_members']}
 resources={}
 for name,s in c['stages'].items():
  assert s['status']=='PASS' and s['native_exit_code_final']==0 and s['binding_succeeded'] and not s['controller_errors'] and not s['persistent_telemetry_fault'] and not s['termination_requested_by_controller']
  z=s['final_census_before_close'];assert z['empty_verified'] and z['pids']==[] and z['active_processes']==z['active_accounting']['active_processes']==0 and z['pid_cross_check']['match']
  rows=list(csv.DictReader((A/f'{name}_actual_sources.csv').open(newline='',encoding='utf-8-sig')));actual={(x['fileset'],str(Path(x['path']).resolve()).casefold()) for x in rows};assert len(rows)==13 and actual==expected
  props=dict(x.split('=',1) for x in (A/f'{name}_project_identity.txt').read_text('utf-8-sig').splitlines())
  for k,v in {'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_front2048_window','simulation_top':'cfo_front2048_tb','vivado':'2021.1','xelab_jobs':'16'}.items():assert props[k]==v
  samples=[json.loads(x) for x in (A/f'{name}.samples.jsonl').read_text().splitlines()];assert samples
  for x in samples:
   assert not x['job_census_issues'] and not x['job_census_error'] and not x['job_process_open_failures']
   assert len(x['active_process_ids'])==x['active_process_count']==x['job_pid_list_count']==x['job_active_accounting']['active_processes']
   assert all(p.get('creation_filetime_100ns') and p.get('image_path') and p.get('private_usage_bytes') is not None for p in x['active_process_tree'])
  resources[name]={'elapsed_seconds':s['launch_to_zero_seconds'],'peak_job_private_commit_bytes':s['job_extended_at_loop_end']['peak_job_private_commit_bytes'],'minimum_available_physical_bytes':min(x['system_memory']['available_physical_bytes'] for x in samples),'job_zero_confirmed':True}
 runs={};counts={k:0 for k in ['P','Z','D','E']};stalls=0;tailmax=totalmax=adjmax=0
 for line in (A/'front2048_actual.txt').read_text().splitlines():
  it=line.split();tag=it[0];rid,k=map(int,it[1:3]);assert tag in counts and 0<=k<90
  cc=cs[k];r=runs.setdefault(rid,{'case':k,'P':0,'ended':False});assert r['case']==k and not r['ended']
  if tag=='P':
   assert len(it)==5 and int(it[3])==r['P'] and int(it[4],16)==cc['expected']['pilot_words'][r['P']];r['P']+=1
  elif tag=='Z':
   assert len(it)==9 and r['P']==820 and int(it[3],16)==word(cc)
   tail,total,stall,gap,adj=map(int,it[4:]);assert 0<tail<=13500 and 0<total<=19000 and 0<adj<=15600 and adj==total-stall-gap
   assert gap==(0 if k%3==0 else 2047) and stall==k%5+(0 if rid<90 else 7)
   stalls+=stall;tailmax=max(tailmax,tail);totalmax=max(totalmax,total);adjmax=max(adjmax,adj);r.update(kind=tag,ended=True)
  elif tag=='D':
   assert len(it)==7 and r['P']==int(it[6]);r.update(kind=tag,ended=True,abort=int(it[3]),where=int(it[4]),B=int(it[5]))
  else:
   err=int(it[3]);assert len(it)==5 and k==0 and r['P']==0
   wanted=pack([(cs[0]['frame'],32),(cs[0]['generation'],32),(74 if rid==112 else cs[0]['window'],7),(0,76),(0,10),(0,16),(err,4)])
   assert int(it[4],16)==wanted;r.update(kind=tag,ended=True,error=err)
  counts[tag]+=1
 assert sorted(runs)==list(range(113)) and all(r['ended'] for r in runs.values())
 for i in range(90):assert runs[i]['kind']=='Z' and runs[i]['case']==i
 for i in range(8):
  r=runs[90+2*i];g=runs[91+2*i];assert r['kind']=='D' and r['case']==2*i and r['abort']==i%2 and r['where']==i//2 and g['kind']=='Z' and g['case']==2*i+1
  if i//2==0:assert r['P']==r['B']==0
  elif i//2==1:assert 1401<=r['B']<=1403 and r['P']==0
  elif i//2==2:assert r['B']==11264 and 13<=r['P']<=14
  else:assert r['B']==11264 and r['P']==820
 assert [runs[i]['error'] for i in range(106,113)]==[1,2,2,1,2,1,3]
 assert counts=={'P':82026,'Z':98,'D':8,'E':7} and stalls==250
 assert c['controller_bytes_unchanged'] and c['old_project_bytes_unchanged'] and c['t10_unchanged']['before']==c['t10_unchanged']['after']
 assert 'CFO_FRONT2048_PASS unique=90 completed=98 protocol_errors=7 max_tail=13398 max_total=17505 max_adjusted=15448 stalled_cycles=250 reset_discards=4 abort_discards=4' in (A/'native_xsim.log').read_text('utf-8-sig')
 out={'status':'PASS_FRONT2048_WINDOW_FFT_PILOT_SUM_ONLY','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'artifacts_hashchecked':len(manifest['artifacts']),'locked_files_verified':len(lock['files']),'reference_source_hashes_verified':len(data['source_hashes']),'actual_project_members_each_stage':13,'completion_sha256':sha(A/'ATTEMPT_COMPLETION.json'),'manifest_sha256':sha(A/'ATTEMPT_ARTIFACT_MANIFEST.json'),'rows':counts,'unique_windows':90,'complete_transactions':98,'discarded_transactions':8,'protocol_errors':7,'output_stalls':stalls,'max_tail_cycles':tailmax,'max_total_cycles':totalmax,'max_adjusted_service_cycles':adjmax,'all_74_coefficient_rows_verified':True,'resources':resources,'controller_frozen_bytes_preserved':True,'t10_identities_unchanged':True,'review_method':'Compare saved actual records to frozen published-anchored expected records; no FFT/MATLAB/native recomputation','slot_status':'T11_YIELDED; no new native launch until explicit manager grant','unqualified_scopes':['whole-frame contiguous waveform','CDC','estimator backend integration','CFO frame buffers and two-pass rotation','synthesis resources','500 MHz physical timing','full T11/T12/T13 PASS']}
 (O/'INDEPENDENT_REVIEW.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
 for name in ['ATTEMPT_COMPLETION.json','ATTEMPT_ARTIFACT_MANIFEST.json','EXECUTION_FREEZE.json','simulate_actual_sources.csv','simulate_project_identity.txt','simulate_verify.json','native_xvlog.log','native_xelab.log','native_xsim.log']:
  shutil.copy2(A/name,O/name)
 print(json.dumps(out))
if __name__=='__main__':main()