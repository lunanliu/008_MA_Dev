from pathlib import Path
import hashlib,json,re,datetime
R=Path(__file__).resolve().parents[2]
A=R/'work/CFO_GUARD002/attempt_20260914T122355387050Z_luna'
O=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
manifest=A/'GUARD002_ARTIFACT_MANIFEST_FINAL_V2.json'
assert sha(manifest)=='4DF016C74F140E06AF00B64B116C6E56549C4C4E0D7A934D01AE29C11BE97B2E'
checks=[]
for row in read(manifest)['files']:
 p=Path(row['path']);assert p.is_relative_to(A)
 actual=sha(p);assert actual==row['sha256'],p
 checks.append(dict(path=str(p.relative_to(A)),sha256=actual))
raw=read(A/'ATTEMPT_COMPLETION.json');modes=[]
for result in raw['modes']:
 mode=result['mode'];log=(A/f'{mode}.log').read_text(encoding='utf-8',errors='replace')
 ready=re.search(rf'^CFO_GUARD_READY mode={mode} pid=(\d+) milliseconds=(\d+)\s*$',log,re.M);assert ready
 pid=int(ready[1]);samples=[json.loads(x) for x in (A/f'{mode}.samples.jsonl').read_text(encoding='utf-8-sig').splitlines()]
 t=result['event_mono_ns'];assert t['create_suspended']<t['job_assigned']<t['launch']<t['ready']<t['zero']
 assert result['binding_succeeded'] and result['active_pids_at_loop_end']==[] and result['active_pids_after_finally']==[]
 if mode in ('normal','error'):
  assert result['native_exit_code']==(0 if mode=='normal' else 7)
  marker='CFO_GUARD_NORMAL_END' if mode=='normal' else 'CFO_GUARD_EXPECTED_ERROR'
  assert re.search(rf'^{marker}\s*$',log,re.M)
 else:
  assert result['termination_reason']=='HOLD_READY_PLUS_3S'
  assert 3<=(t['trigger']-t['ready'])/1e9<=4.5
  assert (t['zero']-t['trigger'])/1e9<=5
 zero_samples=[s for s in samples if 0 in s['active_process_ids']]
 missing=[s for s in samples if s['instant_job_private_commit_bytes'] is None]
 modes.append(dict(mode=mode,native_pid_from_ready=pid,native_exit_code=result['native_exit_code'],samples=len(samples),pid_zero_samples=len(zero_samples),instant_private_missing_samples=len(missing),native_pid_observed_in_samples=any(pid in s['active_process_ids'] for s in samples),launch_to_zero_seconds=(t['zero']-t['launch'])/1e9,ready_to_trigger_seconds=(t['trigger']-t['ready'])/1e9 if t['trigger'] else None,trigger_to_zero_seconds=(t['zero']-t['trigger'])/1e9 if t['trigger'] else None,min_available_bytes=min(s['system_memory']['available_physical_bytes'] for s in samples),job_peak_private_bytes=max(s['job_memory']['peak_job_private_commit_bytes'] for s in samples)))
review=dict(schema='cfo_guard002_astra_review_v1',utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),manifest_sha256=sha(manifest),artifact_hash_checks=checks,modes=modes,normal_and_error_propagation='PASS',automatic_job_termination_deadline='PASS',kernel_job_final_empty='CONFIRMED_BY_KERNEL_COUNT',per_process_identity_and_instant_resource_telemetry='FAIL',overall_guard_acceptance='PARTIAL_REPAIR_REQUIRED',defect='ProcessIdList is ULONG_PTR; v2 uses four-byte strides on 64-bit Windows and emits PID 0, omitting the actual Vivado PID. Job enumeration count and handle-based termination are distinct and remain supported.',required_repair='Use pointer-sized parsing, complete ctypes signatures, BasicAccounting cross-check, explicit telemetry failure handling. Validate parser offline then only one affected hold native probe before next computation.',t10_affected=False,rerun_all_three_probes_required=False,source_reference='https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_process_id_list')
(O/'INDEPENDENT_REVIEW.json').write_text(json.dumps(review,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in review.items() if k!='artifact_hash_checks'}))