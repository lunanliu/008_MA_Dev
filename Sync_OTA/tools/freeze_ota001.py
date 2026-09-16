from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
files=['rtl/buffer/ota_frame_store.sv','rtl/control/ota_frontend_descriptor.sv','sim/tb/ota_frame_store_tb.sv','sim/tb/ota_frontend_descriptor_tb.sv','tools/vivado/run_threads.tcl','tools/vivado/run_ota001.tcl','docs/jobs/OTA001_ZH.md','docs/architecture/ARCHITECTURE_A01_ZH.md']
rows=[dict(path=p,sha256=hashlib.sha256((root/p).read_bytes()).hexdigest(),bytes=(root/p).stat().st_size) for p in files]
manifest=dict(job_id='OTA001',revision='A01',astra='01a0ac17-f298-7201-848c-58d09e90ebb4',luna='01a0ac17-4f21-7be3-8690-540c11497b1e',scope='two targeted native tests only; no full-core PASS',files=rows)
output=root/'docs/jobs/OTA001_source_lock.json'
if output.exists():raise RuntimeError('frozen manifest exists; create revision instead')
output.write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('MANIFEST_SHA256',hashlib.sha256(output.read_bytes()).hexdigest())
