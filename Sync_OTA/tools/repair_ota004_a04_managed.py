"""Repair only failed managed XCI copies, after a complete byte-verified archive."""
from pathlib import Path
import sys,json,hashlib,shutil,os,datetime
root=Path(__file__).resolve().parents[1]
attempt=Path(sys.argv[1]).resolve()
assert attempt.is_relative_to(root/'work/OTA004') and attempt.is_dir(),attempt
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
baseline_path=root/'docs/jobs/OTA004_A04_REPAIR_BASELINE.json'
baseline=json.loads(baseline_path.read_text())
state_path=root/'work/OTA004/A04_MANAGED_XCI_REPAIR_STATE.json'
receipt_path=root/'work/OTA004/A04_MANAGED_XCI_REPAIR_RECEIPT.json'
def save(p,data):
 temp=p.with_name(p.name+'.tmp')
 temp.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
 os.replace(temp,p)
if receipt_path.exists():
 receipt=json.loads(receipt_path.read_text())
 assert receipt['status']=='MANAGED_XCI_REPAIR_COMPLETE'
 assert receipt['baseline_sha256']==sha(baseline_path)
 for r in receipt['archived']:
  assert sha(Path(r['archive']))==r['sha256']
 print('OTA004_A04_REPAIR_ALREADY_COMPLETE; preserve native-generated targets')
 sys.exit(0)
all_baseline=[baseline['xpr']]+baseline['managed_xci']
for r in baseline['managed_xci']:
 dest=(root/r['path']).resolve()
 assert dest.is_relative_to(root/'Sync_OTA.srcs/sources_1/ip') and dest.suffix=='.xci'
 source=(root/r['replacement']).resolve()
 assert source.is_relative_to(root/'ip/config_a04') and sha(source)==r['replacement_sha256']
# No compute reached A03 generate_target/synthesis; refuse touching any later DCP.
assert not any((root/'Sync_OTA.runs').rglob('*.dcp')), 'existing synthesized run must be preserved'
if state_path.exists():
 state=json.loads(state_path.read_text())
 assert state['baseline_sha256']==sha(baseline_path)
else:
 archive=attempt/'failed_a03_project_before_repair'
 archive.mkdir(exist_ok=False)
 archived=[]
 for r in all_baseline:
  p=root/r['path'];assert p.stat().st_size==r['bytes'] and sha(p)==r['sha256'],p
  dst=archive/r['path'];dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst)
  assert sha(dst)==r['sha256']
  archived.append(dict(path=r['path'],archive=str(dst),sha256=r['sha256']))
 state=dict(baseline_sha256=sha(baseline_path),archived=archived,started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
 save(state_path,state)
# Archive integrity is mandatory before replacing even one managed file.
for r in state['archived']:assert sha(Path(r['archive']))==r['sha256'],r
assert sha(root/baseline['xpr']['path'])==baseline['xpr']['sha256']
repaired=[]
for r in baseline['managed_xci']:
 dest=root/r['path'];source=root/r['replacement'];current=sha(dest)
 assert current in (r['sha256'],r['replacement_sha256']),('unexpected managed edit',dest)
 if current!=r['replacement_sha256']:
  temp=dest.with_name(dest.name+'.a04.tmp')
  temp.write_bytes(source.read_bytes());assert sha(temp)==r['replacement_sha256']
  os.replace(temp,dest)
 assert sha(dest)==r['replacement_sha256']
 repaired.append(dict(path=r['path'],before=r['sha256'],after=r['replacement_sha256']))
receipt=dict(**state,status='MANAGED_XCI_REPAIR_COMPLETE',repaired=repaired,completed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),project_not_recreated=True,no_succeeded_computation_repeated=True)
save(receipt_path,receipt)
save(attempt/'managed_xci_repair_receipt.json',receipt)
print('OTA004_A04_MANAGED_XCI_REPAIR_COMPLETE archived=46 repaired=45 project_preserved=1')
