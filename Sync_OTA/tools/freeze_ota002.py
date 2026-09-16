from pathlib import Path
import hashlib,json,subprocess,py_compile,datetime
root=Path(__file__).resolve().parents[1]
rtl=['rtl/control/ota_sfo_context_join.sv','rtl/common/ota_async_fifo.sv','rtl/sfo/first_resampling/sfo_first_pass_descriptor.sv','rtl/sfo/second_resampling/sfo_second_pass_descriptor.sv','rtl/cfo/ota_cfo_chain.sv','rtl/buffer/ota_frame_store.sv']
rtl += ['rtl/cfo/'+n+'.sv' for n in ['cfo_estimator_link_v2','cfo_estimate74_backend','cfo_fft74_quality_v2','cfo_divide_rne64wide','cfo_fft256_core','cfo_phase74_core_v2','cfo_divide_rne64','cfo_rotate4','cfo_coordinate_control','cfo_front2048_window','cfo_fft2048_core']]
tbs=['sim/tb/'+n+'.sv' for n in ['ota_context_boundary_tb','ota_backend74_tb','ota_cfo_control_tb']]
files=rtl+tbs
files += [f'{directory}/{name}.sv' for directory in ['rtl/vendor/xpm','sim/vendor/link010r1'] for name in ['xpm_cdc','xpm_memory','xpm_fifo']]
files += ['ip/cfo/'+n+'.mem' for n in ['cfo_rot_lut','fft2048_twiddle','front2048_coefficient_index','front2048_coefficient_table','fft256_twiddle','phase74_atan_q31']]
files += ['sim/data/link010_'+n+'.mem' for n in ['input','read','result']]
files += ['tools/vivado/run_ota002.tcl','tools/vivado/run_threads.tcl','tools/verify_ota002_binding.py','tools/verify_link010r1_models.py','docs/jobs/OTA002_ZH.md','docs/provenance/OTA002_REUSED_INPUTS.json']
assert len(files)==len(set(files))
parser=Path('D:/008_MA_Dev/Sync_SFO/work/functional_review_tools_20260915/package/verible-v0.0-4214-gce503962-win64/verible-verilog-syntax.exe')
checks=[]
for rel in rtl+tbs:
 r=subprocess.run([str(parser),str(root/rel)],capture_output=True,text=True)
 assert r.returncode==0,(rel,r.stdout,r.stderr)
 checks.append(dict(path=rel,static_syntax_exit=r.returncode))
for rel in ['tools/verify_ota002_binding.py','tools/verify_link010r1_models.py']:
 compile((root/rel).read_text(encoding='utf-8-sig'),str(root/rel),'exec')
out=root/'docs/jobs/OTA002_source_lock.json'
assert not out.exists(),'frozen package already exists'
rows=[dict(path=p,bytes=(root/p).stat().st_size,sha256=hashlib.sha256((root/p).read_bytes()).hexdigest()) for p in files]
obj=dict(job='OTA002',revision='A01',created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),astra='01a0ac17-f298-7201-848c-58d09e90ebb4',luna='01a0ac17-4f21-7be3-8690-540c11497b1e',stages=['context','backend74','cfo_control'],files=rows,static_syntax=checks,scope='Only the three directed jobs. No full OTA qualification or synthesis.')
out.write_text(json.dumps(obj,indent=2),encoding='utf-8')
print('OTA002_FILES',len(rows),'STATIC_RTL_TB',len(checks),'MANIFEST_SHA256',hashlib.sha256(out.read_bytes()).hexdigest())
