from pathlib import Path
import json,hashlib,re,datetime,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
manifest=root/'docs/jobs/OTA001_source_lock.json'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(manifest)=='341d18aaef1c368a1dca728e646bf2acb235c3facc34b469f65c05b37cbb7866'
lock=json.loads(manifest.read_text())
for f in lock['files']:
 p=root/f['path'];assert p.stat().st_size==f['bytes'] and sha(p)==f['sha256'],f['path']
results=[]
for stage,dut,rtl,marker in [('store','ota_frame_store','rtl/buffer/ota_frame_store.sv','OTA001_STORE_PASS'),('descriptor','ota_frontend_descriptor','rtl/control/ota_frontend_descriptor.sv','OTA001_DESCRIPTOR_PASS')]:
 a=root/'work/OTA001'/f'{stage}_a01'
 log=(a/'native.log').read_text(errors='replace')
 assert (a/'result.txt').read_text().strip()==marker
 assert len(re.findall('^'+marker+r'\b',log,re.M))==1
 assert not re.search(r'^(ERROR:|FATAL:|Fatal:)|Assertion.*(fail|FAIL)|assertion.*(fail|FAIL)',log,re.M)
 assert f'OTA001_NATIVE_DONE stage={stage}' in log and 'Exiting Vivado' in log
 assert f'part=xcvu11p-flgb2104-2-e top={dut} sim={dut}_tb xelab=16' in log
 assert re.search(r'^OTA_THREADS pid=\d+ general=8 synth=8$',log,re.M)
 actual=(a/'actual_sources.tsv').read_text().splitlines()
 expected=[f'sources_1\tTOP={dut}',f'sources_1\t{root.as_posix()}/{rtl}',f'sim_1\tTOP={dut}_tb',f'sim_1\t{root.as_posix()}/sim/tb/{dut}_tb.sv']
 assert actual==expected,(actual,expected)
 xpr=a/'project'/f'OTA001_{stage}.xpr'
 opts=ET.parse(xpr).getroot().find('Configuration').findall('Option')
 assert any(x.get('Name')=='Part' and x.get('Val')=='xcvu11p-flgb2104-2-e' for x in opts)
 nested=[]
 for p in (a/'project').rglob('*.log'):
  text=p.read_text(errors='replace')
  assert not re.search(r'^(ERROR:|FATAL:|Fatal:)|Assertion.*(fail|FAIL)|assertion.*(fail|FAIL)',text,re.M),str(p)
  nested.append(dict(path=str(p.relative_to(root)),sha256=sha(p)))
 results.append(dict(stage=stage,status='PASS_WITH_TB_WARNING' if stage=='descriptor' else 'PASS',native_log=str((a/'native.log').relative_to(root)),native_log_sha256=sha(a/'native.log'),xpr_sha256=sha(xpr),result_sha256=sha(a/'result.txt'),actual_sources_sha256=sha(a/'actual_sources.tsv'),simulation_finish=re.search(r'\$finish called at time : (.+)',log).group(1),warnings=[x for x in log.splitlines() if x.startswith('WARNING:')],nested_log_hashes=nested))
report=dict(job='OTA001',revision='A01',review_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),manifest_sha256=sha(manifest),frozen_inputs_verified=8,stages=results,scope='Frozen directed component checks only. No synthesis, full CFO origin proof, integration or DDR throughput qualification.',process_closure='Luna reports normal zero exits and stage cleanup scans. Independent current process snapshot recorded separately; memory log peak is not aggregate whole-tree peak.',deferred_issue='SEALED release_frame/replay_valid mutual exclusion; do not claim covered.')
(root/'reports/OTA001/ASTRA_REVIEW.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('OTA001_REVIEW_OK',len(results),'stages;',len(lock['files']),'frozen inputs')
