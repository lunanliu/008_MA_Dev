from pathlib import Path
import json,csv,hashlib,re
R=Path('D:/008_MA_Dev');A=R/'Sync_SFO/docs/reorganization_20260915'
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(4194304),b''):h.update(b)
 return h.hexdigest()
base={v['path']:v for v in json.loads((A/'files_before.json').read_text())};maps=json.loads((A/'path_mapping.json').read_text(encoding='utf-8-sig'));errors=[];archived=[]
for row in json.loads((A/'copy_verification.json').read_text())['files']:
 src=R/row['source'];mp=next(m for m in maps if src==Path(m['old']) or src.is_relative_to(Path(m['old'])));ap=Path(mp['archive'])/src.relative_to(Path(mp['old'])) if src!=Path(mp['old']) else Path(mp['archive']);h=sha(ap);archived.append({'old':row['source'],'archive':ap.relative_to(R).as_posix(),'sha256':h})
 if h!=base[row['source']]['sha256']:errors.append({'archive_changed':row['source']})
checks=json.loads((A/'static_entry_checks.json').read_text());native=[]
for i,p in enumerate(checks['projects'],1):
 expected={(fs['name'],Path(m['path']).as_posix().lower()) for fs in p['filesets'] for m in fs['members']};actual=list(csv.DictReader((A/f'native_files_{i}.tsv').open(),delimiter='\t'));aset={(r['fileset'],Path(r['path']).as_posix().lower()) for r in actual};missing=expected-aset;extras=[]
 if missing:errors.append({'project':p['xpr'],'missing_actual':sorted(missing)})
 for row in actual:
  path=Path(row['path']);key=(row['fileset'],path.as_posix().lower())
  if key in expected:continue
  assert i==1 and path.is_relative_to(R/'Sync_SFO/ip/config')
  rel=path.relative_to(R/'Sync_SFO').as_posix();reference=base.get(rel);exists=path.is_file();h=sha(path) if exists else None
  if not exists or not reference or h!=reference['sha256']:errors.append({'ip_support_mismatch':str(path),'exists':exists})
  extras.append({'fileset':row['fileset'],'path':path.as_posix(),'sha256':h,'baseline_path':rel})
 # Native read-only operation must not change XPR or explicit input bytes.
 if sha(Path(p['xpr']))!=p['sha256']:errors.append({'xpr_changed_during_open':p['xpr']})
 for fs in p['filesets']:
  for m in fs['members']:
   if sha(Path(m['path']))!=m['sha256']:errors.append({'input_changed_during_open':m['path']})
 native.append({'xpr':p['xpr'],'direct_members':len(expected),'actual_members':len(aset),'missing':len(missing),'existing_ip_support_members':extras})
# Frontend original project and its existing production files remain untouched.
frontchecked=0
for k,row in base.items():
 if k.startswith('Sync_Frontend/') and not k.startswith('Sync_Frontend/.git/') and k not in ('Sync_Frontend/README_ZH.md','Sync_Frontend/.gitignore'):
  if sha(R/k)!=row['sha256']:errors.append({'frontend_existing_changed':k})
  frontchecked+=1
result={'status':'PASS' if not errors else 'FAIL','errors':errors,'preserved_originals':len(archived),'frontend_existing_files_unchanged':frontchecked,'native_projects':native,'native_open_only':True,'new_compute_runs':0,'new_netlists_or_clip_xml':0,'bounds':'Exact file identity and read-only project manager dependency verification; not synthesis, simulation, timing, sustained throughput or board qualification.'}
(A/'archive_verification.json').write_text(json.dumps(archived,indent=2),encoding='utf-8');(A/'final_verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k!='native_projects'}));assert not errors
