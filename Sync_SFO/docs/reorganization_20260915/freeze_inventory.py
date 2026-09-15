import os, sys, json, hashlib, subprocess, time, xml.etree.ElementTree as ET
from pathlib import Path
R=Path('D:/008_MA_Dev'); A=R/'Sync_SFO/docs/reorganization_20260915'
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(4*1024*1024),b''): h.update(b)
    return h.hexdigest()
def git(repo,*args):
    return subprocess.check_output(['C:/Program Files/Git/cmd/git.exe','-C',str(repo),*args])
repos={'root':R,'frontend':R/'Sync_Frontend','i16':R/'I16_AddSub_CLIP'}
repo_info={}
for name,repo in repos.items():
    repo_info[name]={'path':str(repo),'head':git(repo,'rev-parse','HEAD').decode().strip(),'status':git(repo,'status','--porcelain=v1','-uall').decode(),'remotes':git(repo,'remote','-v').decode()}
    for suffix,args in [('working.patch',('diff','--binary')),('staged.patch',('diff','--cached','--binary')),('index_entries.txt',('ls-files','--stage')),('tracked.txt',('ls-files',)),('status.txt',('status','--porcelain=v1','-uall'))]:
        (A/(name+'.'+suffix)).write_bytes(git(repo,*args))
(A/'git_before.json').write_text(json.dumps(repo_info,indent=2),encoding='utf-8')
files=[]
for base,dirs,names in os.walk(R):
    p=Path(base)
    if p==R: dirs[:]=[d for d in dirs if d not in ('.git','Sync_SFO')]
    for name in names:
        f=p/name
        if f.is_symlink(): raise RuntimeError('Unreviewed link: '+str(f))
        stat=f.stat()
        files.append({'path':f.relative_to(R).as_posix(),'bytes':stat.st_size,'sha256':digest(f),'mtime_ns':stat.st_mtime_ns})
(A/'files_before.json').write_text(json.dumps(files,ensure_ascii=False,indent=2),encoding='utf-8')
xprs=[]
for row in files:
    if row['path'].endswith('.xpr'):
        f=R/row['path']; x=ET.parse(f).getroot()
        xprs.append({'path':row['path'],'sha256':row['sha256'],'part':[o.get('Val') for o in x.findall('./Configuration/Option') if o.get('Name')=='Part'],'sets':[{'name':s.get('Name'),'options':[(o.get('Name'),o.get('Val')) for o in s.findall('./Config/Option')],'files':[o.get('Path') for o in s.findall('./File')]} for s in x.findall('./FileSets/FileSet')]})
(A/'xpr_before.json').write_text(json.dumps(xprs,indent=2),encoding='utf-8')
print(json.dumps({'files':len(files),'bytes':sum(r['bytes'] for r in files),'projects':len(xprs),'git':{k:v['head'] for k,v in repo_info.items()}}))
