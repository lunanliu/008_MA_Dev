"""Freeze the not-yet-dispatched FFT005 package. Do not re-run after dispatch."""
from pathlib import Path
import json,hashlib,datetime
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
 members=[('sources_1','rtl/cfo_fft256_core.sv'),('sources_1','ip/fft256_twiddle.mem'),('constrs_1','constraints/cfo_fft256.xdc'),('sim_1','sim/tb/cfo_fft256_tb.sv'),('sim_1','sim/vectors/fft256_config.svh')]+[('sim_1',f'sim/vectors/fft256_{x}.mem') for x in ['input','output','butterfly','saturation']]+[('utils_1','vivado/run_threads.tcl')]
 paths=[p for _,p in members]+['sim/vectors/fft256_cases.json','tools/fft256_reference.py','tools/extract_fft256_published.py','tools/extract_phase74_published.py','tools/verify_fft256.py','tools/freeze_fft005_sources.py','tools/cfo_native_guard_v3.py','vivado/fft256_project.tcl','vivado/configure_parallel_jobs.tcl','docs/FFT256_CONTRACT_V1_ZH.md','docs/FFT256_NATIVE_JOB_005.md','docs/CFO_MAIN_CONTRACT.json','matlab/bittrue/cfo_chain_arithmetic.m','reports/FFT256_VECTOR_CHECK.json','reports/PHASE004R1_REVIEW_20260914/INDEPENDENT_REVIEW.json','reports/PHASE004R1_REVIEW_20260914/README_ZH.md','docs/PHASE004R1_SOURCE_LOCK.json']
 assert len(paths)==len(set(paths)) and len(members)==10
 rows=[{'path':p,'bytes':(R/p).stat().st_size,'sha256':sha(R/p)} for p in paths]
 lock={'schema':'cfo_fft005_source_lock_v1','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(R),'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_fft256_core','simulation_top':'cfo_fft256_tb','project_members':[{'fileset':f,'path':p} for f,p in members],'files':rows,'native_stages':['create','simulate'],'previous_native_tests_must_not_repeat':True,'matlab_runs':0,'scope':'FFT256 arithmetic primitive only; normalization, quality, final modes pending'}
 p=R/'docs/FFT005_SOURCE_LOCK.json';assert not p.exists(),'Cannot overwrite a source lock';p.write_text(json.dumps(lock,indent=2)+'\n',encoding='utf-8');print(json.dumps({'path':str(p),'sha256':sha(p),'files':len(rows),'project_members':len(members)}))
if __name__=='__main__':main()