from pathlib import Path
import json,hashlib,re,datetime
root=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=root/'docs/jobs/OTA003_source_lock.json'
assert sha(manifest)=='e3ea6d3fe2ee0dec000082050e44fafe77df30eb920aff98562d984c77cddcf9'
lock=json.loads(manifest.read_text())
for f in lock['files']:
 p=root/f['path'];assert p.stat().st_size==f['bytes'] and sha(p)==f['sha256'],f['path']
allowed={str((root/f['path']).resolve()).lower() for f in lock['files']}
results=[]
for stage,attempt,dut,tb,count in [('bridge','bridge_a01','ota_ddr_bridge','ota_ddr_bridge_tb',10),('capture','capture_a06','ota_capture_controller','ota_capture_controller_tb',11),('dual_rotation','dual_rotation_a01','cfo_rotate4','ota_dual_rotation_tb',15)]:
 a=root/'work/OTA003'/attempt;marker={'bridge':'OTA003_DDR_BRIDGE_PASS','capture':'OTA003_CAPTURE_CONTROL_PASS','dual_rotation':'OTA003_DUAL_ROTATION_PASS'}[stage]
 log=(a/'native.log').read_text(errors='replace')
 assert (a/'result.txt').read_text().strip()==marker
 assert len(re.findall('^'+marker+r'\b',log,re.M))==1
 assert f'OTA003_NATIVE_DONE stage={stage}' in log and 'Exiting Vivado' in log
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
 expected=sorted((root/f'sim/vendor/link010r1/{n}.sv').resolve() for n in ('xpm_cdc','xpm_fifo','xpm_memory')) if stage=='bridge' else []
 assert sorted(selected)==expected
 elab=(sim/'elaborate.log').read_text(errors='replace')
 assert not re.search(r'Compiling module xpm\.xpm_',elab)
 for name in (['xpm_fifo_async','xpm_cdc_single','xpm_cdc_sync_rst'] if stage=='bridge' else []):
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
 ps=json.loads((a/'process_summary.json').read_text(encoding='utf-8-sig'))
 assert ps['launcher_exit_code']==0 and not ps['timed_out'] and ps['tree_closed_utc'] and len(ps['seen_identities'])>=16
 results.append(dict(stage=stage,functional_status='PASS',process_status='RECORDED_TREE_CLOSED',process_identities=len(ps['seen_identities']),process_summary_sha256=sha(a/'process_summary.json'),actual_source_count=count,result_sha256=sha(a/'result.txt'),actual_sources_sha256=sha(a/'actual_sources.tsv'),binding='INDEPENDENT_EXACT_BOUNDARY_CHECK_PASS',simulation_finish=re.search(r'\$finish called at time : (.+)',log).group(1),logs=nested))
report=dict(job='OTA003',revision='A01',grant='SYNC_OTA_OTA003_A01_20260916T232929Z',review_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),manifest_sha256=sha(manifest),frozen_inputs_verified=len(lock['files']),stages=results,repair_review='Tcl changed only root and verifier paths. Verifier none mode now requires ZERO compiled XPM files for designs with no XPM instances; exact installed-XPM exclusion and fifo mode boundaries remain. Independently checked PRJs, source sets, logs and process summaries. No RTL/TB/vector/threshold change.',scope='Bridge protocol/CDC; full-range finite scheduler using labelled algorithm services; two-symbol real coordinate plus two distinct rotations. Not whole OTA algorithm/continuous rate/synthesis/NI/board acceptance.')
(root/'reports/OTA003/ASTRA_REVIEW.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('OTA003_ASTRA_REVIEW_PASS',len(lock['files']),'locked files;',len(results),'stages; recorded trees closed')
