from pathlib import Path
import csv,json,sys
r=Path(__file__).resolve().parents[1]
p=Path(sys.argv[1]) if len(sys.argv)>1 else r/'reports/reference/autonomous_results.csv'
a=list(csv.DictReader(p.open(encoding='utf-8-sig')))
e=json.loads((r/'sim/data/autonomous_manifest.json').read_text())['expected']
assert len(a)==len(e)==4,'Expected exactly four valid result rows'
prev=-1;maxcfo=0
for k,(v,t) in enumerate(zip(a,e)):
    assert int(v['epoch'])==0 and int(v['rx_frame_id'])==k,'Epoch/id/order mismatch'
    assert int(v['candidate_id'])>prev;prev=int(v['candidate_id'])
    assert int(v['fine_absolute'])==t['true_start'],'Fine TO mismatch'
    err=abs(int(v['cfo_hz'])-t['expected_cfo_hz']);maxcfo=max(maxcfo,err)
    assert err<=1000,'CFO mismatch'
    assert int(v['status'],16)&0x800,'Invalid result status'
print(json.dumps(dict(status='FOUR_FRAME_READBACK_PASS',frames=4,fine_error_samples=0,max_cfo_error_hz=maxcfo,throughput_qualified=False,board_qualified=False)))
