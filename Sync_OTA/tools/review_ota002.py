from pathlib import Path
import json,hashlib,re,datetime
root=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=root/'docs/jobs/OTA002_source_lock.json'
assert sha(manifest)=='f0655da779236dc40026c06e9b63b0a6f8e0b0769447321a0883dd2b1ae4ef95'
lock=json.loads(manifest.read_text())
for f in lock['files']:
 p=root/f['path'];assert p.stat().st_size==f['bytes'] and sha(p)==f['sha256'],f['path']
allowed={str((root/f['path']).resolve()).lower() for f in lock['files']}
results=[]
for stage,attempt,dut,tb,count in [('context','context_a06','ota_sfo_context_join','ota_context_boundary_tb',12),('backend74','backend74_a01','cfo_estimator_link','ota_backend74_tb',20),('cfo_control','cfo_control_a01','ota_cfo_chain','ota_cfo_control_tb',28)]:
 a=root/'work/OTA002'/attempt;marker='OTA002_'+stage.upper()+'_PASS'
 log=(a/'native.log').read_text(errors='replace')
 assert (a/'result.txt').read_text().strip()==marker
 assert len(re.findall('^'+marker+r'\b',log,re.M))==1
 assert f'OTA002_NATIVE_DONE stage={stage}' in log and 'Exiting Vivado' in log
 assert f'part=xcvu11p-flgb2104-2-e top={dut} sim={tb} xelab=16' in log
 assert re.search(r'^OTA_THREADS pid=\d+ general=8 synth=8$',log,re.M)
 actual=(a/'actual_sources.tsv').read_text().splitlines();assert len(actual)==count
 for row in actual:
  fs,p,lib,synth,simuse=row.split('\t')
  assert str(Path(p).resolve()).lower() in allowed,p
  assert lib=='ota_xpm'
  if '/rtl/vendor/' in p:assert (synth,simuse)==('1','0')
  if '/sim/vendor/' in p:assert (synth,simuse)==('0','1')
 binding=json.loads((a/'binding_verified.json').read_text());sim=Path(binding['simdir'])
 prjs=list(sim.glob('*_vlog.prj'));assert len(prjs)==1
 # Reapply exact-boundary original checks independently with PRJ comment/continuation support.
 prj=prjs[0].read_text();lines=[];pending=''
 for raw in prj.splitlines():
  line=raw.strip()
  if not line or line=='nosort' or line.startswith('#'):continue
  pending+=' '+line.rstrip('\\').strip()
  if not line.endswith('\\'):lines.append(pending.strip());pending=''
 assert not pending
 selected=[]
 for line in lines:
  assert line.startswith(('sv ota_xpm ','verilog ota_xpm ')),line
  for quoted in re.findall(r'"([^"]+)"',line):
   p=(sim/quoted).resolve()
   if p.name in ('xpm_cdc.sv','xpm_fifo.sv','xpm_memory.sv'):selected.append(p)
 assert sorted(selected)==sorted((root/f'sim/vendor/link010r1/{n}.sv').resolve() for n in ('xpm_cdc','xpm_fifo','xpm_memory'))
 elab=(sim/'elaborate.log').read_text(errors='replace')
 assert not re.search(r'Compiling module xpm\.xpm_',elab)
 for name in ['xpm_fifo_async','xpm_cdc_single','xpm_cdc_sync_rst']:
  assert re.search(r'Compiling module ota_xpm\.'+name+r'\b',elab),name
 commands=[line for line in elab.splitlines() if 'xelab' in line and '--' in line];assert commands
 libs=re.findall(r'-L\s+([^\s"]+)',commands[0]);assert 'ota_xpm' in libs
 if 'xpm' in libs:assert libs.index('ota_xpm')<libs.index('xpm')
 assert (sim/'xsim.dir/ota_xpm').is_dir()
 nested=[]
 for p in [a/'native.log',*sim.glob('*.log')]:
  t=p.read_text(errors='replace')
  assert not re.search(r'^(ERROR:|FATAL:|Fatal:)|AssertionError|Traceback|\$fatal',t,re.M),str(p)
  nested.append(dict(path=p.relative_to(root).as_posix(),sha256=sha(p)))
 results.append(dict(stage=stage,functional_status='PASS',process_status='HISTORICAL_TREE_GAP_RETAINED' if stage=='backend74' else 'RECORDED_TREE_CLOSED',actual_source_count=count,result_sha256=sha(a/'result.txt'),actual_sources_sha256=sha(a/'actual_sources.tsv'),binding='INDEPENDENT_EXACT_BOUNDARY_CHECK_PASS',simulation_finish=re.search(r'\$finish called at time : (.+)',log).group(1),logs=nested))
report=dict(job='OTA002',revision='A01',grant='SYNC_OTA_OTA002_A01_20260916T221248Z',review_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),manifest_sha256=sha(manifest),frozen_inputs_verified=len(lock['files']),stages=results,repair_review='Tcl only changed root and verifier path. Parser handles PRJ comments/continuations. Repaired startswith checks are less strict for module suffixes; Astra independently reapplied original exact regex boundaries and all three pass. RTL/TB/input/thresholds unchanged.',process_limitation='backend74 lacks full historical subprocess tree because monitor used PowerShell reserved PID variable. Retained, no native rerun. Current zero-tool scan is separate evidence, not proof of historical tree completeness.',scope='Directed context/CDC and four complete 74-observation backend groups; true CFO chain elaboration plus three coarse beats/cancel. No full OTA numerical closure, synthesis, implementation, sustained throughput, NI or board claim.')
(root/'reports/OTA002/ASTRA_REVIEW.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('OTA002_ASTRA_REVIEW_PASS',len(lock['files']),'locked files;',len(results),'stages; backend process provenance qualified')
