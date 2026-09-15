"""Frozen LINK010 native create/simulate controller; no automatic stage retries."""
from pathlib import Path
import argparse,datetime as dt,importlib.util,json,shutil,re,ast
ROOT=Path('D:/008_MA_Dev/T11_CFO')
def module(name,p):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
Q=module('link010_stage_guard',ROOT/'tools/cfo_phase74_guard_v1.py')
A=module('link010_admission',ROOT/'tools/link010_admission.py')
B=module('link010r1_binding',ROOT/'tools/verify_link010r1_binding.py')
LOCK=ROOT/'docs/LINK010R1_SOURCE_LOCK.json';LOCK_SHA='F01D289223D90FE71F3767B1030B35809AA1C651FC249EDA3362AB5E455F3069'
TCL=ROOT/'vivado/link010r1_project.tcl';VERIFY=ROOT/'tools/verify_link010r1.py';XPR=ROOT/'vivado/CFO_LINK010R1/CFO_LINK010R1.xpr';SIM=XPR.parent/'CFO_LINK010R1.sim/sim_1/behav/xsim'
HARD={'create':120,'simulate':600}
def paths(root,a,stage):
 return [a/f'{stage}{s}' for s in ['.log','.jou','.stdout.log','.stderr.log','_actual_sources.csv','_project_identity.txt']]+[a/'link010_actual.txt',a/'link010r1_reset_audit.txt']+[SIM/x for x in ['xvlog.log','compile.log','elaborate.log','xelab.log','simulate.log','xsim.log','xsim.dir/cfo_estimator_link_tb_behav/xsimkernel.log']]
def marks(root,a,stage):
 ps=paths(root,a,stage);return {'ready':Q.marker(ps,f'CFO_LINK010R1_READY action={stage} '),'done':Q.marker(ps,f'CFO_LINK010R1_NATIVE_DONE action={stage}'),'passed':Q.marker(ps,'CFO_LINK010_PASS ')}
Q.paths=paths;Q.marks=marks
info=Q.info;wjson=Q.wjson

def check_lock():
 lock=json.loads(LOCK.read_text('utf-8-sig'));rows=[]
 for x in lock['files']+lock['vendor_dependencies']:
  y=info(ROOT/x['path']);rows.append({'path':x['path'],'expected_sha256':x['sha256'],'actual':y,'matches':y.get('sha256')==x['sha256'] and y.get('bytes')==x['bytes']})
 return lock,{'lock_sha256':info(LOCK).get('sha256'),'all_members_match':all(x['matches'] for x in rows),'members':rows,'all_checks':info(LOCK).get('sha256')==LOCK_SHA and all(x['matches'] for x in rows)}
def admitted(stage):
 ad=A.snapshot(stage,Q=Q);slot=ad.get('grant',{}).get('slot',{})
 # The manager must bind a fresh grant to this exact job, source lock and runner.
 exact={'job':slot.get('authorized_job')=='CFO-LINK010R1','manifest':slot.get('manifest_sha256')==LOCK_SHA,'runner':slot.get('script_sha256')==info(Path(__file__))['sha256']}
 ad['r1_exact_grant_checks']=exact;ad['all_checks']=ad['all_checks'] and all(exact.values());return ad

def command(a,stage):return [str(Q.VIVADO),'-mode','batch','-source',str(TCL),'-log',str(a/f'{stage}.log'),'-journal',str(a/f'{stage}.jou'),'-tclargs',stage,str(a)]
def verify(a=None,stage=None):
 args=[]
 if a:
  args=['--sources',a/f'{stage}_actual_sources.csv','--identity',a/f'{stage}_project_identity.txt']
  if stage=='simulate':args+=['--actual',a/'link010_actual.txt','--reset-audit',a/'link010r1_reset_audit.txt']
 r=Q.py(VERIFY,*args)
 try:r['parsed']=json.loads(r['stdout'].splitlines()[-1])
 except Exception:r['parsed']=None
 return r

def native_identity_samples(r):
 # A late READY flush cannot erase earlier valid native identity observations.
 # Require an exact READY PID within the private Job, reconciled census, memory,
 # CPU and stable creation identity. This check accepts no process-name shortcut.
 p=Path(r['paths']['samples']);rows=[]
 expected='c:/nifpga/programs/vivado2021_1/bin/unwrapped/win64.o/vivado.exe'
 if p.is_file():
  for line in p.read_text('utf-8').splitlines():
   x=json.loads(line);ids=x.get('active_process_ids',[]);tree=x.get('active_process_tree',[])
   y=next((q for q in tree if q.get('pid')==r.get('ready_pid')),None)
   if not y:continue
   ok=(r['ready_pid'] in ids and not x.get('job_census_issues') and not x.get('job_census_error') and not x.get('job_process_open_failures') and x.get('job_pid_cross_check',{}).get('match') and len(tree)==len(ids) and str(y.get('image_path','')).replace('\\','/').casefold()==expected and y.get('creation_filetime_100ns',0)>0 and y.get('private_usage_bytes') is not None and y.get('cpu_time_100ns') is not None)
   if ok:rows.append({'utc':x['utc'],'pid':y['pid'],'creation_filetime_100ns':y['creation_filetime_100ns'],'ready_already_visible':x.get('stage_progress',{}).get('ready',{}).get('found',False)})
 return {'samples':len(rows),'consistent_creation_identity':len({x['creation_filetime_100ns'] for x in rows})==1,'observations':rows}

def passed(r,v,stage):
 m=r.get('markers',{});c=r.get('final_census_before_close',{})
 observed=r['saved_native_identity_check']=native_identity_samples(r)
 ok=bool(r.get('binding_succeeded') and r.get('events',{}).get('zero') and c.get('empty_verified') and r.get('native_exit_code_final')==0 and not r.get('controller_errors') and not r.get('persistent_telemetry_fault') and not r.get('termination_requested_by_controller') and m.get('ready',{}).get('found') and m.get('done',{}).get('found') and r.get('ready_pid',0)>0 and observed['samples']>=1 and observed['consistent_creation_identity'] and v.get('exit_code')==0 and v.get('parsed'))
 diagnostics=[]
 logs=[Path(r['paths']['log']),Path(r['paths']['stdout']),Path(r['paths']['stderr'])]
 if stage=='simulate':logs += [SIM/x for x in ['compile.log','xvlog.log','elaborate.log','xelab.log','simulate.log','xsim.log']]
 for p in logs:
  if p.exists():diagnostics += [{'path':str(p),'line':line} for line in p.read_text('utf-8',errors='replace').splitlines() if re.match(r'^(?:ERROR:|Error:|FATAL:|Fatal:|FATAL_ERROR:)',line.strip())]
 r['native_error_diagnostics']=diagnostics;ok=ok and not diagnostics
 if stage=='simulate':
  z=re.fullmatch(r'CFO_LINK010_PASS unique=4 completed=22 protocol_errors=10 max_tail=(\d+) max_total=(\d+) source_stalls=(\d+) full_runs=21 reset_discards=4 abort_discards=4',m.get('passed',{}).get('line') or '')
  ok=bool(ok and z and int(z[1])<=7800 and int(z[2])<=1170000 and int(z[3])>0 and v['parsed']['native_checked'] and v['parsed'].get('reset_audit',{}).get('status')=='LINK010R1_RESET_AUDIT_PASS')
  r['vendor_binding_check']=B.run(SIM)
  ok=ok and r['vendor_binding_check']['all_checks']
 return ok


def artifact_manifest(a,c):
 if c.get('native_started') and 'post_native_inventory' not in c:
  fr=json.loads((a/'EXECUTION_FREEZE.json').read_text('utf-8'))
  post=A.post_snapshot(fr['admission'],Q=Q);wjson(a/'POST_NATIVE_INVENTORY.json',post)
  c['post_native_inventory']=post
  c['old_project_bytes_unchanged']=all(info(Path(p)).get('sha256')==x.get('sha256') for p,x in fr['old_projects'].items())
  c['controller_bytes_unchanged']=info(Path(__file__))['sha256']==info(a/'cfo_link010r1_guard_v1_frozen.py')['sha256']
 ch=wjson(a/'ATTEMPT_COMPLETION.json',c);rows=[];seen=set()
 for p in list(a.rglob('*'))+list(XPR.parent.rglob('*')):
  if p.is_file() and p.name!='ATTEMPT_ARTIFACT_MANIFEST.json' and str(p) not in seen:
   if a in p.parents or p==XPR or p.suffix.lower() in {'.log','.jou','.txt','.prj','.wdb','.wcfg','.pb'}:rows.append(info(p));seen.add(str(p))
 mh=wjson(a/'ATTEMPT_ARTIFACT_MANIFEST.json',{'schema':'link010r1_artifacts_v1','completion_sha256':ch,'artifacts':rows})
 clock=a/'report_clock.json';z=json.loads(clock.read_text());z.update(status='COMPLETE',ended_utc=Q.utc(),final_status=c['status']);wjson(clock,z)
 # Rewrite once after the clock's terminal state, so manifest hashes are final.
 rows=[info(Path(x['path'])) for x in rows];mh=wjson(a/'ATTEMPT_ARTIFACT_MANIFEST.json',{'schema':'link010r1_artifacts_v1','completion_sha256':ch,'artifacts':rows})
 print(json.dumps({'status':c['status'],'attempt':str(a),'completion_sha256':ch,'manifest_sha256':mh}));return 0 if c['status']=='PASS' else 3

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--self-check',action='store_true');args=ap.parse_args()
 if args.self_check:
  for p in [Path(__file__),ROOT/'tools/link010_admission.py',VERIFY]:ast.parse(p.read_text())
  lock,lc=check_lock();v=verify();checks={'lock':lc['all_checks'],'vector_verify':v['exit_code']==0,'x64_job':Q.G.PTR_SIZE==8 and Q.G.JOB_ACCOUNTING==1,'xpr_absent':not XPR.exists()}
  print(json.dumps({'status':'PASS' if all(checks.values()) else 'FAIL','checks':checks,'native_started':False}));return 0 if all(checks.values()) else 2
 parent=ROOT/'work/CFO_LINK010R1';parent.mkdir(exist_ok=True);a=parent/f"attempt_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}_luna";a.mkdir()
 shutil.copy2(Path(__file__),a/'cfo_link010r1_guard_v1_frozen.py');ep=a/'controller_events.jsonl'
 wjson(a/'report_clock.json',{'thread_id':'01a076f0-d8c0-72a0-8371-cb2ff29c1b28','status':'ACTIVE','started_utc':Q.utc(),'interval_minutes':15})
 lock,lc=check_lock();v=verify();ad=admitted('create')
 old_paths=[ROOT/'vivado'/n/(n+'.xpr') for n in ['CFO_SYNC','CFO_COORD','CFO_PHASE74','CFO_FFT256','CFO_BACKEND74','CFO_FFT2048','CFO_FRONT2048','CFO_LINK010']]
 old={str(p):info(p) for p in old_paths};checks={'source_lock':lc['all_checks'],'vectors':v['exit_code']==0,'fresh_xpr':not XPR.exists(),'admission':ad['all_checks'],'planned_free_memory':ad.get('memory',{}).get('available_physical_bytes',0)>=6*1024**3,'old_projects_present':all(x.get('exists') for x in old.values())}
 fr={'schema':'link010r1_execution_freeze_v1','job_id':'CFO-LINK010R1','utc':Q.utc(),'attempt':str(a),'controller':info(Path(__file__)),'source_lock':lc,'project':{k:lock[k] for k in ['part','hardware_top','simulation_top','project_members']},'old_projects':old,'preflight_verify':v,'admission':ad,'commands':{s:command(a,s) for s in HARD},'hard_timeout_seconds':HARD,'zero_grace_seconds':5,'memory':{'expected_gib':[1.5,3.0],'warning_gib':4,'preflight_free_gib':6,'immediate_severe_free_gib':.25,'sustained_severe_free_gib':.5,'sustained_seconds':30},'parallel':{'general':8,'synth':8,'xelab':16,'native_groups':1,'matlab':0},'checks':checks}
 fsha=wjson(a/'EXECUTION_FREEZE.json',fr);Q.event(ep,'execution_freeze_written',sha256=fsha)
 out={};c={'schema':'link010r1_completion_v1','attempt':str(a),'execution_freeze_sha256':fsha,'status':'BLOCKED_PREFLIGHT','stages':out,'checks':checks,'native_started':False,'scope':'Reset-contract correction for atomic z CDC; unchanged 22F/10E/8D numerical cases, plus edge audit; no full waveform, synthesis or physical CDC/timing qualification.'}
 if not all(checks.values()):return artifact_manifest(a,c)
 for stage in ['create','simulate']:
  # Admission and source hashes must be fresh immediately before each native launch.
  ad=admitted(stage);_,lc2=check_lock()
  if stage=='simulate':
   ad['created_project_bytes_unchanged']=info(XPR).get('sha256')==out['create']['xpr'].get('sha256');ad['all_checks']=ad['all_checks'] and ad['created_project_bytes_unchanged']
  wjson(a/f'PRE_{stage.upper()}_ADMISSION.json',ad)
  if not ad['all_checks'] or not lc2['all_checks'] or ad.get('memory',{}).get('available_physical_bytes',0)<6*1024**3:
   c.update(status='BLOCKED_BEFORE_'+stage.upper(),successful_create_checkpoint_retained=out.get('create',{}).get('status')=='PASS');return artifact_manifest(a,c)
  r=out[stage]=Q.stage(ROOT,a,stage,fr['commands'][stage],HARD[stage],ep);c['native_started']=True
  r['verify']=verify(a,stage);_,postlock=check_lock();r['source_check']=postlock;r['xpr']=info(XPR)
  if XPR.exists():shutil.copy2(XPR,a/f'CFO_LINK010R1_{stage}.xpr')
  r['status']='PASS' if passed(r,r['verify'],stage) and postlock['all_checks'] and XPR.exists() else 'FAIL'
  if stage=='simulate':
   r['copied_logs']=[]
   for name in ['xvlog.log','compile.log','elaborate.log','simulate.log','cfo_estimator_link_tb_vlog.prj','compile.bat','xsim.ini']:
    src=SIM/name
    if src.exists():dst=a/('native_'+name);shutil.copy2(src,dst);r['copied_logs'].append(info(dst))
  wjson(a/f'{stage}_result.json',r)
  if r['status']!='PASS':c['status']='BLOCKED_AFTER_'+stage.upper();return artifact_manifest(a,c)
 oldok=all(info(Path(p)).get('sha256')==x.get('sha256') for p,x in old.items());unchanged=info(Path(__file__))['sha256']==info(a/'cfo_link010r1_guard_v1_frozen.py')['sha256']
 post=A.post_snapshot(fr['admission'],Q=Q);wjson(a/'POST_NATIVE_INVENTORY.json',post)
 # A later manager regrant is not a failure of already completed stages; preserve external identities separately.
 c.update(status='PASS' if oldok and unchanged and post['all_checks'] else 'FAIL',old_project_bytes_unchanged=oldok,controller_bytes_unchanged=unchanged,post_native_inventory=post,t10_not_operated=True,no_matlab=True,no_synthesis_or_implementation=True)
 return artifact_manifest(a,c)
if __name__=='__main__':raise SystemExit(main())