from pathlib import Path
import json,hashlib,csv,xml.etree.ElementTree as ET,datetime,re
r=Path(r'D:\008_MA_Dev');o=r/'docs/verification/native_project';d=o/'astra_review';d.mkdir(exist_ok=True);a=r/'work/native_project_20260914T001342964Z_luna';ns='http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def rows(p):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
problems=[];native_exit=read(a/'owned_exit.json');assert native_exit['owned_active_after']==0 and native_exit['job_empty_utc'] and native_exit['root_exited']
immutable=read(o/'baseline/IMMUTABLE_INPUTS.json')['files'];changed=[x['path'] for x in immutable if h(r/x['path'])!=x['sha256']];problems+=changed
ips=read(o/'baseline/IP_BASELINE.json')['ips'];ipresults=[]
for b in ips:
 p=r/b['path'];tree=ET.parse(p);v={e.attrib['{'+ns+'}referenceId']:e.text or '' for e in tree.findall('.//{'+ns+'}configurableElementValue')};diff=[dict(key=k,before=b['values'].get(k),after=v.get(k)) for k in sorted(set(b['values'])|set(v)) if b['values'].get(k)!=v.get(k)];target_changes=[x for x in diff if x['key']=='MODELPARAM_VALUE.C_PART' and b['name'] in ['t03_xfft_16384_aux','t03_xfft_2048_main'] and x['before']=='xcvu11p-flgc2104-2-e' and x['after']=='xcvu11p-flgb2104-2-e'];ad=[x for x in diff if x['key'].startswith(('PARAM_VALUE.','MODELPARAM_VALUE.')) and x not in target_changes];ref=tree.find('.//{'+ns+'}componentRef');vlnv=':'.join(ref.attrib['{'+ns+'}'+k] for k in ['vendor','library','name','version']);assert not ad and vlnv==b['vlnv'];assert v['PROJECT_PARAM.PACKAGE']=='flgb2104' and v['PROJECT_PARAM.DEVICE']=='xcvu11p' and v['PROJECT_PARAM.SPEEDGRADE']=='-2' and v['PROJECT_PARAM.TEMPERATURE_GRADE'].upper()=='E'
 ipresults.append(dict(ip=b['name'],before_sha256=b['sha256'],after_sha256=h(p),changes=diff,algorithm_parameters_identical=True,target_model_metadata_changes=target_changes,IPDEF=vlnv))
configs={s:rows(a/f'config_{s}.csv') for s in ['before','after','reopened']};assert configs['before']==configs['after']==configs['reopened'];assert len(configs['after'])==1071;assert all(x['SourceMatches']=='1' for x in configs['after'])
assert rows(a/'ip_after.csv')==rows(a/'ip_reopened.csv');assert len(rows(a/'ip_after.csv'))==34
for x in rows(a/'ip_after.csv'):assert x['Package']=='flgb2104' and x['Locked']=='0'
for x in rows(a/'runs_reopened.csv'):assert x['Progress']=='0%' and x['Status']=='Not started'
xpr=r/'vivado/T10_SFO/T10_SFO.xpr';tree=ET.parse(xpr);fentries=[];outside=[];missing=[];absolute=[]
for e in tree.findall('.//FileSet/File'):
 path=e.attrib['Path'];resolved=Path(path.replace('$PPRDIR',xpr.parent.as_posix())).resolve();fentries.append(dict(reference=path,resolved=str(resolved)))
 if not resolved.is_relative_to(r):outside.append(path)
 if not resolved.is_file():missing.append(path)
 if '$PPRDIR' not in path:absolute.append(path)
inc=[]
for e in tree.findall('.//Option'):
 if ('include' in e.attrib.get('Name','').lower() or e.attrib.get('Name')=='VerilogDir') and e.attrib.get('Val'):
  inc.append(dict(name=e.attrib['Name'],value=e.attrib['Val']))
activepart=[e.attrib['Val'] for e in tree.findall('.//Option') if e.attrib.get('Name')=='Part'];assert activepart==['xcvu11p-flgb2104-2-e'];assert not outside and not missing and not absolute
includes=[x for x in inc if x['name']=='VerilogDir'];assert len(includes)==2
for x in includes:
 resolved=Path(x['value'].replace('$PPRDIR',xpr.parent.as_posix())).resolve()
 assert x['value'].startswith('$PPRDIR/') and resolved==(r/'rtl/include').resolve() and resolved.is_dir()
 x['resolved']=str(resolved)
allxci=list((r/'ip/config').rglob('*.xci'));assert len(allxci)==34
expected_xci={(r/b['path']).resolve() for b in ips}
active_xci={Path(x['resolved']) for x in fentries if x['reference'].lower().endswith('.xci')}
assert {p.resolve() for p in allxci}==expected_xci==active_xci
inactive_xci=[p.relative_to(r).as_posix() for p in r.rglob('*.xci') if not p.is_relative_to(r/'ip/config')]
assert inactive_xci==['matlab/source_snapshots/T09_FIXED007/evidence/main_fft.xci']
ext={}
for p in (r/'ip/config').rglob('*'):
 if p.is_file():ext[p.suffix]=ext.get(p.suffix,0)+1
assert ext=={'.veo':34,'.vho':34,'.xci':34,'.xml':34} or dict(sorted(ext.items()))==dict(sorted({'.veo':34,'.vho':34,'.xci':34,'.xml':34}.items()))
log=(a/'vivado.log').read_text(encoding='utf-8',errors='replace');assert log.count('NATIVE_RETARGET_END ')==34;assert 'CONFIG_SOURCE_DIFFERENCES_reopened=0' in log and 'invalid command name "}"' in log
out=dict(status='CORE_PROJECT_IDENTITY_VERIFIED_PUBLICATION_REPAIR_PENDING',utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),native_exit=native_exit,native_exit_sha256=h(a/'owned_exit.json'),native_log_sha256=h(a/'vivado.log'),core_sources=74,unchanged_immutable_inputs=len(immutable),CONFIG_values_compared=1071,CONFIG_before_after_reopen_identical=True,ips=ipresults,xpr_sha256=h(xpr),project_part=activepart[0],project_native_reopen_completed=True,project_closed_after_reopen=True,GUI_interaction_test=False,relative_source_references=len(fentries),source_references=fentries,include_options=inc,external_design_dependencies=outside,missing_design_dependencies=missing,absolute_active_source_references=absolute,xpr_root_Path_attribute=tree.getroot().attrib.get('Path'),portability_scope='All active source and include references relative to project; root Path is saved creation-location metadata. Relocated native open not separately tested.',canonical_xci_count=len(allxci),inactive_history_xci=inactive_xci,native_generated_files_by_extension=ext,full_ip_HDL_MIF_DCP_outputs_generated=False,automatic_instantiation_templates_generated=True,simulation=False,synthesis=False,implementation=False,problems=problems)
(d/'IDENTITY_REVIEW_DRAFT.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
c=read(o/'REPORT_CLOCK.json');c.update(work_state='WORKING',started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),next_due_utc=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=15)).isoformat(),scope='Astra independent saved native result review; no new native');(o/'REPORT_CLOCK.json').write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(ips=34,CONFIG=1071,immutable=len(immutable),relative_source_refs=len(fentries),includes=includes,extensions=ext,problems=problems)))
