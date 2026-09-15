"""Freeze LINK010 only once after independent review; never run after dispatch."""
from pathlib import Path
import json,hashlib,ast,datetime
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def item(p):return {'path':p,'bytes':(R/p).stat().st_size,'sha256':sha(R/p)}
def main():
 members=[('sources_1','rtl/'+p) for p in ['cfo_estimator_link.sv','cfo_estimate74_backend.sv','cfo_fft74_quality_v2.sv','cfo_divide_rne64wide.sv','cfo_fft256_core.sv','cfo_phase74_core_v2.sv','cfo_divide_rne64.sv']]+[('sources_1','ip/'+p) for p in ['fft256_twiddle.mem','phase74_atan_q31.mem']]+[('constrs_1','constraints/cfo_link010.xdc'),('sim_1','sim/tb/cfo_estimator_link_tb.sv'),('sim_1','sim/vectors/link010_config.svh')]+[('sim_1','sim/vectors/link010_'+p+'.mem') for p in ['input','read','result','error_input','error_read','error_result']]+[('utils_1','vivado/run_threads.tcl')]
 paths=[p for _,p in members]+['tools/link010_vectors.py','tools/verify_link010.py','tools/freeze_link010_sources.py','tools/link010_admission.py','tools/backend74_reference.py','tools/cfo_native_guard_v3.py','tools/cfo_phase74_guard_v1.py','vivado/link010_project.tcl','vivado/configure_parallel_jobs.tcl','docs/LINK010_CONTRACT_V1_ZH.md','docs/LINK010_NATIVE_JOB_010.md','docs/CFO_MAIN_CONTRACT.json','docs/BACKEND006R1_SOURCE_LOCK.json','docs/FRONT009_SOURCE_LOCK.json','sim/vectors/link010_cases.json','sim/vectors/backend74_cases.json','reports/LINK010_VECTOR_CHECK.json','reports/LINK010_STATIC_REVIEW_20260915.json','reports/FRONT009_REVIEW_20260914/INDEPENDENT_REVIEW.json','reports/BACKEND006R1_REVIEW_20260914/INDEPENDENT_REVIEW.json']
 assert len(paths)==len(set(paths)) and len(members)==19
 for p in paths:
  if p.endswith('.py'):ast.parse((R/p).read_text(),filename=p)
 for name in ['BACKEND006R1_SOURCE_LOCK.json','FRONT009_SOURCE_LOCK.json']:
  old=json.loads((R/'docs'/name).read_text())
  for x in old['files']:assert sha(R/x['path'])==x['sha256'],x['path']
 vendor=[f'C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/{n}/hdl/{n}.sv' for n in ['xpm_cdc','xpm_fifo','xpm_memory']]
 lock={'schema':'link010_source_lock_v1','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(R),'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_estimator_link','simulation_top':'cfo_estimator_link_tb','project_members':[{'fileset':f,'path':p} for f,p in members],'files':[item(p) for p in paths],'vendor_dependencies':[item(p) for p in vendor],'native_stages':['create','simulate'],'scope':'Atomic 171-bit z messages cross XPM FIFO, frame/protocol adapter and frozen74 backend; no full waveform, synthesis, timing or physical CDC qualification.'}
 p=R/'docs/LINK010_SOURCE_LOCK.json';assert not p.exists();p.write_text(json.dumps(lock,indent=2)+'\n')
 gp=R/'tools/cfo_link010_guard_v1.py';s=gp.read_text();assert s.count('LOCK_SHA_TO_FREEZE')==1;s=s.replace('LOCK_SHA_TO_FREEZE',sha(p));ast.parse(s);gp.write_text(s)
 print(json.dumps({'source_lock_sha256':sha(p),'files':len(paths),'members':len(members),'vendor_dependencies':len(vendor),'controller_sha256':sha(gp)}))
if __name__=='__main__':main()