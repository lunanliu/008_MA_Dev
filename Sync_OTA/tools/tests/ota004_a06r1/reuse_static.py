from pathlib import Path
import hashlib,json,tempfile,tkinter,datetime
r=Path('D:/008_MA_Dev/Sync_OTA')
entry=(r/'tools/vivado/run_ota004_a06r1.tcl').read_text()
t=tkinter.Tcl();assert t.call('info','complete',entry)==1
t.eval(entry[entry.index('proc read_lines '):entry.index('proc hooks ')])
t.eval(entry[entry.index('proc verify_prior_core_sources '):entry.index('proc audit_reused_ips ')])
prior=(r/'Sync_OTA.runs/synth_1/sync_ota_top.tcl').read_text()
order=(r/'work/OTA004/synth_a05/compile_order_synthesis.txt').read_text()
for before,after in [('rtl/control/sync_ota_top_a05.sv','rtl/control/sync_ota_top_a06.sv'),('rtl/cfo/ota_cfo_chain_a02.sv','rtl/cfo/ota_cfo_chain_a06.sv'),('rtl/common/ota_async_fifo.sv','rtl/common/ota_async_fifo_a06.sv'),('rtl/cfo/cfo_estimator_link_v2.sv','rtl/cfo/cfo_estimator_link_a06.sv')]:
 prior=prior.replace(before,after);order=order.replace(before,after)
checks=[]
with tempfile.TemporaryDirectory(prefix='ota_core_reuse_static_') as tmp:
 out=Path(tmp);(out/'compile_order_synthesis.txt').write_text(order)
 t.setvar('root',r.as_posix());t.setvar('out',out.as_posix())
 t.call('verify_prior_core_sources',prior)
 checks.append(dict(name='127_generated_production_sources_and_order',result='PASS'))
 actual=(out/'reused_core_actual_production_order.txt').read_text().splitlines();assert len(actual)==127
 variants={
  'one_old_FIFO_source':prior.replace('rtl/common/ota_async_fifo_a06.sv','rtl/common/ota_async_fifo.sv'),
  'compile_order_changed':prior.replace(actual[0],'TEMP_REPLACEMENT').replace(actual[1],actual[0]).replace('TEMP_REPLACEMENT',actual[1]),
  'additional_unreviewed_RTL':prior+'\nread_verilog -sv {D:/008_MA_Dev/Sync_OTA/rtl/unreviewed.sv}\n',
  'truncated_script':prior+'\nread_verilog {\n'
 }
 for name,text in variants.items():
  try:t.call('verify_prior_core_sources',text)
  except tkinter.TclError:checks.append(dict(name=name,result='EXPECTED_REJECTION'))
  else:raise AssertionError(name)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=['tools/vivado/run_ota004_a06r1.tcl','tools/vivado/audit_ota004_a06r1_gray.tcl','tools/verify_ota004_a06r1_synth_result.py','tools/verify_ota004_a06r1_project.py','tools/monitor_ota004_a06r1.ps1','docs/jobs/OTA004_A06R1_ZH.md']
review=dict(status='A06R1_FINAL_STATIC_REVIEW_PASS_PENDING_NEW_NATIVE_GRANT',created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),supplements='reports/OTA004/A06R1_STATIC_REVIEW.json; authoritative final script hashes below supersede that earlier draft hash list',luna_read_only_review='four-source reuse fingerprint concern resolved with all four files plus exact 127 generated production sources and compile order',tests=checks,existing_tests=dict(auditor=27,monitor=17,gray_macros=24,gray_destination_bits=128),native_started=False,files=[dict(path=p,bytes=(r/p).stat().st_size,sha256=sha(r/p)) for p in files])
p=r/'reports/OTA004/A06R1_REUSE_SUPPLEMENT.json';assert not p.exists();p.write_text(json.dumps(review,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(status=review['status'],reuse_checks=len(checks))))

