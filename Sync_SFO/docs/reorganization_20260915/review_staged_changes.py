from pathlib import Path
import subprocess,json,hashlib,re
R=Path('D:/008_MA_Dev');A=R/'Sync_SFO/docs/reorganization_20260915';G='C:/Program Files/Git/cmd/git.exe'
def git(repo,*args,data=None):return subprocess.check_output([G,'-C',str(repo),*args],input=data)
# Scope byte-preservation to newly added project assets only; existing policies remain intact.
front=R/'Sync_Frontend';p=front/'.gitattributes';append=b'\n# Preserve bytes of new directory-entry assets.\nSync_Frontend.srcs/** -text\nSync_Frontend.xpr -text\nwrapper/sync_frontend_clip.vhd -text\n';p.write_bytes(p.read_bytes()+append)
git(front,'add','--','.gitattributes','Sync_Frontend.srcs','Sync_Frontend.xpr','wrapper/sync_frontend_clip.vhd')
i16=front/'examples/I16_AddSub_CLIP';p=i16/'.gitattributes';assert not p.exists();p.write_text('# Preserve the new root project entry bytes.\n/I16_AddSub.xpr -text\n',encoding='utf-8');git(i16,'add','--','.gitattributes','I16_AddSub.xpr')
# Root index must explicitly exclude the retained independent frontend repository.
p=R/'.gitignore';extra=b'\n# Independent module repository after reorganization.\n/Sync_Frontend/\n';p.write_bytes(p.read_bytes()+extra);old=git(R,'show',':.gitignore');oid=git(R,'hash-object','-w','--stdin',data=old+extra).decode().strip();git(R,'update-index','--cacheinfo','100644',oid,'.gitignore')
(A/'final_git_attribute_additions.json').write_text(json.dumps({'frontend_gitattributes_suffix':append.decode(),'i16_new_gitattributes':(i16/'.gitattributes').read_text(),'root_gitignore_suffix':extra.decode()},indent=2),encoding='utf-8')
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
