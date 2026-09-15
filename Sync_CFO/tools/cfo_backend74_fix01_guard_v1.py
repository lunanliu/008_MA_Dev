#!/usr/bin/env python3
"""CFO-BACKEND006R1 supervisor: reuse CFO_BACKEND74 and replace quality v1 by v2."""
from __future__ import annotations
import argparse, csv, datetime as dt, importlib.util, json, os, shutil
from pathlib import Path

if os.name != "nt": raise SystemExit("Windows only")
ROOT=Path(r"D:\008_MA_Dev\T11_CFO"); PYTHON=Path(r"C:\Python314\python.exe"); VIVADO=Path(r"C:\NIFPGA\programs\Vivado2021_1\bin\vivado.bat")
V3=ROOT/"tools/cfo_native_guard_v3.py"; PHASE_GUARD=ROOT/"tools/cfo_phase74_guard_v1.py"; R1=ROOT/"tools/cfo_phase74_fix01_guard_v1.py"
OLD_LOCK=ROOT/"docs/BACKEND006_SOURCE_LOCK.json"; LOCK=ROOT/"docs/BACKEND006R1_SOURCE_LOCK.json"; CONTRACT=ROOT/"docs/BACKEND74_CONTRACT_V1_ZH.md"; DOC=ROOT/"docs/BACKEND74_NATIVE_JOB_006R1.md"; VERIFY_OLD=ROOT/"tools/verify_backend74.py"; VERIFY=ROOT/"tools/verify_backend74_fix01.py"
TCL=ROOT/"vivado/backend74_fix01.tcl"; THREADS=ROOT/"vivado/run_threads.tcl"; CONFIG=ROOT/"vivado/configure_parallel_jobs.tcl"; XPR=ROOT/"vivado/CFO_BACKEND74/CFO_BACKEND74.xpr"; BACKEND_PROJECT=ROOT/"vivado/CFO_BACKEND74"; BACKEND_SIM=BACKEND_PROJECT/"CFO_BACKEND74.sim/sim_1/behav/xsim"
OLD_CORE=ROOT/"rtl/cfo_fft74_quality.sv"; NEW_CORE=ROOT/"rtl/cfo_fft74_quality_v2.sv"; REVIEW=ROOT/"reports/BACKEND006_COMPILE_REVIEW_20260914/INDEPENDENT_REVIEW.json"; INIT_XPR_SHA="9653AF12054CC39EBCF697515A7D56C277C9E0FCF0DB21CCC8A4CB7160A75E04"; OLD_LOCK_SHA="000A950011FB210375B6AEB0C8004EEBC4F22CF8CAAB69A7D9441295A0100CF8"; LOCK_SHA="2BFBD70A0B237352C5F8547AF21281840CDFEEAA861E0F975B75C7B57837ACFF"; OLD_CORE_SHA="38AAE8B4C6DD7FC8BD5B57F1512192A3AE4C726DC74C14485C8EBD2716956430"; NEW_CORE_SHA="84B39001F074DFB2C08951221A5E801A02457EE7826C7813229F2478068EE3AF"
HARD_SIM=300; ZERO=5; FREE=6*1024**3
sp=importlib.util.spec_from_file_location("cfo_phase74_guard_v1",PHASE_GUARD); assert sp and sp.loader
Q=importlib.util.module_from_spec(sp); sp.loader.exec_module(Q)

def utc(): return Q.utc()
def info(p): return Q.info(p)
def wjson(p,x): return Q.wjson(p,x)
def event(p,n,**x): Q.event(p,n,**x)
def runpy(script,*args): return Q.py(script,*args)
def r1_paths(root,attempt,stage):
    ps=[attempt/"simulate.log",attempt/"simulate.jou",attempt/"simulate.stdout.log",attempt/"simulate.stderr.log",attempt/"simulate.samples.jsonl",attempt/"before_fix_actual_sources.csv",attempt/"updated_actual_sources.csv",attempt/"simulate_actual_sources.csv",attempt/"simulate_project_identity.txt",attempt/"backend74_actual.txt",attempt/"CFO_BACKEND74_before_source_update.xpr",attempt/"CFO_BACKEND74_after_source_update.xpr",attempt/"CFO_BACKEND74_final.xpr"]
    ps += [BACKEND_SIM/n for n in ("xvlog.log","compile.log","elaborate.log","xelab.log","simulate.log","xsim.log","xsim.dir/cfo_estimate74_backend_tb_behav/xsimkernel.log")]
    out=[]; seen=set()
    for p in ps:
        if str(p) not in seen: seen.add(str(p)); out.append(p)
    return out
def r1_marks(root,attempt,stage):
    ps=r1_paths(root,attempt,stage)
    return {"ready":Q.marker(ps,"CFO_BACKEND74_READY action=simulate "),"revision":Q.marker(ps,"CFO_BACKEND74_SOURCE_REVISION BACKEND006R1"),"done":Q.marker(ps,"CFO_BACKEND74_NATIVE_DONE action=simulate"),"passed":Q.marker(ps,"CFO_BACKEND74_PASS ")}
Q.paths=r1_paths; Q.marks=r1_marks
def load_lock(path): return json.loads(path.read_text(encoding="utf-8-sig"))
def locked(root,path):
    lock=load_lock(path); rows=[]; ok=True
    for item in lock["files"]:
        p=root/item["path"]; actual=info(p); match=bool(actual.get("exists") and actual.get("bytes")==item["bytes"] and actual.get("sha256")==item["sha256"]); ok &= match
        rows.append({"relative_path":item["path"],"expected_bytes":item["bytes"],"expected_sha256":item["sha256"],"actual":actual,"matches":match})
    return lock,rows,ok
def expected_members(root,lock): return {(x["fileset"],str((root/x["path"]).resolve()).casefold()) for x in lock["project_members"]}
def csv_members(path):
    try: return {(x["fileset"],str(Path(x["path"]).resolve()).casefold()) for x in csv.DictReader(path.open(encoding="utf-8-sig",newline=""))}
    except Exception: return set()
def source_audit(root,attempt,old_lock,new_lock):
    b=csv_members(attempt/"before_fix_actual_sources.csv"); u=csv_members(attempt/"updated_actual_sources.csv"); s=csv_members(attempt/"simulate_actual_sources.csv"); old=expected_members(root,old_lock); new=expected_members(root,new_lock); oldq=("sources_1",str(OLD_CORE.resolve()).casefold()); newq=("sources_1",str(NEW_CORE.resolve()).casefold())
    checks={"before_fix_members_exact_v1":b==old,"updated_members_exact_v2":u==new,"simulate_members_exact_v2":s==new,"updated_equals_simulate":u==s,"old_quality_absent_after_update":oldq not in u,"new_quality_present_after_update":newq in u}
    return {"checks":checks,"all_checks":all(checks.values()),"counts":{"expected_old":len(old),"expected_new":len(new),"before_fix":len(b),"updated":len(u),"simulate":len(s)},"before_fix":sorted([list(x) for x in b]),"updated":sorted([list(x) for x in u]),"simulate":sorted([list(x) for x in s])}
def baseline():
    allp=Q.G.native_snapshot(); protected=[x for x in allp if int(x.get("pid",-1)) in Q.T10]; other=[x for x in allp if str(x.get("image_name","")).lower() in {"vivado.exe","xsimk.exe","xelab.exe","xvlog.exe"} and int(x.get("pid",-1)) not in Q.T10]
    return {"all_native_processes":allp,"protected":protected,"protected_pids":[int(x["pid"]) for x in protected],"non_reserved_native_processes":other}
def t10_ok(before,after):
    a={int(x["pid"]):str(x.get("image_name","")) for x in after.get("all_native_processes",[])}; b={int(x["pid"]):str(x.get("image_name","")) for x in before.get("all_native_processes",[])}; ok=all(pid in a and a[pid].lower()==name.lower() for pid,name in Q.T10.items()); return ok,{"before":b,"after":a,"protected_expected":Q.T10}
def command(attempt): return [str(VIVADO),"-mode","batch","-source","D:/008_MA_Dev/T11_CFO/vivado/backend74_fix01.tcl","-log",str(attempt/"simulate.log"),"-journal",str(attempt/"simulate.jou"),"-tclargs",str(attempt)]
def freeze(root,attempt,controller,frozen_copy,pre,base,mem,old_lock,old_rows,old_ok,lock,rows,lockok):
    current_xpr=info(XPR); checks={"r1_source_lock_hash":info(LOCK).get("sha256")==LOCK_SHA,"all_52_locked_files_match":lockok and len(rows)==52,"legacy_source_lock_hash":info(OLD_LOCK).get("sha256")==OLD_LOCK_SHA,"legacy_41_files_match":old_ok and len(old_rows)==41,"existing_xpr_expected":current_xpr.get("sha256")==INIT_XPR_SHA and current_xpr.get("exists"),"old_quality_expected":info(OLD_CORE).get("sha256")==OLD_CORE_SHA,"new_quality_expected":info(NEW_CORE).get("sha256")==NEW_CORE_SHA,"compile_review_present":REVIEW.is_file(),"legacy_verify_exit_0":pre["legacy"]["exit_code"]==0,"r1_verify_exit_0":pre["r1"]["exit_code"]==0,"t10_vivado_present":any(int(x.get("pid",-1))==34768 and str(x.get("image_name","")).lower()=="vivado.exe" for x in base["all_native_processes"]),"t10_xsim_present":any(int(x.get("pid",-1))==28856 and str(x.get("image_name","")).lower()=="xsimk.exe" for x in base["all_native_processes"]),"no_other_vivado_or_xsim_process":not base["non_reserved_native_processes"],"free_memory_recommendation":isinstance(mem.get("available_physical_bytes"),int) and mem["available_physical_bytes"]>=FREE}
    deps=[DOC,CONTRACT,VERIFY_OLD,VERIFY,TCL,THREADS,CONFIG,OLD_LOCK,LOCK,REVIEW,V3,PHASE_GUARD,R1,OLD_CORE,NEW_CORE,XPR]
    return {"schema":"cfo_backend006r1_execution_freeze_v1","job_id":"CFO-BACKEND006R1","recorded_utc":utc(),"root":str(root),"attempt":str(attempt),"controller":{"path":str(controller),"info":info(controller),"frozen_copy":{"path":str(frozen_copy),"info":info(frozen_copy)},"guard_v3":{"path":str(V3),"info":info(V3)},"phase_guard_reference":{"path":str(PHASE_GUARD),"info":info(PHASE_GUARD)},"phase_fix01_reference":{"path":str(R1),"info":info(R1)}},"source_lock":{"path":str(LOCK),"expected_sha256":LOCK_SHA,"actual":info(LOCK),"member_count":len(rows),"all_members_match":lockok,"project_members":lock["project_members"]},"legacy_source_lock":{"path":str(OLD_LOCK),"expected_sha256":OLD_LOCK_SHA,"actual":info(OLD_LOCK),"member_count":len(old_rows),"all_members_match":old_ok,"project_members":old_lock["project_members"]},"project_checkpoint":{"xpr":current_xpr,"expected_initial_sha256":INIT_XPR_SHA,"hardware_top":"cfo_estimate74_backend","simulation_top":"cfo_estimate74_backend_tb","part":"xcvu11p-flgb2104-2-e","old_quality":info(OLD_CORE),"new_quality":info(NEW_CORE)},"dependencies":{str(p):info(p) for p in deps},"tools":{"python":str(PYTHON),"python_version":__import__("sys").version,"vivado":str(VIVADO),"vivado_version_declared":"2021.1"},"preflight_verification":pre,"preexisting_native_processes":base,"startup_memory":mem,"resources":{"t10_reserved_pids":Q.T10,"max_concurrent_backend_vivado":1,"matlab_slots":0,"planned_peak_gib_warning":4,"free_recommendation_gib":6,"hard_memory_available_gib":.25,"sustained_memory_available_gib":.5,"sustained_memory_seconds":30,"native_stages_serial":True,"xelab_jobs":16,"general_maxThreads":8,"synth_maxThreads":8},"command":command(attempt),"hard_timeouts_seconds":{"simulate":HARD_SIM,"post_trigger_zero_grace":ZERO},"scope_guards":{"no_t10_operation":True,"no_matlab":True,"no_create_project":True,"no_old_runner":True,"no_old_independent_stage_repeat":True,"no_synthesis":True,"no_implementation":True,"no_fft2048_or_fullframe":True,"no_auto_restart":True,"no_native_started_before_freeze":True},"checks":checks}
def raw_pass(line):
    import re
    z=re.search(r"^CFO_BACKEND74_PASS unique=(\d+) completed=(\d+) protocol_errors=(\d+) max_tail=(\d+) max_total=(\d+) stalled_cycles=(\d+) reset_discards=(\d+) abort_discards=(\d+) divider_cases=(\d+)",line or "")
    return dict(zip(("unique","completed","protocol_errors","max_tail","max_total","stalled_cycles","reset_discards","abort_discards","divider_cases"),map(int,z.groups()))) if z else None
def common_ok(r):
    m=r.get("markers",{}); f=r.get("final_census_before_close",{})
    return bool(r.get("binding_succeeded") and r.get("events",{}).get("zero") and f.get("empty_verified") and r.get("native_exit_code_final")==0 and not r.get("controller_errors") and not r.get("persistent_telemetry_fault") and not r.get("termination_requested_by_controller") and m.get("ready",{}).get("found") and m.get("done",{}).get("found") and m.get("revision",{}).get("found") and r.get("ready_pid",0)>0 and r.get("stable_telemetry_samples",0)>=1)
def pass_ok(r,verify_result,audit):
    m=r.get("markers",{}); v=raw_pass(m.get("passed",{}).get("line")); r["raw_pass_values"]=v; good=bool(v and v["unique"]==28 and v["completed"]==38 and v["protocol_errors"]==5 and v["stalled_cycles"]==154 and v["reset_discards"]==5 and v["abort_discards"]==5 and v["divider_cases"]==14 and v["max_tail"]<=7600 and v["max_total"]<=12000)
    return bool(common_ok(r) and m.get("passed",{}).get("found") and good and audit.get("all_checks") and verify_result.get("exit_code")==0)
def copy_native_logs(root,attempt):
    rows=[]
    for src,name in [(BACKEND_SIM/"xvlog.log","native_xvlog.log"),(BACKEND_SIM/"compile.log","native_compile.log"),(BACKEND_SIM/"elaborate.log","native_xelab.log"),(BACKEND_SIM/"simulate.log","native_simulate.log"),(BACKEND_SIM/"xsim.log","native_xsim.log"),(BACKEND_SIM/"xsim.dir/cfo_estimate74_backend_tb_behav/xsimkernel.log","native_xsimkernel.log")]:
        dst=attempt/name
        try: shutil.copy2(src,dst)
        except Exception as e: rows.append({"source":str(src),"destination":str(dst),"error":repr(e)})
        else: rows.append({"source":str(src),"destination":str(dst),"info":info(dst)})
    return rows
def project_files():
    if not BACKEND_PROJECT.is_dir(): return []
    return [info(p) for p in sorted(BACKEND_PROJECT.rglob("*")) if p.is_file() and (p==XPR or p.suffix.lower() in {".log",".jou",".txt",".prj",".pb",".wdb",".wcfg"})]
def artifacts(attempt):
    rows=[]; seen=set()
    for p in sorted(attempt.rglob("*")):
        if p.is_file() and p.name!="ATTEMPT_ARTIFACT_MANIFEST.json": rows.append(info(p)); seen.add(str(p))
    rows += [x for x in project_files() if x.get("path") not in seen]
    return rows
def complete(attempt,root,payload):
    ch=wjson(attempt/"ATTEMPT_COMPLETION.json",payload); clock=attempt/"report_clock.json"
    if clock.exists(): z=json.loads(clock.read_text(encoding="utf-8")); z.update({"status":"COMPLETE","ended_utc":utc(),"final_status":payload.get("status")}); wjson(clock,z)
    mh=wjson(attempt/"ATTEMPT_ARTIFACT_MANIFEST.json",{"schema":"cfo_backend006r1_artifact_manifest_v1","generated_utc":utc(),"attempt":str(attempt),"completion_sha256":ch,"artifacts":artifacts(attempt)})
    return ch,mh
def verify(attempt):
    return runpy(VERIFY,"--actual",attempt/"backend74_actual.txt","--sources",attempt/"simulate_actual_sources.csv","--identity",attempt/"simulate_project_identity.txt")
def parse_json(r):
    try:
        lines=[x for x in r.get("stdout","").splitlines() if x.strip()]; return json.loads(lines[-1]) if lines else None
    except Exception: return None
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--self-check",action="store_true"); q=ap.parse_args(); root=ROOT.resolve()
    if q.self_check:
        c={"root":root.is_dir(),"guard_v3":V3.is_file(),"phase_guard_reference":PHASE_GUARD.is_file(),"r1_reference":R1.is_file(),"pointer_size":Q.G.PTR_SIZE==8,"accounting_class":Q.G.JOB_ACCOUNTING==1,"fix01_tcl":TCL.is_file(),"r1_source_lock":LOCK.is_file(),"r1_verify":VERIFY.is_file(),"existing_xpr":XPR.is_file(),"old_quality":OLD_CORE.is_file(),"new_quality":NEW_CORE.is_file(),"no_native_started":True}; print(json.dumps({"schema":"cfo_backend006r1_controller_self_check_v1","checks":c,"native_started":False})); return 0 if all(c.values()) else 2
    parent=root/"work/CFO_BACKEND006R1"; parent.mkdir(parents=True,exist_ok=True); attempt=parent/f"attempt_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}_luna"; attempt.mkdir(); ep=attempt/"controller_events.jsonl"; frozen_copy=attempt/"cfo_backend74_fix01_guard_v1_frozen.py"; shutil.copy2(Path(__file__).resolve(),frozen_copy); wjson(attempt/"report_clock.json",{"schema":"cfo_backend006r1_report_clock_v1","thread_id":"01a076f1-ad1b-7d33-a29c-4ea34ae84d01","started_utc":utc(),"interval_minutes":15,"status":"ACTIVE"})
    old_lock,old_rows,old_ok=locked(root,OLD_LOCK); lock,rows,lockok=locked(root,LOCK); pre={"legacy":runpy(VERIFY_OLD),"r1":runpy(VERIFY)}; base=baseline(); mem=Q.G.mem(); fr=freeze(root,attempt,Path(__file__).resolve(),frozen_copy,pre,base,mem,old_lock,old_rows,old_ok,lock,rows,lockok); fsha=wjson(attempt/"EXECUTION_FREEZE.json",fr); event(ep,"execution_freeze_written",sha256=fsha,checks=fr["checks"])
    if not all(fr["checks"].values()):
        c={"schema":"cfo_backend006r1_completion_v1","job_id":"CFO-BACKEND006R1","status":"BLOCKED_PREFLIGHT","attempt":str(attempt),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":fsha},"checks":fr["checks"],"scope_guards":fr["scope_guards"],"post_native_processes":Q.G.native_snapshot(),"repair_audit":{"rtl_or_vector_modified_by_wrapper":False,"native_stages_reexecuted":False}}; ch,mh=complete(attempt,root,c); print(json.dumps({"status":c["status"],"attempt":str(attempt),"completion_sha256":ch,"manifest_sha256":mh})); return 3
    out={}; out["simulate"]=Q.stage(root,attempt,"simulate",fr["command"],HARD_SIM,ep); out["simulate"]["native_log_copies"]=copy_native_logs(root,attempt); out["simulate"]["verify"]=verify(attempt); out["simulate"]["verify_json"]=parse_json(out["simulate"]["verify"]); out["simulate"]["source_audit"]=source_audit(root,attempt,old_lock,lock); out["simulate"]["xpr"]={"current":info(XPR),"before_source_update":info(attempt/"CFO_BACKEND74_before_source_update.xpr"),"after_source_update":info(attempt/"CFO_BACKEND74_after_source_update.xpr"),"final_copy":info(attempt/"CFO_BACKEND74_final.xpr")}
    out["simulate"]["status"]="PASS" if pass_ok(out["simulate"],out["simulate"]["verify"],out["simulate"]["source_audit"]) and out["simulate"]["xpr"]["before_source_update"].get("sha256")==INIT_XPR_SHA and out["simulate"]["xpr"]["after_source_update"].get("exists") and out["simulate"]["xpr"]["final_copy"].get("exists") else "FAIL"; wjson(attempt/"simulate_verify.json",out["simulate"]["verify"]); wjson(attempt/"simulate_source_audit.json",out["simulate"]["source_audit"])
    post=Q.G.native_snapshot(); tgood,tdelta=t10_ok(base,{"all_native_processes":post}); post_lock,post_rows,post_ok=locked(root,LOCK); status="PASS" if out["simulate"]["status"]=="PASS" and tgood and post_ok else "FAIL"; c={"schema":"cfo_backend006r1_completion_v1","job_id":"CFO-BACKEND006R1","status":status,"attempt":str(attempt),"generated_utc":utc(),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":fsha},"stages":out,"post_source_lock":{"lock":post_lock,"members":post_rows,"all_members_match":post_ok},"post_native_processes":post,"t10_unchanged":tdelta,"t10_not_operated_by_controller":True,"no_matlab":True,"no_create_project":True,"no_old_independent_repeat":True,"no_synthesis_or_implementation":True,"scope":"Only the existing CFO_BACKEND74 project was source-revised from quality v1 to the authorized v2 declaration split and its behavioral XSim stage was run; no create_project, FFT2048 front end, full-frame, CLIP, synthesis, timing, sustained-throughput, or T11/T12/T13 qualification claim.","repair_audit":{"rtl_or_vector_modified_by_wrapper":False,"native_stages_reexecuted":False,"old_project_rebuilt":False}}; ch,mh=complete(attempt,root,c); print(json.dumps({"status":status,"attempt":str(attempt),"completion_sha256":ch,"manifest_sha256":mh})); return 0 if status=="PASS" else 6
if __name__=="__main__": raise SystemExit(main())
