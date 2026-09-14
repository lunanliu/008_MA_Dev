from pathlib import Path
import hashlib,json,re,datetime,subprocess
R=Path(__file__).resolve().parents[2];A=R/'work/CFO_COORD003/attempt_20260914T131705246420Z_luna';O=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
manifest=A/'ATTEMPT_ARTIFACT_MANIFEST_FINAL.json';M=load(manifest);checks=[]
for row in M['artifacts']:
 p=Path(row['path']);actual=sha(p);assert actual==row['sha256'],f'Artifact changed: {p}';checks.append(dict(path=str(p),sha256=actual))
C=load(A/'ATTEMPT_COMPLETION.json');F=load(A/'EXECUTION_FREEZE.json');X=load(A/'FINAL_XPR_AUDIT.json')
assert sha(A/'ATTEMPT_COMPLETION.json')==M['completion_sha256']
assert sha(A/'EXECUTION_FREEZE.json')==C['execution_freeze']['sha256']
for k in ('controller','repaired_telemetry'):
 row=F[k]['info'];assert sha(Path(row['path']))==row['sha256']
assert sha(Path(X['final_project_xpr']['path']))==X['final_project_xpr']['sha256']
cmd=['C:/Python314/python.exe','-I','-B','-X','utf8',str(R/'tools/verify_coordinate.py'),'--actual',str(A/'coordinate_actual.txt'),'--sources',str(A/'simulate_actual_sources.csv'),'--identity',str(A/'simulate_project_identity.txt')]
r=subprocess.run(cmd,capture_output=True,text=True,encoding='utf-8');assert r.returncode==0,r.stderr
(O/'frozen_verifier_output.txt').write_text(r.stdout,encoding='utf-8');numeric=load(A/'simulate_verify.json')
# Recompute numeric fields from plain arbitrary-precision division, not DUT or expected.mem.
def rnd(n,d):
 q,rem=divmod(n,d);return q+int(rem*2>d or (rem*2==d and q&1))
def join(fields):
 v=0
 for x,b in fields:v=v*(1<<b)+(x% (1<<b))
 return v
rows=load(R/'sim/vectors/coordinate_cases.json')['rows'];actual=[x.split() for x in (A/'coordinate_actual.txt').read_text().splitlines()]
for raw in actual:
 row=rows[int(raw[0])];f=row['frequency_code'];o=row['raw_origin_q28'];d=row['step1_q28']*row['step2_q28'];mode=row['residual'];a=abs(f);mask=(1<<48)-1
 err=1 if f==-(1<<31) or o==-(1<<53) else 2 if not d else 3 if d>=1<<62 else 0
 om=st=ph=0
 if not err:
  om=rnd(abs(o)*(1<<44),d)&mask;st=rnd(a*((1<<32) if mode else d),500000000*(1 if mode else 65536))&mask
  if st>=1<<47:err=4
  else:ph=rnd(a*(om if mode else abs(o))*(65536 if mode else 4096),500000000)&mask
 if err:step32=phase32=step48=phase48=origin=0
 else:
  step48=(-1 if f>=0 else 1)*st;phase48=((-1 if (f>=0)==(o>=0) else 1)*ph)&mask;origin=(-1 if o<0 else 1)*om
  step32=(-1 if step48<0 else 1)*rnd(abs(step48),65536);phase32=rnd(phase48,65536)
 word=join([(row['frame'],32),(row['generation'],32),(mode,1),(int(not err),1),(err,4),(step32,32),(phase32,32),(step48,48),(phase48,48),(origin,49)])
 assert int(raw[1],16)==word,raw[0]
log=(A/'simulate.log').read_text(encoding='utf-8',errors='replace')
match=re.search(r'^CFO_COORD_PASS unique=(\d+) completed=(\d+) invalid=(\d+) max_latency=(\d+) stalled_cycles=(\d+) reset_discards=(\d+) abort_discards=(\d+)\s*$',log,re.M)
assert match and list(map(int,match.groups()))==[367,373,7,435,1311,3,3]
assert '--mt 16' in log and not re.search(r'^(ERROR:|FATAL:|Fatal:)',log,re.M)
stages=[];prior_zero=0
for name,S in C['stages'].items():
 times=S['event_mono_ns'];assert prior_zero<times['create_suspended']<times['job_assigned']<times['launch']<times['ready']<times['zero'];prior_zero=times['zero']
 assert S['binding_succeeded'] and S['end_census']['empty_verified'] and S['final_census_before_close']['empty_verified']
 assert not S['persistent_telemetry_fault'] and not S['controller_errors']
 samples=[json.loads(x) for x in (A/f'{name}.samples.jsonl').read_text(encoding='utf-8-sig').splitlines()]
 stable=[]
 for sm in samples:
  assert 0 not in sm['active_process_ids'];assert sm['job_pid_stride_bytes']==8
  if sm['active_process_count']:
   assert sm['job_pid_cross_check']['match'] and not sm['job_census_issues'] and not sm['job_process_open_failures'],sm
   assert sm['instant_job_private_commit_bytes'] is not None
   assert sm['instant_job_private_commit_bytes']==sum(x['private_usage_bytes'] for x in sm['active_process_tree'])
   for p in sm['active_process_tree']:assert p.get('image_path') and p.get('creation_filetime_100ns') and p.get('cpu_time_100ns') is not None
  if times['ready']<=sm['monotonic_ns']<(times['trigger'] or times['zero']) and S['ready_pid'] in sm['active_process_ids']:stable.append(sm)
 if name=='hold':assert len(stable)>=2 and 3<=(times['trigger']-times['ready'])/1e9<=4.5 and (times['zero']-times['trigger'])/1e9<=5
 else:assert S['native_exit_code']==0
 stages.append(dict(stage=name,seconds=(times['zero']-times['launch'])/1e9,saved_samples=len(samples),saved_ready_pid_samples=len(stable),maximum_instant_private_bytes=max(x['instant_job_private_commit_bytes'] or 0 for x in samples),job_peak_private_bytes=S['job_extended_at_loop_end']['peak_job_private_commit_bytes'],min_available_physical_bytes=min(x['system_memory']['available_physical_bytes'] for x in samples),ready_to_trigger_seconds=(times['trigger']-times['ready'])/1e9 if times['trigger'] else None,trigger_to_zero_seconds=(times['zero']-times['trigger'])/1e9 if times['trigger'] else None))
assert all(p['pid'] not in sm['active_process_ids'] for p in C['post_native_processes'] for name in C['stages'] for sm in [json.loads(x) for x in (A/f'{name}.samples.jsonl').read_text(encoding='utf-8-sig').splitlines()])
review=dict(schema='cfo_coord003_astra_review_v1',utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),scope='Coordinate-control arithmetic and protocol only',acceptance='PASS_LIMITED_SCOPE',guard_telemetry_and_cancel='PASS',frozen_artifact_count=len(checks),artifact_hashes=checks,completion_sha256=sha(A/'ATTEMPT_COMPLETION.json'),manifest_sha256=sha(manifest),final_xpr_sha256=sha(Path(X['final_project_xpr']['path'])),independently_recomputed_results=len(actual),unique_vectors=367,published_matlab_parameters=216,max_latency_cycles=435,latency_us_at_target_150MHz=435/150,stalled_cycles=1311,invalid_descriptors=7,reset_discards=3,abort_discards=3,stages=stages,warning_scope=['unused IP-generated directory is absent in a no-IP project','default wave-window size excludes two vector arrays; numeric checks unaffected'],formal_T11_T12_T13_PASS=False,matlab_run=False,synthesis_or_timing_qualified=False,t10_operated=False,next_gate='74-point estimation backend')
(O/'INDEPENDENT_REVIEW.json').write_text(json.dumps(review,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in review.items() if k!='artifact_hashes'}))