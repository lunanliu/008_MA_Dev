#!/usr/bin/env python3
"""CFO-PHASE004 native create/simulate supervisor for the frozen 74-point path."""
from __future__ import annotations
import argparse, datetime as dt, importlib.util, json, os, re, subprocess, sys, time
from pathlib import Path

if os.name != "nt": raise SystemExit("Windows only")
ROOT=Path(r"D:\008_MA_Dev\T11_CFO"); PYTHON=Path(r"C:\Python314\python.exe"); VIVADO=Path(r"C:\NIFPGA\programs\Vivado2021_1\bin\vivado.bat")
V3=ROOT/"tools/cfo_native_guard_v3.py"; LOCK=ROOT/"docs/PHASE004_SOURCE_LOCK.json"; DOC=ROOT/"docs/PHASE74_NATIVE_JOB_004.md"; CONTRACT=ROOT/"docs/PHASE74_CONTRACT_V1_ZH.md"
VP=ROOT/"tools/verify_phase74.py"; VC=ROOT/"tools/verify_coordinate.py"; VR=ROOT/"tools/verify_rotator.py"; TCL=ROOT/"vivado/phase74_project.tcl"; THREADS=ROOT/"vivado/run_threads.tcl"; CONFIG=ROOT/"vivado/configure_parallel_jobs.tcl"
OLD_SYNC=ROOT/"vivado/CFO_SYNC/CFO_SYNC.xpr"; OLD_COORD=ROOT/"vivado/CFO_COORD/CFO_COORD.xpr"; XPR=ROOT/"vivado/CFO_PHASE74/CFO_PHASE74.xpr"; PARSE=ROOT/"reports/CFO_GUARD003_PARSE_CHECK_20260914.json"
LOCK_SHA="8717207E2772437418D0CDED3AD71836F14A8B456CE58A510C4531CD6E2B96E0"; SYNC_SHA="8EE3459986419C34B42B4261A0E38B2D5C670B47E25E33D80B46074CD4EE8063"; COORD_SHA="7605D752B0BB2C0B7BE2841D823E5C0AC3C25EA15D848239E3200AFBC40239A4"
T10={34768:"vivado.exe",28856:"xsimk.exe"}; HARD=.25*1024**3; LOW=.5*1024**3; FREE=6*1024**3; ZERO=5; CREATE=120; SIM=300
sp=importlib.util.spec_from_file_location("cfo_native_guard_v3",V3); assert sp and sp.loader
G=importlib.util.module_from_spec(sp); sp.loader.exec_module(G)

def utc(): return G.utc()
def mono(): return G.mono()
def info(p): return G.info(p)
def wjson(p,x): return G.write_json(p,x)
def event(p,n,**x): G.append_jsonl(p,{"utc":utc(),"event":n,**x})
def py(script,*args):
    av=[str(PYTHON),"-I","-B","-X","utf8",str(script),*map(str,args)]; r=subprocess.run(av,cwd=str(ROOT),stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8",errors="replace",shell=False,check=False)
    return {"argv":av,"exit_code":int(r.returncode),"stdout":r.stdout,"stderr":r.stderr}
def locked(root):
    lock=json.loads(LOCK.read_text(encoding="utf-8-sig")); rows=[]; ok=True
    for x in lock["files"]:
        p=root/x["path"]; a=info(p); m=bool(a.get("exists") and a.get("bytes")==x["bytes"] and a.get("sha256")==x["sha256"]); ok &= m
        rows.append({"relative_path":x["path"],"expected_bytes":x["bytes"],"expected_sha256":x["sha256"],"actual":a,"matches":m})
    return lock,rows,ok
def baseline():
    allp=G.native_snapshot(); protected=[x for x in allp if int(x.get("pid",-1)) in T10]; other=[x for x in allp if str(x.get("image_name","")).lower() in {"vivado.exe","xsimk.exe","xelab.exe","xvlog.exe"} and int(x.get("pid",-1)) not in T10]
    return {"all_native_processes":allp,"protected":protected,"protected_pids":[int(x["pid"]) for x in protected],"non_reserved_native_processes":other}
def t10_ok(before,after):
    a={int(x["pid"]):str(x.get("image_name","")) for x in after.get("all_native_processes",[])}; b={int(x["pid"]):str(x.get("image_name","")) for x in before.get("all_native_processes",[])}
    ok=all(pid in a and a[pid].lower()==name.lower() for pid,name in T10.items()); return ok,{"before":b,"after":a,"protected_expected":T10}
def freeze(root,attempt,controller,pre,base,mem,lock,rows,lockok):
    cmds={k:[str(VIVADO),"-mode","batch","-source","D:/008_MA_Dev/T11_CFO/vivado/phase74_project.tcl","-log",str(attempt/f"{k}.log"),"-journal",str(attempt/f"{k}.jou"),"-tclargs",k,str(attempt)] for k in ("create","simulate")}
    checks={"source_lock_hash":info(LOCK).get("sha256")==LOCK_SHA,"all_25_locked_files_match":lockok and len(rows)==25,"old_sync_xpr_expected":info(OLD_SYNC).get("sha256")==SYNC_SHA,"old_coord_xpr_expected":info(OLD_COORD).get("sha256")==COORD_SHA,"phase_xpr_absent_before_create":not XPR.exists(),"preflight_rotator_exit_0":pre["rotator"]["exit_code"]==0,"preflight_coordinate_exit_0":pre["coordinate"]["exit_code"]==0,"preflight_phase74_exit_0":pre["phase74"]["exit_code"]==0,"parse_evidence_pass":PARSE.is_file() and json.loads(PARSE.read_text(encoding="utf-8"))["status"]=="PASS","t10_vivado_present":any(int(x.get("pid",-1))==34768 and str(x.get("image_name","")).lower()=="vivado.exe" for x in base["all_native_processes"]),"t10_xsim_present":any(int(x.get("pid",-1))==28856 and str(x.get("image_name","")).lower()=="xsimk.exe" for x in base["all_native_processes"]),"no_other_vivado_or_xsim_process":not base["non_reserved_native_processes"],"free_memory_recommendation":isinstance(mem.get("available_physical_bytes"),int) and mem["available_physical_bytes"]>=FREE}
    return {"schema":"cfo_phase004_execution_freeze_v1","job_id":"CFO-PHASE004","recorded_utc":utc(),"root":str(root),"attempt":str(attempt),"controller":{"path":str(controller),"info":info(controller)},"repaired_telemetry":{"path":str(V3),"info":info(V3),"parse_evidence":{"path":str(PARSE),"info":info(PARSE)},"pointer_size_bytes":G.PTR_SIZE,"pid_stride_bytes":G.PTR_SIZE,"pid_width_bits":G.PTR_SIZE*8,"basic_accounting_information_class":G.JOB_ACCOUNTING},"source_lock":{"path":str(LOCK),"expected_sha256":LOCK_SHA,"actual":info(LOCK),"members":rows,"member_count":len(rows),"all_members_match":lockok,"project_members":lock["project_members"]},"frozen_project":{"part":lock["part"],"hardware_top":lock["hardware_top"],"simulation_top":lock["simulation_top"],"new_xpr":str(XPR),"new_xpr_preexisting":XPR.exists(),"old_sync_xpr":info(OLD_SYNC),"old_sync_xpr_expected_sha256":SYNC_SHA,"old_coord_xpr":info(OLD_COORD),"old_coord_xpr_expected_sha256":COORD_SHA},"dependencies":{str(p):info(p) for p in [DOC,CONTRACT,VP,VC,VR,TCL,THREADS,CONFIG,OLD_SYNC,OLD_COORD]},"tools":{"python":str(PYTHON),"python_version":sys.version,"vivado":str(VIVADO),"vivado_version_declared":"2021.1","vivado_info":info(VIVADO)},"preflight_verification":pre,"preexisting_native_processes":base,"startup_memory":mem,"resources":{"t10_reserved_pids":T10,"max_concurrent_cfo_vivado":1,"matlab_slots":0,"planned_peak_gib_warning":4,"free_recommendation_gib":6,"hard_memory_available_gib":.25,"sustained_memory_available_gib":.5,"sustained_memory_seconds":30,"native_stages_serial":True,"xelab_jobs":16,"general_maxThreads":8,"synth_maxThreads":8},"commands":cmds,"hard_timeouts_seconds":{"create":CREATE,"simulate":SIM,"post_trigger_zero_grace":ZERO},"scope_guards":{"no_t10_operation":True,"no_matlab":True,"no_old_runner":True,"no_normal_error_hold_repeat":True,"no_rotator_repeat":True,"no_coordinate_repeat":True,"no_synthesis":True,"no_implementation":True,"no_fft_or_fullframe":True,"no_auto_restart":True,"no_native_started_before_freeze":True},"checks":checks}
def paths(root,a,stage):
    q=[a/f"{stage}.log",a/f"{stage}.jou",a/f"{stage}.stdout.log",a/f"{stage}.stderr.log",a/f"{stage}_actual_sources.csv",a/f"{stage}_project_identity.txt",a/"phase74_actual.txt",root/"vivado/CFO_PHASE74/CFO_PHASE74.sim/sim_1/behav/xsim/xsim.log",root/"vivado/CFO_PHASE74/CFO_PHASE74.sim/sim_1/behav/xsim/xelab.log",root/"vivado/CFO_PHASE74/CFO_PHASE74.sim/sim_1/behav/xsim/xvlog.log"]
    out=[]; seen=set()
    for p in q:
        if str(p) not in seen: seen.add(str(p)); out.append(p)
    return out
def lines(ps):
    out=[]
    for p in ps:
        try:
            for line in p.read_text(encoding="utf-8",errors="replace").splitlines():
                s=line.strip()
                if s and not s.startswith("#"): out.append({"path":str(p),"line":s})
        except FileNotFoundError: pass
        except Exception as e: out.append({"path":str(p),"line_read_error":repr(e)})
    return out
def marker(ps,prefix):
    for x in lines(ps):
        if x.get("line","").startswith(prefix) and not x.get("line","").startswith("puts "): return {"found":True,**x}
    return {"found":False,"line":None,"path":None}
def marks(root,a,stage):
    ps=paths(root,a,stage); return {"ready":marker(ps,f"CFO_PHASE74_READY action={stage} "),"done":marker(ps,f"CFO_PHASE74_NATIVE_DONE action={stage}"),"passed":marker(ps,"CFO_PHASE74_PASS ")}
def pid(m):
    z=re.search(r"\bpid=(\d+)\b",m.get("line", "")) if m.get("found") else None; return int(z.group(1)) if z else None
def pass_values(m):
    z=re.search(r"^CFO_PHASE74_PASS unique=(\d+) completed=(\d+) protocol_errors=(\d+) max_tail=(\d+) max_total=(\d+) stalled_cycles=(\d+) reset_discards=(\d+) abort_discards=(\d+)",m.get("line","")) if m.get("found") else None
    return dict(zip(("unique","completed","protocol_errors","max_tail","max_total","stalled_cycles","reset_discards","abort_discards"),map(int,z.groups()))) if z else None
def private_bad(tree): return [{"pid":int(x["pid"]),"query_error":x.get("query_error"),"memory_error":x.get("memory_error")} for x in tree if x.get("query_error") or x.get("memory_error")]
def private_sum(c,t,b):
    if c.get("empty_verified"): return 0
    if c.get("issues") or b or len(t)!=len(c.get("pids",[])) or not all(x.get("private_usage_bytes") is not None for x in t): return None
    return sum(int(x["private_usage_bytes"]) for x in t)
def kill(job,r,ep,stage,reason,now):
    if r.get("termination_requested_by_controller"): return None
    try: job.kill(); event(ep,"job_terminate_requested",stage=stage,reason=reason)
    except Exception as e: r["controller_errors"].append({"operation":"TerminateJobObject","error":repr(e)})
    r["termination_requested_by_controller"]=True; r["termination_reason"]=reason; r["events"]["trigger"]=utc(); r["event_mono_ns"]["trigger"]=now; return now+ZERO*1_000_000_000
def stage(root,a,stage,av,limit,ep):
    log=a/f"{stage}.log"; jou=a/f"{stage}.jou"; so=a/f"{stage}.stdout.log"; se=a/f"{stage}.stderr.log"; sm=a/f"{stage}.samples.jsonl"; ps=paths(root,a,stage)
    keys=("create_suspended","job_assigned","launch","ready","trigger","zero"); r={"schema":"cfo_phase004_stage_result_v1","stage":stage,"argv":list(map(str,av)),"command_line":subprocess.list2cmdline(list(map(str,av))),"paths":{"log":str(log),"journal":str(jou),"stdout":str(so),"stderr":str(se),"samples":str(sm)},"binding_succeeded":False,"events":{k:None for k in keys},"event_mono_ns":{k:None for k in keys},"samples_count":0,"telemetry_fault_samples":[],"persistent_telemetry_fault":False,"termination_requested_by_controller":False,"termination_reason":None,"ready_pid":None,"stable_telemetry_samples":0,"unstable_after_ready_samples":0,"controller_errors":[]}
    proc=job=None; deadline=None; low_since=None; badn=0; ready=False; first=True; nexts=None; r["events"]["create_suspended"]=utc(); r["event_mono_ns"]["create_suspended"]=mono(); event(ep,"create_suspended_begin",stage=stage,argv=list(map(str,av)))
    try:
        proc=G.spawn(root,list(map(str,av)),so,se); r["launcher_pid"]=proc.pid; event(ep,"create_suspended_done",stage=stage,launcher_pid=proc.pid); job=G.Job()
        try: job.assign(proc.hp)
        except Exception as e:
            r["binding_error"]=repr(e)
            try: proc.prekill()
            except Exception as ce: r["controller_errors"].append({"operation":"pre_resume_cleanup","error":repr(ce)})
            raise
        r["binding_succeeded"]=True; r["events"]["job_assigned"]=utc(); r["event_mono_ns"]["job_assigned"]=mono(); event(ep,"job_assigned",stage=stage,launcher_pid=proc.pid,kill_on_job_close=True); proc.resume(); start=r["event_mono_ns"]["launch"]=mono(); r["events"]["launch"]=utc(); event(ep,"native_resumed_launch",stage=stage); nexts=start
        while True:
            now=mono(); mk=marks(root,a,stage)
            if mk["ready"]["found"] and not ready:
                ready=True; r["ready_pid"]=pid(mk["ready"]); r["events"]["ready"]=utc(); r["event_mono_ns"]["ready"]=now; event(ep,"native_ready",stage=stage,marker=mk["ready"])
            c=job.census(); ids=c.get("pids",[]); tree=G.snapshot(ids); bad=private_bad(tree); mm=G.mem(); jm=job.extended(); mon=G.detail(os.getpid(),G.table().get(os.getpid())); rd=next((x for x in tree if int(x.get("pid",-1))==int(r.get("ready_pid") or -1)),None)
            stable=bool(ready and r.get("ready_pid") in ids and not c.get("issues") and not c.get("query_errors") and not bad and len(tree)==len(ids) and rd and rd.get("private_usage_bytes") is not None and rd.get("image_path") and rd.get("cpu_time_100ns") is not None)
            if stable: r["stable_telemetry_samples"]+=1
            elif ready: r["unstable_after_ready_samples"]+=1
            isbad=bool(c.get("issues") or c.get("query_errors") or bad)
            if isbad:
                badn+=1
                if len(r["telemetry_fault_samples"])<64: r["telemetry_fault_samples"].append({"utc":utc(),"issues":c.get("issues"),"query_errors":c.get("query_errors"),"process_open_failures":bad})
            else: badn=0
            if first or now>=nexts:
                sample={"utc":utc(),"monotonic_ns":now,"stage":stage,"ready_pid":r.get("ready_pid"),"active_process_count":c.get("active_processes"),"active_process_ids":ids,"active_process_tree":tree,"job_pid_list_count":c.get("listed_processes"),"job_pid_list_assigned_processes":c.get("assigned_processes"),"job_pid_stride_bytes":G.PTR_SIZE,"job_pid_width_bits":G.PTR_SIZE*8,"job_active_accounting":c.get("active_accounting"),"job_pid_cross_check":c.get("pid_cross_check"),"job_census_issues":c.get("issues"),"job_census_error":c.get("query_error"),"job_process_open_failures":bad,"system_memory":mm,"instant_job_private_commit_bytes":private_sum(c,tree,bad),"job_memory":jm,"monitor_private_usage_bytes":mon.get("private_usage_bytes"),"stage_progress":mk,"root_exit_code":proc.exit()}
                try: G.append_jsonl(sm,sample); r["samples_count"]+=1
                except Exception as e: r["controller_errors"].append({"operation":"sample_write","error":repr(e)}); deadline=kill(job,r,ep,stage,"CRITICAL_RESOURCE_RECORDING_FAILURE",now)
                nexts=now+1_000_000_000; first=False
            avl=mm.get("available_physical_bytes")
            if isinstance(avl,int) and avl<HARD and not r["termination_requested_by_controller"]: deadline=kill(job,r,ep,stage,"SEVERE_MEMORY_PRESSURE_IMMEDIATE",now)
            elif isinstance(avl,int) and avl<LOW:
                low_since=low_since or now
                if now-low_since>=30_000_000_000 and not r["termination_requested_by_controller"]: deadline=kill(job,r,ep,stage,"SEVERE_MEMORY_PRESSURE_SUSTAINED_30S",now)
            else: low_since=None
            if badn>=20 and not r["termination_requested_by_controller"]: r["persistent_telemetry_fault"]=True; deadline=kill(job,r,ep,stage,"PERSISTENT_TELEMETRY_FAILURE",now)
            if not r["termination_requested_by_controller"] and now-start>=limit*1_000_000_000: deadline=kill(job,r,ep,stage,f"{stage.upper()}_LAUNCH_HARD_TIMEOUT",now)
            if c.get("empty_verified"):
                r["events"]["zero"]=utc(); r["event_mono_ns"]["zero"]=now; event(ep,"job_zero_triggered" if r["termination_requested_by_controller"] else "job_zero_natural",stage=stage); break
            if r["termination_requested_by_controller"] and deadline is not None and now>deadline: r["zero_deadline_exceeded"]=True; event(ep,"job_zero_deadline_exceeded",stage=stage,active_pids=ids,issues=c.get("issues"),query_errors=c.get("query_errors")); break
            time.sleep(.1)
        r["end_census"]=job.census(); r["active_pids_at_loop_end"]=r["end_census"].get("pids"); r["active_query_error_at_loop_end"]=r["end_census"].get("query_error"); r["job_extended_at_loop_end"]=job.extended(); r["markers"]=marks(root,a,stage); r["native_exit_code"]=proc.exit()
    except Exception as e: r["controller_errors"].append({"operation":"stage_exception","error":repr(e)}); r["status"]="FAIL"; event(ep,"stage_exception",stage=stage,error=repr(e))
    finally:
        if job is not None:
            try:
                c=job.census()
                if not c.get("empty_verified") and not r.get("termination_requested_by_controller"):
                    try: job.kill(); r["termination_requested_by_controller"]=True; r["termination_reason"]=r.get("termination_reason") or "FINALLY_JOB_CLEANUP"
                    except Exception as e: r["controller_errors"].append({"operation":"finally_terminate","error":repr(e)})
                end=mono()+ZERO*1_000_000_000
                while not c.get("empty_verified") and mono()<end: time.sleep(.1); c=job.census()
                r["final_census_before_close"]=c
            except Exception as e: r["controller_errors"].append({"operation":"finally_census","error":repr(e)})
            try: job.close()
            except Exception as e: r["controller_errors"].append({"operation":"job_close","error":repr(e)})
        if proc is not None:
            r["native_exit_code_final"]=proc.exit()
            try: proc.close()
            except Exception as e: r["controller_errors"].append({"operation":"process_close","error":repr(e)})
    r["post_native_processes"]=G.native_snapshot(); r["artifacts"]=[info(p) for p in ps]
    if r["event_mono_ns"].get("trigger") and r["event_mono_ns"].get("ready"): r["ready_to_trigger_seconds"]=(r["event_mono_ns"]["trigger"]-r["event_mono_ns"]["ready"])/1e9
    if r["event_mono_ns"].get("zero") and r["event_mono_ns"].get("trigger"): r["trigger_to_zero_seconds"]=(r["event_mono_ns"]["zero"]-r["event_mono_ns"]["trigger"])/1e9
    if r["event_mono_ns"].get("zero") and r["event_mono_ns"].get("launch"): r["launch_to_zero_seconds"]=(r["event_mono_ns"]["zero"]-r["event_mono_ns"]["launch"])/1e9
    return r
def passed(stage,r):
    m=r.get("markers",{}); f=r.get("final_census_before_close",{}); common=bool(r.get("binding_succeeded") and r.get("events",{}).get("zero") and f.get("empty_verified") and r.get("native_exit_code_final")==0 and not r.get("controller_errors") and not r.get("persistent_telemetry_fault") and not r.get("termination_requested_by_controller") and m.get("ready",{}).get("found") and m.get("done",{}).get("found") and r.get("ready_pid",0)>0 and r.get("stable_telemetry_samples",0)>=2 and r.get("unstable_after_ready_samples",0)<=3)
    if stage=="create": return common
    v=pass_values(m.get("passed",{})); r["raw_pass_values"]=v
    return bool(common and m.get("passed",{}).get("found") and v and v["unique"]==27 and v["completed"]==33 and v["protocol_errors"]==5 and v["stalled_cycles"]==150 and v["reset_discards"]==3 and v["abort_discards"]==3 and v["max_tail"]<=6000 and v["max_total"]<=11000)
def verify(a,stage,actual=False):
    av=[]
    if actual: av += ["--actual",a/"phase74_actual.txt"]
    return py(VP,*av,"--sources",a/f"{stage}_actual_sources.csv","--identity",a/f"{stage}_project_identity.txt")
def parsed(r):
    try:
        x=[z for z in r.get("stdout","").splitlines() if z.strip()]; return json.loads(x[-1]) if x else None
    except Exception: return None
def project_files():
    if not XPR.parent.is_dir(): return []
    return [info(p) for p in sorted(XPR.parent.rglob("*")) if p.is_file() and (p==XPR or p.suffix.lower() in {".log",".jou",".txt",".prj",".pb",".wdb",".wcfg"})]
def artifacts(a):
    rows=[]; seen=set()
    for p in sorted(a.rglob("*")):
        if p.is_file() and p.name!="ATTEMPT_ARTIFACT_MANIFEST.json": rows.append(info(p)); seen.add(str(p))
    rows += [x for x in project_files() if x.get("path") not in seen]; return rows
def complete(a,root,c):
    ch=wjson(a/"ATTEMPT_COMPLETION.json",c); clock=a/"report_clock.json"
    if clock.exists():
        z=json.loads(clock.read_text(encoding="utf-8")); z.update({"status":"COMPLETE","ended_utc":utc(),"final_status":c.get("status")}); wjson(clock,z)
    mh=wjson(a/"ATTEMPT_ARTIFACT_MANIFEST.json",{"schema":"cfo_phase004_artifact_manifest_v1","generated_utc":utc(),"attempt":str(a),"completion_sha256":ch,"artifacts":artifacts(a)})
    return ch,mh
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--root",type=Path,default=ROOT); ap.add_argument("--self-check",action="store_true"); q=ap.parse_args(); root=q.root.resolve()
    if q.self_check:
        c={"root":root.is_dir(),"python":PYTHON.is_file(),"vivado":VIVADO.is_file(),"v3_source":V3.is_file(),"v3_pointer_size":G.PTR_SIZE==8,"v3_accounting_class":G.JOB_ACCOUNTING==1,"v3_census":callable(getattr(G.Job,"census",None)),"phase_tcl":TCL.is_file(),"source_lock":LOCK.is_file(),"phase_verify":VP.is_file(),"no_native_started":True}; print(json.dumps({"schema":"cfo_phase004_controller_self_check_v1","checks":c,"native_started":False})); return 0 if all(c.values()) else 2
    parent=root/"work/CFO_PHASE004"; parent.mkdir(parents=True,exist_ok=True); a=parent/f"attempt_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}_luna"; a.mkdir(); ep=a/"controller_events.jsonl"; wjson(a/"report_clock.json",{"schema":"cfo_phase004_report_clock_v1","thread_id":"01a076f0-d8c0-72a0-8371-cb2ff29c1b28","started_utc":utc(),"interval_minutes":15,"status":"ACTIVE"})
    pre={"rotator":py(VR),"coordinate":py(VC),"phase74":py(VP)}; base=baseline(); mem=G.mem(); lock,rows,lockok=locked(root); fr=freeze(root,a,Path(__file__).resolve(),pre,base,mem,lock,rows,lockok); fsha=wjson(a/"EXECUTION_FREEZE.json",fr); event(ep,"execution_freeze_written",sha256=fsha,checks=fr["checks"])
    if not all(fr["checks"].values()):
        c={"schema":"cfo_phase004_completion_v1","job_id":"CFO-PHASE004","status":"BLOCKED_PREFLIGHT","attempt":str(a),"execution_freeze":{"path":str(a/"EXECUTION_FREEZE.json"),"sha256":fsha},"checks":fr["checks"],"scope_guards":fr["scope_guards"],"post_native_processes":G.native_snapshot(),"repair_audit":[]}; ch,mh=complete(a,root,c); print(json.dumps({"status":c["status"],"attempt":str(a),"completion_sha256":ch,"manifest_sha256":mh})); return 3
    out={}; out["create"]=stage(root,a,"create",fr["commands"]["create"],CREATE,ep); out["create"]["verify"]=verify(a,"create"); out["create"]["verify_json"]=parsed(out["create"]["verify"]); out["create"]["xpr"]=info(XPR); out["create"]["status"]="PASS" if passed("create",out["create"]) and out["create"]["verify"]["exit_code"]==0 and out["create"]["xpr"].get("exists") else "FAIL"; wjson(a/"create_verify.json",out["create"]["verify"]); wjson(a/"create_xpr_audit.json",{"stage":"create","xpr":out["create"]["xpr"]})
    if out["create"]["status"]!="PASS":
        c={"schema":"cfo_phase004_completion_v1","job_id":"CFO-PHASE004","status":"BLOCKED_AFTER_CREATE","attempt":str(a),"generated_utc":utc(),"execution_freeze":{"path":str(a/"EXECUTION_FREEZE.json"),"sha256":fsha},"stages":out,"post_native_processes":G.native_snapshot(),"scope":"Create failed or source/identity verification failed; simulate not started.","t10_not_operated_by_controller":True,"no_matlab":True,"repair_audit":[]}; ch,mh=complete(a,root,c); print(json.dumps({"status":c["status"],"attempt":str(a),"completion_sha256":ch,"manifest_sha256":mh})); return 5
    out["simulate"]=stage(root,a,"simulate",fr["commands"]["simulate"],SIM,ep); out["simulate"]["verify"]=verify(a,"simulate",True); out["simulate"]["verify_json"]=parsed(out["simulate"]["verify"]); out["simulate"]["xpr"]=info(XPR); out["simulate"]["status"]="PASS" if passed("simulate",out["simulate"]) and out["simulate"]["verify"]["exit_code"]==0 else "FAIL"; wjson(a/"simulate_verify.json",out["simulate"]["verify"])
    xa={"schema":"cfo_phase004_xpr_audit_v1","create_xpr":out["create"]["xpr"],"final_xpr":out["simulate"]["xpr"],"sha256_unchanged":out["create"]["xpr"].get("sha256")==out["simulate"]["xpr"].get("sha256")}; xsha=wjson(a/"FINAL_XPR_AUDIT.json",xa); post=G.native_snapshot(); tgood,tdelta=t10_ok(base,{"all_native_processes":post}); pl,pm,pok=locked(root); status="PASS" if all(out[k]["status"]=="PASS" for k in ("create","simulate")) and tgood and pok else "FAIL"
    c={"schema":"cfo_phase004_completion_v1","job_id":"CFO-PHASE004","status":status,"attempt":str(a),"generated_utc":utc(),"execution_freeze":{"path":str(a/"EXECUTION_FREEZE.json"),"sha256":fsha},"stages":out,"final_xpr_audit":{"path":str(a/"FINAL_XPR_AUDIT.json"),"sha256":xsha,**xa},"post_source_lock":{"lock":pl,"members":pm,"all_members_match":pok},"post_native_processes":post,"t10_unchanged":tdelta,"t10_not_operated_by_controller":True,"no_matlab":True,"no_old_runner":True,"no_computation_rerun":True,"no_synthesis_or_implementation":True,"scope":"Only independent CFO_PHASE74 create and behavioral XSim simulate ran serially under private Job objects; no FFT, full-frame, T11/T12/T13, synthesis, timing, or 500MS/s claim.","repair_audit":[]}; ch,mh=complete(a,root,c); print(json.dumps({"status":status,"attempt":str(a),"completion_sha256":ch,"manifest_sha256":mh})); return 0 if status=="PASS" else 6
if __name__=="__main__": raise SystemExit(main())
