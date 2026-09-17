from pathlib import Path
import re,json,sys,hashlib
root=Path(__file__).resolve().parents[1];out=Path(sys.argv[1]).resolve();assert out.is_relative_to(root/'work/OTA004')
run=root/'Sync_OTA.runs/synth_1/runme.log';log=run.read_text(errors='replace')
errors=re.findall(r'(?mi)^\s*(?:error|fatal|critical warning)\s*:.*$',log);assert not errors,errors
assert 'Synthesis finished with 0 errors' in log
cdc=(out/'synth_cdc.txt').read_text(errors='replace');counts={key:int(n) for key,n in re.findall(r'(?m)^(CDC-\d+)\s+(?:Critical|Warning|Info)\s+(\d+)\s',cdc)}
assert counts.get('CDC-1',0)==0 and counts.get('CDC-13',0)==0,('raw reset control bypass remains',counts)
# Only OR-combined coordinated global/session resets feeding the reset macros
# may remain CDC-10. No data, busy, fault or state-decode path is exempted.
accepted=[]
for line in cdc.splitlines():
 if not re.match(r'^\s*\d+\s+CDC-10\s+',line):continue
 ells=re.split(r'\s{2,}',line.strip());src,dst=ells[-2:]
 assert src.startswith(('algorithm_reset_guard/reset_active_reg','cfo/compute_cancel150_reg')),('unreviewed CDC-10 source',src,dst)
 assert ('reset' in dst and dst.endswith(('/D','/PRE','/CLR'))),('unreviewed CDC-10 endpoint',dst)
 accepted.append(dict(source=src,destination=dst,scope='coordinated reset assertion only; local release synchronization retained'))
xdc=(out/'synth_applied_constraints.xdc').read_text(errors='replace')
assert re.search(r'(?m)^set_max_delay\b',xdc) and re.search(r'(?m)^set_bus_skew\b',xdc), 'vendor gray-pointer delay/skew constraints absent'
assert not re.search(r'(?m)^set_clock_groups\s.*-asynchronous',xdc),'blanket clock group is forbidden'
assert 'syncstages_ff' in xdc or 'dest_graysync_ff' in xdc
report=dict(status='OTA004_A06_CDC_SOURCE_REPAIR_LIMITED_PASS',native_errors=0,native_critical_warnings=0,cdc_counts=counts,reset_only_cdc10=accepted,scoped_vendor_gray_constraints_present=True,physical_timing='NOT_QUALIFIED',runme_sha256=hashlib.sha256(run.read_bytes()).hexdigest(),applied_xdc_sha256=hashlib.sha256((out/'synth_applied_constraints.xdc').read_bytes()).hexdigest())
(out/'strict_synth_review.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
