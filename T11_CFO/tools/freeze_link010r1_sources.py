"""Freeze a reviewed LINK010R1 package once; no native tool execution."""
from pathlib import Path
import ast,json,hashlib,datetime
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def item(p):return {'path':p,'bytes':(R/p).stat().st_size,'sha256':sha(R/p)}
def main():
 oldpath=R/'docs/LINK010_SOURCE_LOCK.json'
 assert sha(oldpath)=='C9975BEE22B81FDE0AE670DB4644C3DDE0206C111307A904AA08A5E77D80BCA5'
 old=json.loads(oldpath.read_text('utf-8'))
 for x in old['files']+old['vendor_dependencies']:
  p=R/x['path'];assert p.stat().st_size==x['bytes'] and sha(p)==x['sha256'],p
 rename={'rtl/cfo_estimator_link.sv':'rtl/cfo_estimator_link_v2.sv','sim/tb/cfo_estimator_link_tb.sv':'sim/tb/cfo_estimator_link_r1_tb.sv'}
 members=[{'fileset':x['fileset'],'path':rename.get(x['path'],x['path'])} for x in old['project_members']]
 members += [{'fileset':'sources_1','path':x['path']} for x in old['vendor_dependencies']]
 members += [{'fileset':'sim_1','path':f'sim/vendor/link010r1/{n}.sv'} for n in ['xpm_cdc','xpm_memory','xpm_fifo']]
 paths=[x['path'] for x in old['files']]+[x['path'] for x in members if not Path(x['path']).is_absolute()]
 paths += ['docs/LINK010_SOURCE_LOCK.json','docs/LINK010R1_CONTRACT_ZH.md','docs/LINK010R1_NATIVE_JOB.md','tools/verify_link010r1.py','tools/verify_link010r1_models.py','tools/verify_link010r1_reset.py','tools/verify_link010r1_binding.py','tools/freeze_link010r1_sources.py','vivado/link010r1_project.tcl','sim/vendor/link010r1/xpm_fifo_assertions.diff','reports/LINK010R1_RESET_FIX_DRAFT_REVIEW.json','reports/LINK010R1_TB_STATIC_REVIEW.json','reports/LINK010R1_MODEL_BINDING_STATIC_REVIEW.json','reports/LINK010R1_BINDING_HELPER_REVIEW.json','reports/LINK010R1_STATIC_REVIEW.json','reports/LINK010R1_PRE_FREEZE_CHECK.json']
 paths=list(dict.fromkeys(paths));assert len(members)==25
 for p in paths:
  assert (R/p).is_file(),p
  if p.endswith('.py'):ast.parse((R/p).read_text('utf-8'),filename=p)
 review=json.loads((R/'reports/LINK010R1_STATIC_REVIEW.json').read_text('utf-8'))
 assert review['status']=='STATIC_REVIEW_PASS_PENDING_NATIVE' and review['native_started']==False
 lock={'schema':'link010r1_source_lock_v1','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(R),'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_estimator_link','simulation_top':'cfo_estimator_link_tb','project_members':members,'files':[item(p) for p in paths],'vendor_dependencies':[item(x['path']) for x in old['vendor_dependencies']],'native_stages':['create','simulate'],'scope':'LINK010 reset-contract correction, same numerical/protocol vectors plus passive reset-edge audit; no whole CFO chain or synthesis/physical qualification.'}
 p=R/'docs/LINK010R1_SOURCE_LOCK.json';assert not p.exists();p.write_text(json.dumps(lock,indent=2)+'\n',encoding='utf-8',newline='\n')
 guard=R/'tools/cfo_link010r1_guard_v1.py';s=guard.read_text('utf-8');assert s.count('LOCK_SHA_TO_FREEZE')==1;s=s.replace('LOCK_SHA_TO_FREEZE',sha(p));ast.parse(s);guard.write_text(s,encoding='utf-8',newline='\n')
 print(json.dumps({'source_lock_sha256':sha(p),'files':len(paths),'vendor_dependencies':3,'project_members':25,'controller_sha256':sha(guard),'native_started':False}))
if __name__=='__main__':main()
