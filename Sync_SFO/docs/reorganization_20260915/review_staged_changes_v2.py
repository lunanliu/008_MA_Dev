from pathlib import Path
import subprocess,json,hashlib,re
R=Path('D:/008_MA_Dev');A=R/'Sync_SFO/docs/reorganization_20260915';G='C:/Program Files/Git/cmd/git.exe'
def git(repo,*args,data=None):return subprocess.check_output([G,'-C',str(repo),*args],input=data)
front=R/'Sync_Frontend';i16=front/'examples/I16_AddSub_CLIP'
# Verify no changed algorithm blob was slipped into a tracked path move.
plan=json.loads((A/'git_staging_plan.json').read_text());index={}
for record in git(R,'ls-files','--stage','-z').split(b'\0'):
 if record:
  meta,name=record.split(b'\t',1);index[name.decode()]=meta.split()[1].decode()
changed_moves=[]
for m in plan['tracked_path_moves']:
 if index[m['new']]!=m['index_blob']:changed_moves.append(m['new'])
allowed={'Sync_CFO/README_ZH.md','Sync_CFO/docs/CFO_STAGE_ENTRY_DATA_20260915_ZH.md','Sync_CFO/docs/DELIVERY_BOUNDARY_20260915_ZH.md'}
allowed.update(p.relative_to(R).as_posix() for p in (R/'Sync_CFO/vivado').glob('*/*.xpr'))
assert set(changed_moves)<=allowed,changed_moves
# Newly versioned hardware assets must store precisely the verified on-disk bytes.
assets=[]
for repo in (R,front,i16):
 for name in git(repo,'diff','--cached','--diff-filter=A','--name-only').decode().splitlines():
  if Path(name).suffix.lower() in ('.sv','.vhd','.v','.xci','.xpr'):
   assert git(repo,'show',':'+name)==(repo/name).read_bytes(),name
   assets.append(str(repo/name))
# Newly written navigation links only. Preserved historical text is intentionally not rewritten.
files=[R/'PATH_MAPPING_ZH.md',R/'Sync_SFO/README_ZH.md',R/'Sync_CFO/docs/DIRECTORY_ENTRY_20260915_ZH.md',R/'Sync_CFO/wrapper/README_ZH.md',front/'docs/DIRECTORY_ENTRY_20260915_ZH.md',front/'examples/README_ZH.md',i16/'DIRECTORY_ENTRY_20260915_ZH.md',A/'REORGANIZATION_RESULT_ZH.md']
missing=[];links=0
for f in files:
 for href in re.findall(r'\]\(([^)]+)\)',f.read_text(encoding='utf-8')):
  if '://' in href or href.startswith('#'):continue
  links+=1
  if not (f.parent/href.split('#')[0]).resolve().exists():missing.append({'file':str(f),'link':href})
assert not missing,missing
review={'status':'PASS','path_moves':len(plan['tracked_path_moves']),'changed_move_contents':changed_moves,'all_other_moved_index_blobs_unchanged':True,'new_hardware_assets_staged_with_exact_bytes':len(assets),'new_navigation_links_checked':links,'missing_new_links':missing,'user_dirty_root_paths':git(R,'diff','--name-only').decode().splitlines(),'user_dirty_i16_paths':git(i16,'diff','--name-only').decode().splitlines()}
(A/'precommit_review.json').write_text(json.dumps(review,indent=2),encoding='utf-8')
# Add only these new audit records.
git(R,'add','--',(A/'final_git_attribute_additions.json').relative_to(R).as_posix(),(A/'precommit_review.json').relative_to(R).as_posix())
print(json.dumps(review))
