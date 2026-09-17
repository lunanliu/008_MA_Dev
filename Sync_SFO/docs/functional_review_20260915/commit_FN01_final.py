from pathlib import Path
import subprocess, json, hashlib
M=Path('D:/008_MA_Dev/Sync_SFO'); R=M/'reports/functional_review/FN01'; A=M/'docs/functional_review_20260915'; G='C:/Program Files/Git/cmd/git.exe'
def git(*a): return subprocess.run([G,'-C',str(M),*a],check=True,capture_output=True).stdout
assert not git('diff','--cached','--name-only').strip(), 'Pre-existing staged files; leave index unchanged.'
manifest=json.loads((R/'FINAL_EVIDENCE_MANIFEST.json').read_text(encoding='utf-8'))
for e in manifest['files']:
 p=M/e['path']; assert len(p.read_bytes())==e['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest().upper()==e['sha256'], e['path']
selected=sorted(p for p in R.rglob('*') if p.is_file())+[M/'README_ZH.md',M/'docs/SFO_SYNC_MODULE_GUI_ZH.md',A/'REVIEW_STATUS_ZH.md',M/'wrapper/interface_contract_FN01.json']
relative=[p.relative_to(M).as_posix() for p in selected]
git('add','-f','--',*relative)
repo=M.parent
staged=git('diff','--cached','--name-only','--no-renames','-z').decode().strip('\x00').split('\x00')
expected={p.relative_to(repo).as_posix() for p in selected}
assert set(staged)==expected, {'unexpected':list(set(staged)-expected),'missing':list(expected-set(staged))}
for p in selected:
 r=p.relative_to(repo).as_posix(); assert git('show',':'+r)==p.read_bytes(), 'Index bytes changed: '+r
print(git('diff','--cached','--stat').decode())
print(git('commit','-m','docs(sfo): accept FN01 compile and wrapper checks').decode())
print('COMMIT',git('rev-parse','HEAD').decode().strip())
print('POST_STAGED',git('diff','--cached','--name-only').decode().strip())
print('TRACKED_STATUS',git('status','--short','--untracked-files=no','--','.').decode().strip())
