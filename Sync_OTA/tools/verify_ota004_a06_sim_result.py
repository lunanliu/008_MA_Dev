"""Accept only the full smoke marker plus no native errors and held-reset evidence."""
from pathlib import Path
import re,sys,json,hashlib
root=Path(__file__).resolve().parents[1];sim=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve()
assert sim.is_relative_to(root/'Sync_OTA.sim') and out.is_relative_to(root/'work/OTA004')
log=(sim/'simulate.log').read_text(errors='replace')
errors=re.findall(r'(?mi)^\s*(?:error|fatal|critical warning)\s*:.*$',log)
assert not errors,('native simulation errors',errors)
assert 'XPM_CDC_SYNC_RST S-1' not in log and 'XPM_FIFO_RESET S-1' not in log
assert (sim/'result.txt').read_text().strip()=='OTA004_REAL_TOP_SMOKE_PASS'
assert log.count('OTA004_EARLY_CANCEL_RESET_PASS real_fifo_probes=4 clocks_both_directions=1 depths_32_1024=1 all_busy_clear_before_reassert=1')==1
assert log.count('OTA004_LOCAL_RESET_FIFO_PASS real_fifo_probes=4 old_epoch_flushed=1 new_records_per_probe=2 stale_duplicate_reorder=0')==1
assert log.count('OTA004_RESET_GUARD_PASS cancel_completion=1 invalid_completion=1 both_acknowledged=1 reset_continuous=1')==1
samples=re.findall(r'OTA004_STARTUP_RESET_SAMPLE sample=(\d+) raw_reset=1 estimator_reset_n=0 accepted_words=0',log)
assert samples==['1','2','3','4'],samples
fpo=re.findall(r'Warning: WARNING : aresetn must be asserted or deasserted for a minimum of 2 cycles[^\n]*\n([^\n]+)',log)
assert len(fpo)<=1,('repeated reset width warning',fpo)
for context in fpo:
 assert 'Time: 20 ns ' in context and '/frontend/fine_confirmation/u_quality_divider_vendor_adapter/u_quality_divider/' in context and '/i_fpo/has_aresetn/check_reset' in context,context
# XPM startup SIM_ASSERT_CHK information remains visible; no runtime error is whitelisted.
report=dict(status='OTA004_REAL_SMOKE_STRICT_PASS',native_errors=0,reset_guard=True,early_cancel_real_fifo_probes=4,local_reset_fifo_probes=4,startup_reset_samples=4,startup_fpo_warning_count=len(fpo),startup_warning_boundary='Only 20ns internal FPO initialization, with public reset held at 8/16/24/32ns and no accepted data',simulate_log_sha256=hashlib.sha256((sim/'simulate.log').read_bytes()).hexdigest())
(out/'strict_smoke_review.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
