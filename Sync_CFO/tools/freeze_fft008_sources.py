"""One-time freeze; never rerun after dispatch."""
from pathlib import Path
import json,hashlib,datetime,ast
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 members=[('sources_1','rtl/cfo_fft2048_core.sv'),('sources_1','ip/fft2048_twiddle.mem'),('constrs_1','constraints/cfo_fft2048.xdc'),('sim_1','sim/tb/cfo_fft2048_tb.sv'),('sim_1','sim/vectors/fft2048_config.svh')]+[('sim_1','sim/vectors/fft2048_'+s+'.mem') for s in ['input','output','butterfly','saturation','window']]+[('utils_1','vivado/run_threads.tcl')]
 paths=[p for _,p in members]+['tools/fft2048_reference.py','tools/verify_fft2048.py','tools/freeze_fft008_sources.py','tools/review_frontdata007.py','tools/cfo_native_guard_v3.py','tools/cfo_phase74_guard_v1.py','tools/cfo_phase74_fix01_guard_v1.py','vivado/fft2048_project.tcl','vivado/configure_parallel_jobs.tcl','docs/FFT2048_CONTRACT_V1_ZH.md','docs/FFT2048_NATIVE_JOB_008.md','docs/CFO_MAIN_CONTRACT.json','docs/FRONTDATA007_SOURCE_LOCK.json','sim/vectors/fft2048_cases.json','matlab/bittrue/cfo_chain_arithmetic.m','reports/FFT2048_VECTOR_CHECK.json','reports/FRONTDATA007_REVIEW_20260914/INDEPENDENT_REVIEW.json','reports/FRONTDATA007_REVIEW_20260914/README_ZH.md','reports/FRONTDATA007_REVIEW_20260914/extract_frontdata007_v3_repair.py','reports/BACKEND006R1_REVIEW_20260914/INDEPENDENT_REVIEW.json']
 assert len(paths)==len(set(paths)) and len(members)==11
 for p in paths:
  if p.endswith('.py'):ast.parse((R/p).read_text(),filename=p)
 lock={'schema':'fft008_source_lock_v1','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(R),'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_fft2048_core','simulation_top':'cfo_fft2048_tb','project_members':[{'fileset':f,'path':p} for f,p in members],'files':[{'path':p,'bytes':(R/p).stat().st_size,'sha256':sha(R/p)} for p in paths],'native_stages':['create','simulate'],'scope':'FFT2048 primitive only. No full-frame, pilot multiply/sum, CDC, synthesis or clock500 physical qualification.'}
 p=R/'docs/FFT008_SOURCE_LOCK.json';assert not p.exists();p.write_text(json.dumps(lock,indent=2)+'\n',encoding='utf-8')
 guard=R/'tools/cfo_fft2048_guard_v1.py';s=guard.read_text();assert s.count('LOCK_SHA_TO_FREEZE')==1;s=s.replace('LOCK_SHA_TO_FREEZE',sha(p));ast.parse(s);guard.write_text(s,encoding='utf-8')
 print(json.dumps({'lock_sha256':sha(p),'files':len(paths),'members':len(members),'guard_sha256':sha(guard)}))
if __name__=='__main__':main()