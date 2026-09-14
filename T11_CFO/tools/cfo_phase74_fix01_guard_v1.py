#!/usr/bin/env python3
"""CFO-PHASE004R1 single-stage supervisor for the reviewed whitespace-only RTL fix."""
from __future__ import annotations
import argparse, csv, datetime as dt, importlib.util, json, os, re, shutil
from pathlib import Path

if os.name != "nt": raise SystemExit("Windows only")
ROOT=Path(r"D:\008_MA_Dev\T11_CFO"); GUARD=ROOT/"tools/cfo_phase74_guard_v1.py"
LOCK=ROOT/"docs/PHASE004R1_SOURCE_LOCK.json"; OLD_LOCK=ROOT/"docs/PHASE004_SOURCE_LOCK.json"
DOC=ROOT/"docs/PHASE74_NATIVE_JOB_004R1.md"; CONTRACT=ROOT/"docs/PHASE74_CONTRACT_V1_ZH.md"
VP=ROOT/"tools/verify_phase74.py"; VPF=ROOT/"tools/verify_phase74_fix01.py"; VC=ROOT/"tools/verify_coordinate.py"; VR=ROOT/"tools/verify_rotator.py"
TCL=ROOT/"vivado/phase74_fix01.tcl"; THREADS=ROOT/"vivado/run_threads.tcl"; CONFIG=ROOT/"vivado/configure_parallel_jobs.tcl"
V2=ROOT/"rtl/cfo_phase74_core_v2.sv"; V1=ROOT/"rtl/cfo_phase74_core.sv"; XPR=ROOT/"vivado/CFO_PHASE74/CFO_PHASE74.xpr"
FAILED_XPR=ROOT/"reports/PHASE004_COMPILE_REVIEW_20260914/CFO_PHASE74_before_fix.xpr"; REVIEW=ROOT/"reports/PHASE004_COMPILE_REVIEW_20260914/INDEPENDENT_REVIEW.json"
LOCK_SHA="601EB944FD0A0E03B5E459DE11A3749AA72DC6004C2DA94847CC56E737A306CD"; V2_SHA="70115D741EFFADDFFA8E1C69767057638CAB6F28DBB9FA6BAD7C36E40A760028"; V1_SHA="49C08A1B7FA8860AB418D3D823DDF767A59FDC2877DE682AE1724501F63812D4"; INITIAL_XPR_SHA="401AC5B0C6105AE0564AEBA059E205196F74DF3807DAEC12F7596AA81AD4E92D"
HARD=300; ZERO=5; FREE=6*1024**3
sp=importlib.util.spec_from_file_location("cfo_phase74_guard_v1",GUARD); assert sp and sp.loader
Q=importlib.util.module_from_spec(sp); sp.loader.exec_module(Q)

def utc(): return Q.utc()
def info(p): return Q.info(p)
def wjson(p,x): return Q.wjson(p,x)
def event(p,n,**x): Q.event(p,n,**x)
def runpy(script,*args): return Q.py(script,*args)
def locked(root,path):
    lock=json.loads(path.read_text(encoding="utf-8-sig")); rows=[]; ok=True
    for item in lock["files"]:
        p=root/item["path"]; actual=info(p); match=bool(actual.get("exists") and actual.get("bytes")==item["bytes"] and actual.get("sha256")==item["sha256"]); ok &= match
        rows.append({"relative_path":item["path"],"expected_bytes":item["bytes"],"expected_sha256":item["sha256"],"actual":actual,"matches":match})
    return lock,rows,ok
def expected_members(root,lock): return {(x["fileset"],str((root/x["path"]).resolve()).casefold()) for x in lock["project_members"]}
def csv_members(path):
    try: return {(x["fileset"],str(Path(x["path"]).resolve()).casefold()) for x in csv.DictReader(path.open(encoding="utf-8-sig",newline=""))}
    except Exception: return set()
def source_sets(root,attempt,old_lock,new_lock):
    before=csv_members(attempt/"before_fix_actual_sources.csv"); updated=csv_members(attempt/"updated_actual_sources.csv"); simulate=csv_members(attempt/"simulate_actual_sources.csv")
    old_expected=expected_members(root,old_lock); new_expected=expected_members(root,new_lock); old_core=("sources_1",str(V1.resolve()).casefold()); new_core=("sources_1",str(V2.resolve()).casefold())
    checks={"before_old_members_exact":before==old_expected,"updated_new_members_exact":updated==new_expected,"simulate_new_members_exact":simulate==new_expected,"updated_equals_simulate":updated==simulate,"updated_contains_v2":new_core in updated,"updated_excludes_v1":old_core not in updated,"before_contains_v1":old_core in before,"before_excludes_v2":new_core not in before}
    return {"checks":checks,"all_checks":all(checks.values()),"counts":{"before":len(before),"updated":len(updated),"simulate":len(simulate)},"before":sorted([list(x) for x in before]),"updated":sorted([list(x) for x in updated]),"simulate":sorted([list(x) for x in simulate])}
def baseline():
    allp=Q.G.native_snapshot(); protected=[x for x in allp if int(x.get("pid",-1)) in Q.T10]; other=[x for x in allp if str(x.get("image_name","")).lower() in {"vivado.exe","xsimk.exe","xelab.exe","xvlog.exe"} and int(x.get("pid",-1)) not in Q.T10]
    return {"all_native_processes":allp,"protected":protected,"protected_pids":[int(x["pid"]) for x in protected],"non_reserved_native_processes":other}
def t10_ok(before,after):
    a={int(x["pid"]):str(x.get("image_name","")) for x in after.get("all_native_processes",[])}; b={int(x["pid"]):str(x.get("image_name","")) for x in before.get("all_native_processes",[])}; ok=all(pid in a and a[pid].lower()==name.lower() for pid,name in Q.T10.items()); return ok,{"before":b,"after":a,"protected_expected":Q.T10}
def command(attempt): return [str(Q.VIVADO),"-mode","batch","-source","D:/008_MA_Dev/T11_CFO/vivado/phase74_fix01.tcl","-log",str(attempt/"simulate.log"),"-journal",str(attempt/"simulate.jou"),"-tclargs",str(attempt)]
def freeze(root,attempt,pre,base,mem,new_lock,new_rows,new_ok,old_lock,old_rows,old_ok):
    checks={"new_lock_hash":info(LOCK).get("sha256")==LOCK_SHA,"all_36_locked_files_match":new_ok and len(new_rows)==36,"v2_hash":info(V2).get("sha256")==V2_SHA,"v1_hash_preserved":info(V1).get("sha256")==V1_SHA,"initial_xpr_hash":info(XPR).get("sha256")==INITIAL_XPR_SHA,"archived_failed_xpr_hash":info(FAILED_XPR).get("sha256")==INITIAL_XPR_SHA,"review_pass":REVIEW.is_file() and json.loads(REVIEW.read_text(encoding="utf-8"))["status"]=="RTL_LEXICAL_FAILURE_REPAIR_READY_NOT_YET_COMPILED","fix_tcl_has_no_create_project":not re.search(r"\bcreate_project\b",TCL.read_text(encoding="utf-8")),"preflight_rotator_exit_0":pre["rotator"]["exit_code"]==0,"preflight_coordinate_exit_0":pre["coordinate"]["exit_code"]==0,"preflight_phase74_exit_0":pre["phase74"]["exit_code"]==0,"preflight_fix01_exit_0":pre["fix01"]["exit_code"]==0,"t10_vivado_present":any(int(x.get("pid",-1))==34768 and str(x.get("image_name","")).lower()=="vivado.exe" for x in base["all_native_processes"]),"t10_xsim_present":any(int(x.get("pid",-1))==28856 and str(x.get("image_name","")).lower()=="xsimk.exe" for x in base["all_native_processes"]),"no_other_vivado_or_xsim_process":not base["non_reserved_native_processes"],"free_memory_recommendation":isinstance(mem.get("available_physical_bytes"),int) and mem["available_physical_bytes"]>=FREE}
    return {"schema":"cfo_phase004r1_execution_freeze_v1","job_id":"CFO-PHASE004R1","recorded_utc":utc(),"root":str(root),"attempt":str(attempt),"controller":{"path":str(Path(__file__).resolve()),"info":info(Path(__file__).resolve()),"original_controller":{"path":str(GUARD),"info":info(GUARD)}}, "source_lock":{"path":str(LOCK),"expected_sha256":LOCK_SHA,"actual":info(LOCK),"members":new_rows,"member_count":len(new_rows),"all_members_match":new_ok,"project_members":new_lock["project_members"]},"legacy_source_lock":{"path":str(OLD_LOCK),"actual":info(OLD_LOCK),"members":old_rows,"member_count":len(old_rows),"all_members_match":old_ok},"reviewed_fix":{"v1_core":{"path":str(V1),"info":info(V1)},"v2_core":{"path":str(V2),"info":info(V2)},"old_xpr":{"path":str(FAILED_XPR),"info":info(FAILED_XPR)},"review":{"path":str(REVIEW),"info":info(REVIEW)}},"frozen_project":{"part":new_lock["part"],"hardware_top":new_lock["hardware_top"],"simulation_top":new_lock["simulation_top"],"existing_xpr":str(XPR),"initial_xpr":info(XPR)},"dependencies":{str(p):info(p) for p in [DOC,CONTRACT,VP,VPF,VC,VR,TCL,THREADS,CONFIG,OLD_LOCK,FAILED_XPR,REVIEW]},"tools":{"python":str(Q.PYTHON),"python_version":__import__("sys").version,"vivado":str(Q.VIVADO),"vivado_version_declared":"2021.1"},"preflight_verification":pre,"preexisting_native_processes":base,"startup_memory":mem,"resources":{"t10_reserved_pids":Q.T10,"max_concurrent_cfo_vivado":1,"matlab_slots":0,"planned_peak_gib_warning":4,"free_recommendation_gib":6,"hard_memory_available_gib":.25,"sustained_memory_available_gib":.5,"sustained_memory_seconds":30,"native_stages_serial":True,"xelab_jobs":16,"general_maxThreads":8,"synth_maxThreads":8},"command":command(attempt),"hard_timeouts_seconds":{"simulate":HARD,"post_trigger_zero_grace":ZERO},"scope_guards":{"no_create_project":True,"no_t10_operation":True,"no_matlab":True,"no_old_runner":True,"no_old_stage_repeat":True,"no_rotator_repeat":True,"no_coordinate_repeat":True,"no_synthesis":True,"no_implementation":True,"no_fft_or_fullframe":True,"no_auto_restart":True,"no_native_started_before_freeze":True},"checks":checks}
def pass_ok(r,fix_markers,source_check,verify_result):
    m=r.get("markers",{}); f=r.get("final_census_before_close",{}); v=Q.pass_values(m.get("passed",{})); r["raw_pass_values"]=v
    common=bool(r.get("binding_succeeded") and r.get("events",{}).get("zero") and f.get("empty_verified") and r.get("native_exit_code_final")==0 and not r.get("controller_errors") and not r.get("persistent_telemetry_fault") and not r.get("termination_requested_by_controller") and m.get("ready",{}).get("found") and m.get("done",{}).get("found") and r.get("ready_pid",0)>0 and r.get("stable_telemetry_samples",0)>=1 and r.get("unstable_after_ready_samples",0)<=3)
    raw=bool(m.get("passed",{}).get("found") and v and v["unique"]==27 and v["completed"]==33 and v["protocol_errors"]==5 and v["stalled_cycles"]==150 and v["reset_discards"]==3 and v["abort_discards"]==3 and v["max_tail"]<=6000 and v["max_total"]<=11000)
    return bool(common and raw and fix_markers.get("revision",{}).get("found") and fix_markers.get("repair",{}).get("found") and source_check.get("all_checks") and verify_result.get("exit_code")==0)
def copy_native_logs(root,attempt):
    simdir=root/"vivado/CFO_PHASE74/CFO_PHASE74.sim/sim_1/behav/xsim"; rows=[]
    for name in ("xvlog.log","xelab.log","xsim.log"):
        src=simdir/name; dst=attempt/f"native_{name}"
        try: shutil.copy2(src,dst)
        except Exception as e: rows.append({"source":str(src),"destination":str(dst),"error":repr(e)})
        else: rows.append({"source":str(src),"destination":str(dst),"info":info(dst)})
    return rows
def artifacts(attempt):
    rows=[]; seen=set()
    for p in sorted(attempt.rglob("*")):
        if p.is_file() and p.name!="ATTEMPT_ARTIFACT_MANIFEST.json": rows.append(info(p)); seen.add(str(p))
    rows += [x for x in Q.project_files() if x.get("path") not in seen]; return rows
def complete(attempt,root,payload):
    ch=wjson(attempt/"ATTEMPT_COMPLETION.json",payload); clock=attempt/"report_clock.json"
    if clock.exists(): z=json.loads(clock.read_text(encoding="utf-8")); z.update({"status":"COMPLETE","ended_utc":utc(),"final_status":payload.get("status")}); wjson(clock,z)
    mh=wjson(attempt/"ATTEMPT_ARTIFACT_MANIFEST.json",{"schema":"cfo_phase004r1_artifact_manifest_v1","generated_utc":utc(),"attempt":str(attempt),"completion_sha256":ch,"artifacts":artifacts(attempt)})
    return ch,mh
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--self-check",action="store_true"); q=ap.parse_args(); root=ROOT.resolve()
    if q.self_check:
        c={"root":root.is_dir(),"guard":GUARD.is_file(),"v3_pointer_size":Q.G.PTR_SIZE==8,"v3_accounting_class":Q.G.JOB_ACCOUNTING==1,"fix_tcl":TCL.is_file(),"new_lock":LOCK.is_file(),"new_verify":VPF.is_file(),"v2":V2.is_file(),"no_native_started":True}; print(json.dumps({"schema":"cfo_phase004r1_controller_self_check_v1","checks":c,"native_started":False})); return 0 if all(c.values()) else 2
    parent=root/"work/CFO_PHASE004R1"; parent.mkdir(parents=True,exist_ok=True); attempt=parent/f"attempt_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}_luna"; attempt.mkdir(); ep=attempt/"controller_events.jsonl"; wjson(attempt/"report_clock.json",{"schema":"cfo_phase004r1_report_clock_v1","thread_id":"01a076f0-d8c0-72a0-8371-cb2ff29c1b28","started_utc":utc(),"interval_minutes":15,"status":"ACTIVE"})
    new_lock,new_rows,new_ok=locked(root,LOCK); old_lock,old_rows,old_ok=locked(root,OLD_LOCK); pre={"rotator":runpy(VR),"coordinate":runpy(VC),"phase74":runpy(VP),"fix01":runpy(VPF)}; base=baseline(); mem=Q.G.mem(); fr=freeze(root,attempt,pre,base,mem,new_lock,new_rows,new_ok,old_lock,old_rows,old_ok); fsha=wjson(attempt/"EXECUTION_FREEZE.json",fr); event(ep,"execution_freeze_written",sha256=fsha,checks=fr["checks"])
    if not all(fr["checks"].values()):
        c={"schema":"cfo_phase004r1_completion_v1","job_id":"CFO-PHASE004R1","status":"BLOCKED_PREFLIGHT","attempt":str(attempt),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":fsha},"checks":fr["checks"],"scope_guards":fr["scope_guards"],"post_native_processes":Q.G.native_snapshot(),"repair_audit":{"rtl_or_vector_modified_by_wrapper":False}}; ch,mh=complete(attempt,root,c); print(json.dumps({"status":c["status"],"attempt":str(attempt),"completion_sha256":ch,"manifest_sha256":mh})); return 3
    r=Q.stage(root,attempt,"simulate",fr["command"],HARD,ep); r["native_log_copies"]=copy_native_logs(root,attempt); fix_markers={"revision":Q.marker(Q.paths(root,attempt,"simulate"),"CFO_PHASE74_SOURCE_REVISION "),"repair":Q.marker(Q.paths(root,attempt,"simulate"),"CFO_PHASE74_SOURCE_REPAIR ")}; source_check=source_sets(root,attempt,old_lock,new_lock); r["fix_markers"]=fix_markers; r["source_sets"]=source_check; verify_result=runpy(VPF,"--actual",attempt/"phase74_actual.txt","--sources",attempt/"simulate_actual_sources.csv","--identity",attempt/"simulate_project_identity.txt"); r["verify"]=verify_result
    try: r["verify_json"]=json.loads([x for x in verify_result["stdout"].splitlines() if x.strip()][-1])
    except Exception: r["verify_json"]=None
    r["xpr_final"]=info(XPR); r["xpr_copies"]={name:info(attempt/name) for name in ("CFO_PHASE74_before_source_update.xpr","CFO_PHASE74_after_source_update.xpr","CFO_PHASE74_final.xpr")}; r["status"]="PASS" if pass_ok(r,fix_markers,source_check,verify_result) else "FAIL"; wjson(attempt/"source_update_check.json",source_check); wjson(attempt/"simulate_verify.json",verify_result)
    post=Q.G.native_snapshot(); tgood,tdelta=t10_ok(base,{"all_native_processes":post}); post_lock,post_rows,post_ok=locked(root,LOCK); status="PASS" if r["status"]=="PASS" and tgood and post_ok else ("BLOCKED_AFTER_SOURCE_UPDATE" if source_check.get("all_checks") else "FAIL")
    c={"schema":"cfo_phase004r1_completion_v1","job_id":"CFO-PHASE004R1","status":status,"attempt":str(attempt),"generated_utc":utc(),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":fsha},"stage":r,"source_update_check":source_check,"post_source_lock":{"lock":post_lock,"members":post_rows,"all_members_match":post_ok},"post_native_processes":post,"t10_unchanged":tdelta,"t10_not_operated_by_controller":True,"no_matlab":True,"no_create_project":True,"no_old_stage_repeat":True,"no_synthesis_or_implementation":True,"scope":"Only the reviewed v2 whitespace repair was applied to the existing CFO_PHASE74 project, followed by the pending serial compile/elaboration/behavioral simulation; no FFT, full-frame, T11/T12/T13, synthesis, timing, or 500MS/s claim.","repair_audit":{"reviewed_v1_sha256":V1_SHA,"reviewed_v2_sha256":V2_SHA,"rtl_or_vector_modified_by_wrapper":False,"old_project_rebuilt":False,"old_successful_create_repeated":False}}; ch,mh=complete(attempt,root,c); print(json.dumps({"status":status,"attempt":str(attempt),"completion_sha256":ch,"manifest_sha256":mh})); return 0 if status=="PASS" else 6
if __name__=="__main__": raise SystemExit(main())
