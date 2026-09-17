"""Read-only input verification; receipt output only in a new diagnostic attempt."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
LOCK=ROOT/'docs/jobs/OTA004_A06R2I1_source_lock.json'
def main():
 if len(sys.argv) not in (2,3) or (len(sys.argv)==3 and sys.argv[2]!='--post'):
  raise SystemExit('usage: checker <identity-attempt> [--post]')
 out=Path(sys.argv[1]).resolve()
 import re
 if out.parent!=ROOT/'work/OTA004' or not re.fullmatch(r'identity_a06r2i1(?:_[A-Za-z0-9-]+)?',out.name) or not out.is_dir():
  raise SystemExit('invalid identity-only attempt')
 lock=json.loads(LOCK.read_text(encoding='utf-8-sig'))
 for row in lock['files']+lock['tools']:
  p=Path(row['path']);p=p if p.is_absolute() else ROOT/p
  with p.open('rb') as f:actual=hashlib.file_digest(f,'sha256').hexdigest()
  if actual!=row['sha256'].lower():raise SystemExit('input mismatch: '+str(p))
 import datetime
 record={'status':'A06R2I1_INPUTS_UNCHANGED','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':len(lock['files']),'tools':len(lock['tools']),'lock_sha256':hashlib.sha256(LOCK.read_bytes()).hexdigest(),'native_acceptance':'NONE'}
 name='identity_postcheck.json' if len(sys.argv)==3 else 'identity_precheck.json'
 with (out/name).open('x',encoding='utf-8') as f:json.dump(record,f,ensure_ascii=False,indent=2);f.write('\n')
 print(json.dumps(record,ensure_ascii=False))
if __name__=='__main__':main()
