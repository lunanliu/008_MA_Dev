"""One-time FRONT009 source freeze; do not rerun after dispatch."""
from pathlib import Path
import json,hashlib,datetime,ast
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 members=[('sources_1','rtl/'+p) for p in ['cfo_front2048_window.sv','cfo_fft2048_core.sv']]+[('sources_1','ip/'+p) for p in ['fft2048_twiddle.mem','front2048_coefficient_index.mem','front2048_coefficient_table.mem']]+[('constrs_1','constraints/cfo_front2048.xdc'),('sim_1','sim/tb/cfo_front2048_tb.sv'),('sim_1','sim/vectors/front2048_config.svh')]+[('sim_1','sim/vectors/front2048_'+p+'.mem') for p in ['input','pilot','result','metadata']]+[('utils_1','vivado/run_threads.tcl')]
 paths=[p for _,p in members]+['tools/front2048_reference.py','tools/verify_front2048.py','tools/freeze_front009_sources.py','tools/fft2048_reference.py','tools/cfo_native_guard_v3.py','tools/cfo_phase74_guard_v1.py','tools/cfo_phase74_fix01_guard_v1.py','vivado/front2048_project.tcl','vivado/configure_parallel_jobs.tcl','docs/FRONT2048_CONTRACT_V1_ZH.md','docs/FRONT2048_NATIVE_JOB_009.md','docs/CFO_MAIN_CONTRACT.json','docs/FFT008_SOURCE_LOCK.json','sim/vectors/front2048_cases.json','matlab/bittrue/cfo_chain_arithmetic.m','reports/FRONT2048_VECTOR_CHECK.json','reports/FFT008_REVIEW_20260914/INDEPENDENT_REVIEW.json','reports/FFT008_REVIEW_20260914/README_ZH.md']
 assert len(paths)==len(set(paths)) and len(members)==13
 for p in paths:
  if p.endswith('.py'):ast.parse((R/p).read_text(),filename=p)
 old=json.loads((R/'docs/FFT008_SOURCE_LOCK.json').read_text())
 for x in old['files']:assert sha(R/x['path'])==x['sha256'],x['path']
 lock={'schema':'front009_source_lock_v1','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(R),'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_front2048_window','simulation_top':'cfo_front2048_tb','project_members':[{'fileset':f,'path':p} for f,p in members],'files':[{'path':p,'bytes':(R/p).stat().st_size,'sha256':sha(R/p)} for p in paths],'native_stages':['create','simulate'],'scope':'Integrated window FFT2048, exact coefficient lookup, pilot multiply and z sum; 74-row coverage. No whole-frame waveform, CDC, backend integration, synthesis or clock500 physical qualification.'}
 p=R/'docs/FRONT009_SOURCE_LOCK.json';assert not p.exists();p.write_text(json.dumps(lock,indent=2)+'\n',encoding='utf-8')
 gp=R/'tools/cfo_front2048_guard_v1.py';s=gp.read_text();assert s.count('LOCK_SHA_TO_FREEZE')==1;s=s.replace('LOCK_SHA_TO_FREEZE',sha(p));ast.parse(s);gp.write_text(s,encoding='utf-8')
 print(json.dumps({'lock_sha256':sha(p),'files':len(paths),'members':len(members),'controller_sha256':sha(gp)}))
if __name__=='__main__':main()