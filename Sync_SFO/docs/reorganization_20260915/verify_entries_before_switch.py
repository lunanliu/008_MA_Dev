from pathlib import Path
import os,re,json,hashlib,xml.etree.ElementTree as E
R=Path('D:/008_MA_Dev');A=R/'Sync_SFO/docs/reorganization_20260915'
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(4194304),b''):h.update(b)
 return h.hexdigest()
def resolve(p,v):
 for a,b in {'$PPRDIR':p.parent.as_posix(),'$PSRCDIR':(p.parent/(p.stem+'.srcs')).as_posix(),'$PGENDIR':(p.parent/(p.stem+'.gen')).as_posix(),'$PRUNDIR':(p.parent/(p.stem+'.runs')).as_posix(),'$PCACHEDIR':(p.parent/(p.stem+'.cache')).as_posix()}.items():v=v.replace(a,b)
 if '$' in v:raise RuntimeError('Unknown path macro '+v)
 return Path(v).resolve()
changes=json.loads((A/'xpr_path_changes.json').read_text());projects=[];errors=[]
for change in changes:
 p=Path(change['target']);x=E.parse(p).getroot();fs=[];module=R/'Sync_CFO' if p.is_relative_to(R/'Sync_CFO') else R/'Sync_SFO' if p.is_relative_to(R/'Sync_SFO') else R/'Sync_Frontend'
 for s in x.findall('./FileSets/FileSet'):
  members=[]
  for f in s.findall('File'):
   path=resolve(p,f.get('Path'));exists=path.is_file()
   if not exists:errors.append({'project':str(p),'missing':str(path)})
   if not path.is_relative_to(module):errors.append({'project':str(p),'outside_module':str(path)})
   members.append({'xpr_path':f.get('Path'),'path':path.as_posix(),'exists':exists,'sha256':sha(path) if exists else None})
  fs.append({'name':s.get('Name'),'members':members,'options':[e.attrib for e in s.findall('./Config/Option')]})
 hooks=sorted({s.get('PreStepTclHook') for s in x.findall('.//Step') if s.get('PreStepTclHook')})
 for hook in hooks:
  if not resolve(p,hook).is_file():errors.append({'hook_missing':hook,'xpr':str(p)})
 project={'xpr':p.as_posix(),'sha256':sha(p),'part':x.find('./Configuration/Option[@Name="Part"]').get('Val'),'filesets':fs,'hooks':hooks}
 assert project['part']=='xcvu11p-flgb2104-2-e';projects.append(project)
# The new SFO exact source set must match the approved handoff project.
sfo=projects[0];old=R/'Sync_SFO/handoff/T10_SFO_20260915_manual/core_project/vivado/T10_SFO/T10_SFO.xpr';x=E.parse(old).getroot();pairs=[]
for s in x.findall('./FileSets/FileSet'):
 newset=next(v for v in sfo['filesets'] if v['name']==s.get('Name'))
 assert len(s.findall('File'))==len(newset['members'])
 for f,new in zip(s.findall('File'),newset['members']):
  op=resolve(old,f.get('Path'));assert sha(op)==new['sha256'];pairs.append({'source':op.as_posix(),'target':new['path'],'sha256':new['sha256']})
core_paths=(R/'Sync_SFO/rtl/sources.f').read_text().splitlines();core_paths=[v.strip() for v in core_paths if v.strip()]
assert len(core_paths)==74 and len(set(core_paths))==74
for rel in core_paths:assert any(m['path']==(R/'Sync_SFO'/rel).as_posix() for s in sfo['filesets'] for m in s['members'])
ips={m['path'] for s in sfo['filesets'] for m in s['members'] if m['path'].endswith('.xci')};assert len(ips)==34
# Source and destination pairing is positional within frozen filesets, never by mtime/name.
for pr in projects[1:]:
 p=Path(pr['xpr'])
 if p.is_relative_to(R/'Sync_CFO'):op=R/'T11_CFO'/p.relative_to(R/'Sync_CFO')
 elif p.name=='I16_AddSub.xpr':op=R/'I16_AddSub_CLIP/vivado/I16_AddSub/I16_AddSub.xpr'
 else:op=R/'Sync_Frontend/vivado/Sync_Frontend/Sync_Frontend.xpr'
 ox=E.parse(op).getroot()
 for ns,oset in zip(pr['filesets'],ox.findall('./FileSets/FileSet')):
  assert ns['name']==oset.get('Name') and len(ns['members'])==len(oset.findall('File'))
  for nm,om in zip(ns['members'],oset.findall('File')):
   oldpath=resolve(op,om.get('Path'));assert sha(oldpath)==nm['sha256'],str(oldpath)
# Verify all original items to be switched remain as frozen. Root management files and GUI module are not switched.
copycheck=json.loads((A/'copy_verification.json').read_text());baseline={x['path']:x for x in json.loads((A/'files_before.json').read_text())}
for row in copycheck['files']:
 p=R/row['source']
 if sha(p)!=baseline[row['source']]['sha256']:errors.append({'changed_before_switch':row['source']})
result={'status':'PASS' if not errors else 'FAIL','errors':errors,'project_count':len(projects),'sfo_core_rtl':74,'sfo_ip_configs':34,'sfo_file_references_compared':len(pairs),'original_files_unchanged_before_switch':len(copycheck['files']),'projects':projects,'sfo_pairs':pairs,'boundary':'Static path/source identity only. No algorithm, simulation, synthesis, timing or throughput validation.'}
(A/'static_entry_checks.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k not in ('projects','sfo_pairs')}));assert not errors
