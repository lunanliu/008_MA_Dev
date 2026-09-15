from pathlib import Path
import subprocess,json
R=Path('D:/008_MA_Dev');A=R/'Sync_SFO/docs/reorganization_20260915';G='C:/Program Files/Git/cmd/git.exe'
def git(repo,*args,data=None):return subprocess.check_output([G,'-C',str(repo),*args],input=data)
info=json.loads((A/'git_before.json').read_text())
assert git(R,'rev-parse','HEAD').decode().strip()==info['root']['head']
assert git(R,'ls-files','--stage')==(A/'root.index_entries.txt').read_bytes(), 'Index changed externally; stop'
assert not git(R,'diff','--cached','--name-only').strip()
entries=git(R,'ls-files','--stage','-z').split(b'\0');changes=[];payload=[]
roots={'constraints','docs','handoff','ip','matlab','rtl','sim','tools','vivado','work'}
for record in entries:
 if not record:continue
 meta,path=record.split(b'\t',1);mode,oid,stage=meta.split();assert stage==b'0';name=path.decode();first=name.split('/')[0]
 new='Sync_CFO/'+name[len('T11_CFO/'):] if name.startswith('T11_CFO/') else 'Sync_SFO/'+name if first in roots else name
 if new==name:continue
 assert (R/new).is_file(),new
 payload.append(b'0 '+b'0'*40+b'\t'+path+b'\0');payload.append(mode+b' '+oid+b'\t'+new.encode()+b'\0');changes.append({'old':name,'new':new,'index_blob':oid.decode()})
git(R,'update-index','-z','--index-info',data=b''.join(payload))
# Stage only our additive root housekeeping edits against the pre-existing index content.
adds=json.loads((A/'additive_navigation_edits.json').read_text())
for edit in adds:
 name=edit['path']
 if name.startswith('Sync_Frontend/'):continue
 old=git(R,'show',':'+name);addition=edit['added_utf8'].encode();staged=addition+old if edit['position']=='prefix' else old+addition
 oid=git(R,'hash-object','-w','--stdin',data=staged).decode().strip();git(R,'update-index','--cacheinfo','100644',oid,name)
# Exact reviewed new/changed paths, no blanket add of pre-existing untracked content.
paths=['PATH_MAPPING_ZH.md','Sync_SFO/README_ZH.md','Sync_SFO/Sync_SFO.xpr','Sync_SFO/tools/vivado/open_sync_sfo.tcl','Sync_SFO/docs/SFO_SYNC_MODULE_GUI_ZH.md','Sync_SFO/docs/provenance/RUN03_APPROVED_INPUTS.csv','Sync_CFO/README_ZH.md','Sync_CFO/docs/DIRECTORY_ENTRY_20260915_ZH.md','Sync_CFO/docs/DELIVERY_BOUNDARY_20260915_ZH.md','Sync_CFO/docs/CFO_STAGE_ENTRY_DATA_20260915_ZH.md','Sync_CFO/wrapper/README_ZH.md']
paths += [p.relative_to(R).as_posix() for p in (R/'Sync_SFO/wrapper').iterdir() if p.is_file()]
paths += [p.relative_to(R).as_posix() for p in (R/'Sync_CFO/rtl/vendor/vivado_2021_1_xpm').iterdir() if p.is_file()]
paths += [p.relative_to(R).as_posix() for p in sorted((R/'Sync_CFO/vivado').glob('*/*.xpr'))]
evidence=['copy_plan.json','copy_verification.json','files_before.json','git_before.json','xpr_before.json','additional_copy_plan.json','xpr_path_changes.json','static_entry_checks.json','path_mapping.json','switch_checkpoint.json','native_open_job.json','native_open_summary.tsv','final_verification.json','archive_verification.json','additive_navigation_edits.json','REORGANIZATION_RESULT_ZH.md','GIT_REORGANIZATION_ZH.md']
paths += [(A/name).relative_to(R).as_posix() for name in evidence]
paths += [p.relative_to(R).as_posix() for pat in ('native_files_*.tsv','*.py','*.tcl') for p in A.glob(pat)]
git(R,'add','--',*paths)
git(R,'add','-f','--',(A/'native_open.log').relative_to(R).as_posix(),(A/'native_open.jou').relative_to(R).as_posix())
# Frontend and I16 keep their independent histories and pre-existing dirt.
front=R/'Sync_Frontend';assert git(front,'rev-parse','HEAD').decode().strip()==info['frontend']['head'];assert not git(front,'diff','--cached','--name-only').strip()
fpaths=['.gitignore','README_ZH.md','Sync_Frontend.xpr','docs/DIRECTORY_ENTRY_20260915_ZH.md','tools/open_sync_frontend.tcl','wrapper/sync_frontend_clip.vhd','examples/README_ZH.md','examples/I16_AddSub_CLIP_Source_Project.zip']
fpaths += [p.relative_to(front).as_posix() for p in (front/'Sync_Frontend.srcs').rglob('*.xci')];git(front,'add','--',*fpaths)
i16=front/'examples/I16_AddSub_CLIP';assert git(i16,'rev-parse','HEAD').decode().strip()==info['i16']['head'];assert not git(i16,'diff','--cached','--name-only').strip();git(i16,'add','--','I16_AddSub.xpr','DIRECTORY_ENTRY_20260915_ZH.md')
(A/'git_staging_plan.json').write_text(json.dumps({'tracked_path_moves':changes,'root_explicit_paths':paths,'frontend_explicit_paths':fpaths,'i16_explicit_paths':['I16_AddSub.xpr','DIRECTORY_ENTRY_20260915_ZH.md'],'baseline_user_modifications_not_staged':True},indent=2),encoding='utf-8')
git(R,'add','--',(A/'git_staging_plan.json').relative_to(R).as_posix())
for name,repo in [('root',R),('frontend',front),('i16',i16)]:
 (A/(name+'.staged_review.txt')).write_bytes(git(repo,'diff','--cached','--stat'))
 (A/(name+'.unstaged_after_staging.patch')).write_bytes(git(repo,'diff','--binary'))
 print(name,'staged_paths',len(git(repo,'diff','--cached','--name-only').splitlines()),'unstaged_paths',git(repo,'diff','--name-only').decode().strip().splitlines())
print('INDEX_RELOCATIONS',len(changes),'READY_FOR_REVIEW_NOT_COMMITTED')
