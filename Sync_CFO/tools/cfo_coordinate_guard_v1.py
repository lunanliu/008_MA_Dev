#!/usr/bin/env python3
"""CFO-COORD003 native stage supervisor using the repaired GUARD003 Job telemetry."""
from __future__ import annotations
import argparse, datetime as dt, hashlib, importlib.util, json, os, re, subprocess, sys, time
from pathlib import Path

if os.name != "nt":
    raise SystemExit("Windows only")

ROOT=Path(r"D:\008_MA_Dev\T11_CFO")
PYTHON=Path(r"C:\Python314\python.exe")
VIVADO=Path(r"C:\NIFPGA\programs\Vivado2021_1\bin\vivado.bat")
V3_PATH=ROOT/"tools/cfo_native_guard_v3.py"
LOCK=ROOT/"docs/COORD003_SOURCE_LOCK.json"
JOB_DOC=ROOT/"docs/COORDINATE_NATIVE_JOB_003.md"
CONTRACT=ROOT/"docs/COORDINATE_CONTRACT_V1_ZH.md"
VERIFY_COORD=ROOT/"tools/verify_coordinate.py"
VERIFY_ROTATOR=ROOT/"tools/verify_rotator.py"
COORD_TCL=ROOT/"vivado/coordinate_project.tcl"
RUN_THREADS=ROOT/"vivado/run_threads.tcl"
CONFIGURE=ROOT/"vivado/configure_parallel_jobs.tcl"
OLD_XPR=ROOT/"vivado/CFO_SYNC/CFO_SYNC.xpr"
COORD_XPR=ROOT/"vivado/CFO_COORD/CFO_COORD.xpr"
PARSE_EVIDENCE=ROOT/"reports/CFO_GUARD003_PARSE_CHECK_20260914.json"
EXPECTED_LOCK_SHA="21CBAD1DE014FC72341AC3F1BDB161A1A848CADF03A4D302EE964C06B8869B84"
EXPECTED_OLD_XPR_SHA="8EE3459986419C34B42B4261A0E38B2D5C670B47E25E33D80B46074CD4EE8063"
T10_PIDS={34768:"vivado.exe",28856:"xsimk.exe"}
HARD_MEM=int(.25*1024**3)
LOW_MEM=int(.50*1024**3)
FREE_RECOMMENDATION=int(6*1024**3)
HOLD_HARD_SECONDS=60
CREATE_HARD_SECONDS=120
SIMULATE_HARD_SECONDS=300
ZERO_GRACE_SECONDS=5; EXPECTED_CANCEL_EXIT=0xC000013A

spec=importlib.util.spec_from_file_location("cfo_native_guard_v3",V3_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("Unable to load GUARD003 v3")
G=importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)

def utc():
    return G.utc()

def mono():
    return G.mono()

def info(path):
    return G.info(path)

def write_json(path,value):
    return G.write_json(path,value)

def run_python(script,*args):
    argv=[str(PYTHON),"-I","-B","-X","utf8",str(script),*map(str,args)]
    r=subprocess.run(argv,cwd=str(ROOT),stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8",errors="replace",shell=False,check=False)
    return {"argv":argv,"exit_code":int(r.returncode),"stdout":r.stdout,"stderr":r.stderr}

def event(path,name,**data):
    G.append_jsonl(path,{"utc":utc(),"event":name,**data})

def output_lines(paths):
    rows=[]
    for path in paths:
        try:
            for line in path.read_text(encoding="utf-8",errors="replace").splitlines():
                stripped=line.strip()
                if stripped and not stripped.startswith("#"):
                    rows.append({"path":str(path),"line":stripped})
        except FileNotFoundError:
            pass
        except Exception as e:
            rows.append({"path":str(path),"line_read_error":repr(e)})
    return rows

def first_marker(paths,prefix):
    for row in output_lines(paths):
        line=row.get("line","")
        if line.startswith(prefix) and not line.startswith("puts "):
            return {"found":True,**row}
    return {"found":False,"line":None,"path":None}

def stage_markers(stage,paths):
    if stage=="hold":
        ready=first_marker(paths,"CFO_GUARD_READY mode=hold ")
        done={"found":False}
        passed={"found":False}
    else:
        ready=first_marker(paths,f"CFO_COORD_READY action={stage} ")
        done=first_marker(paths,f"CFO_COORD_NATIVE_DONE action={stage}")
        passed=first_marker(paths,"CFO_COORD_PASS ")
    return {"ready":ready,"done":done,"passed":passed}

def parse_pid(marker):
    if not marker.get("found"):
        return None
    m=re.search(r"\bpid=(\d+)\b",marker.get("line",""))
    return int(m.group(1)) if m else None

def private_failures(tree):
    return [{"pid":int(x["pid"]),"query_error":x.get("query_error"),"memory_error":x.get("memory_error")} for x in tree if x.get("query_error") or x.get("memory_error")]

def private_sum(census,tree,failures):
    if census.get("empty_verified"):
        return 0
    if census.get("issues") or failures or len(tree)!=len(census.get("pids",[])):
        return None
    if not all(x.get("private_usage_bytes") is not None for x in tree):
        return None
    return sum(int(x["private_usage_bytes"]) for x in tree)

def identity_check():
    return {"rotator":run_python(VERIFY_ROTATOR),"coordinate":run_python(VERIFY_COORD)}

def locked_inputs(root):
    lock=json.loads(LOCK.read_text(encoding="utf-8-sig"))
    members=[]
    okay=True
    for item in lock["files"]:
        p=root/item["path"]
        actual=info(p)
        record={"relative_path":item["path"],"expected_bytes":item["bytes"],"expected_sha256":item["sha256"],"actual":actual}
        record["matches"]=bool(actual.get("exists") and actual.get("bytes")==item["bytes"] and actual.get("sha256")==item["sha256"])
        okay=okay and record["matches"]
        members.append(record)
    return lock,members,okay

def t10_baseline():
    snap=G.native_snapshot()
    protected=[x for x in snap if int(x.get("pid",-1)) in T10_PIDS]
    return {"all_native_processes":snap,"protected":protected,"protected_pids":[int(x["pid"]) for x in protected]}

def t10_unchanged(before,after):
    def by_pid(items):
        return {int(x["pid"]):{"image_name":x.get("image_name"),"parent_pid":x.get("parent_pid")} for x in items}
    b=by_pid(before.get("all_native_processes",[])); a=by_pid(after.get("all_native_processes",[]))
    return all(pid in a and a[pid]["image_name"].lower()==name.lower() for pid,name in T10_PIDS.items()),{"before":b,"after":a,"protected_expected":T10_PIDS}

def build_freeze(root,attempt,controller,preflight,baseline,mem_snapshot,lock,members,lock_ok):
    return {
        "schema":"cfo_coord003_execution_freeze_v1",
        "job_id":"CFO-COORD003",
        "recorded_utc":utc(),
        "root":str(root),
        "attempt":str(attempt),
        "controller":{"path":str(controller),"info":info(controller)},
        "repaired_telemetry":{"path":str(V3_PATH),"info":info(V3_PATH),"parse_evidence":{"path":str(PARSE_EVIDENCE),"info":info(PARSE_EVIDENCE)},"pointer_size_bytes":G.PTR_SIZE,"pid_stride_bytes":G.PTR_SIZE,"pid_width_bits":G.PTR_SIZE*8,"basic_accounting_information_class":G.JOB_ACCOUNTING},
        "source_lock":{"path":str(LOCK),"expected_sha256":EXPECTED_LOCK_SHA,"actual":info(LOCK),"members":members,"member_count":len(members),"all_members_match":lock_ok,"project_members":lock["project_members"]},
        "frozen_project":{"part":lock["part"],"hardware_top":lock["hardware_top"],"simulation_top":lock["simulation_top"],"new_xpr":str(COORD_XPR),"new_xpr_preexisting":COORD_XPR.is_file(),"old_xpr":info(OLD_XPR),"old_xpr_expected_sha256":EXPECTED_OLD_XPR_SHA},
        "dependencies":{str(p):info(p) for p in [JOB_DOC,CONTRACT,VERIFY_COORD,VERIFY_ROTATOR,COORD_TCL,RUN_THREADS,CONFIGURE,OLD_XPR]},
        "tools":{"python":str(PYTHON),"python_version":sys.version,"vivado":str(VIVADO),"vivado_version_declared":"2021.1","vivado_info":info(VIVADO)},
        "preflight_verification":preflight,
        "preexisting_native_processes":baseline,
        "startup_memory":mem_snapshot,
        "resources":{"t10_reserved_pids":T10_PIDS,"max_concurrent_cfo_vivado":1,"matlab_slots":0,"planned_peak_gib_warning":4,"free_recommendation_gib":6,"hard_memory_available_gib":.25,"sustained_memory_available_gib":.50,"sustained_memory_seconds":30,"native_stages_serial":True,"xelab_jobs":16,"general_maxThreads":8,"synth_maxThreads":8},
        "commands":{
            "hold":[str(VIVADO),"-mode","batch","-source","D:/008_MA_Dev/T11_CFO/vivado/guard_probe_v2.tcl","-log",str(attempt/"hold.log"),"-journal",str(attempt/"hold.jou"),"-tclargs","hold"],
            "create":[str(VIVADO),"-mode","batch","-source","D:/008_MA_Dev/T11_CFO/vivado/coordinate_project.tcl","-log",str(attempt/"create.log"),"-journal",str(attempt/"create.jou"),"-tclargs","create",str(attempt)],
            "simulate":[str(VIVADO),"-mode","batch","-source","D:/008_MA_Dev/T11_CFO/vivado/coordinate_project.tcl","-log",str(attempt/"simulate.log"),"-journal",str(attempt/"simulate.jou"),"-tclargs","simulate",str(attempt)]
        },
        "hard_timeouts_seconds":{"hold":HOLD_HARD_SECONDS,"create":CREATE_HARD_SECONDS,"simulate":SIMULATE_HARD_SECONDS,"post_trigger_zero_grace":ZERO_GRACE_SECONDS},
        "scope_guards":{"no_t10_operation":True,"no_matlab":True,"no_old_runner":True,"no_old_normal_error_repeat":True,"no_rotator_repeat":True,"no_synthesis":True,"no_implementation":True,"no_auto_restart":True,"no_native_started_before_freeze":True},
        "checks":{
            "source_lock_hash":info(LOCK).get("sha256")==EXPECTED_LOCK_SHA,
            "all_18_locked_files_match":lock_ok,
            "old_xpr_expected":info(OLD_XPR).get("sha256")==EXPECTED_OLD_XPR_SHA,
            "coordinate_xpr_absent_before_create":not COORD_XPR.exists(),
            "preflight_rotator_exit_0":preflight["rotator"]["exit_code"]==0,
            "preflight_coordinate_exit_0":preflight["coordinate"]["exit_code"]==0,
            "parse_evidence_pass":json.loads(PARSE_EVIDENCE.read_text(encoding="utf-8"))["status"]=="PASS" if PARSE_EVIDENCE.is_file() else False,
            "t10_vivado_present":any(int(x.get("pid",-1))==34768 and x.get("image_name","").lower()=="vivado.exe" for x in baseline["all_native_processes"]),
            "t10_xsim_present":any(int(x.get("pid",-1))==28856 and x.get("image_name","").lower()=="xsimk.exe" for x in baseline["all_native_processes"]),
            "free_memory_recommendation":isinstance(mem_snapshot.get("available_physical_bytes"),int) and mem_snapshot["available_physical_bytes"]>=FREE_RECOMMENDATION
        }
    }

def run_stage(root,attempt,stage,argv,hard_seconds,events_path):
    log=attempt/f"{stage}.log"; journal=attempt/f"{stage}.jou"; stdout=attempt/f"{stage}.stdout.log"; stderr=attempt/f"{stage}.stderr.log"; samples=attempt/f"{stage}.samples.jsonl"
    paths=[log,stdout,stderr]
    result={"schema":"cfo_coord003_stage_result_v1","stage":stage,"argv":list(map(str,argv)),"command_line":subprocess.list2cmdline(list(map(str,argv))),"paths":{"log":str(log),"journal":str(journal),"stdout":str(stdout),"stderr":str(stderr),"samples":str(samples)},"binding_succeeded":False,"events":{"create_suspended":None,"job_assigned":None,"launch":None,"ready":None,"trigger":None,"zero":None},"event_mono_ns":{"create_suspended":None,"job_assigned":None,"launch":None,"ready":None,"trigger":None,"zero":None},"samples_count":0,"telemetry_fault_samples":[],"persistent_telemetry_fault":False,"termination_requested_by_controller":False,"termination_reason":None,"ready_pid":None,"stable_telemetry_samples":0,"unstable_after_ready_samples":0,"controller_errors":[]}
    proc=None;job=None;triggered=False;zero_deadline=None;low_since=None;consecutive_bad=0;ready_line_seen=None;stable_count=0
    result["events"]["create_suspended"]=utc();result["event_mono_ns"]["create_suspended"]=mono();event(events_path,"create_suspended_begin",stage=stage,argv=list(map(str,argv)))
    def request_kill(reason,now):
        nonlocal triggered,zero_deadline
        if triggered:
            return
        try:
            job.kill()
            event(events_path,"job_terminate_requested",stage=stage,reason=reason)
        except Exception as e:
            result["controller_errors"].append({"operation":"TerminateJobObject","error":repr(e)})
            event(events_path,"job_terminate_error",stage=stage,reason=reason,error=repr(e))
        triggered=True;result["termination_requested_by_controller"]=True;result["termination_reason"]=reason;result["events"]["trigger"]=utc();result["event_mono_ns"]["trigger"]=now;zero_deadline=now+int(ZERO_GRACE_SECONDS*1e9)
    try:
        proc=G.spawn(root,list(map(str,argv)),stdout,stderr)
        result["launcher_pid"]=proc.pid
        event(events_path,"create_suspended_done",stage=stage,launcher_pid=proc.pid)
        job=G.Job()
        try:
            job.assign(proc.hp)
        except Exception as e:
            result["binding_error"]=repr(e);event(events_path,"job_binding_failed",stage=stage,error=repr(e))
            try: proc.prekill()
            except Exception as x: result["controller_errors"].append({"operation":"pre_resume_cleanup","error":repr(x)})
            raise
        result["binding_succeeded"]=True;result["events"]["job_assigned"]=utc();result["event_mono_ns"]["job_assigned"]=mono();event(events_path,"job_assigned",stage=stage,launcher_pid=proc.pid,kill_on_job_close=True)
        proc.resume();start=result["event_mono_ns"]["launch"]=mono();result["events"]["launch"]=utc();event(events_path,"native_resumed_launch",stage=stage)
        next_sample=start;first=True;ready=False;next_marker_poll=start;hold_ready_pid=None
        while True:
            now=mono()
            mk=stage_markers(stage,paths)
            if mk["ready"]["found"] and not ready:
                ready=True;ready_line_seen=mk["ready"];result["ready_pid"]=parse_pid(mk["ready"]);hold_ready_pid=result["ready_pid"];result["events"]["ready"]=utc();result["event_mono_ns"]["ready"]=now;event(events_path,"native_ready",stage=stage,marker=ready_line_seen)
            census=job.census();pids=census.get("pids",[]);tree=G.snapshot(pids);failures=private_failures(tree);mm=G.mem();ji=job.extended();mon=G.detail(os.getpid(),G.table().get(os.getpid()))
            ready_detail=next((x for x in tree if int(x.get("pid",-1))==int(hold_ready_pid)),None) if hold_ready_pid is not None else None
            stable=bool(ready and hold_ready_pid is not None and hold_ready_pid in pids and not census.get("issues") and not census.get("query_errors") and not failures and len(tree)==len(pids) and ready_detail and ready_detail.get("private_usage_bytes") is not None and ready_detail.get("image_path") and ready_detail.get("cpu_time_100ns") is not None)
            if stable: stable_count+=1;result["stable_telemetry_samples"]=stable_count
            elif ready: result["unstable_after_ready_samples"]+=1
            bad=bool(census.get("issues") or census.get("query_errors") or failures)
            if bad:
                consecutive_bad+=1
                if len(result["telemetry_fault_samples"])<64: result["telemetry_fault_samples"].append({"utc":utc(),"issues":census.get("issues"),"query_errors":census.get("query_errors"),"process_open_failures":failures})
            else: consecutive_bad=0
            if first or now>=next_sample:
                sm={"utc":utc(),"monotonic_ns":now,"stage":stage,"ready_pid":hold_ready_pid,"active_process_count":census.get("active_processes"),"active_process_ids":pids,"active_process_tree":tree,"job_pid_list_count":census.get("listed_processes"),"job_pid_list_assigned_processes":census.get("assigned_processes"),"job_pid_stride_bytes":G.PTR_SIZE,"job_pid_width_bits":G.PTR_SIZE*8,"job_active_accounting":census.get("active_accounting"),"job_pid_cross_check":census.get("pid_cross_check"),"job_census_issues":census.get("issues"),"job_census_error":census.get("query_error"),"job_process_open_failures":failures,"system_memory":mm,"instant_job_private_commit_bytes":private_sum(census,tree,failures),"job_memory":ji,"monitor_private_usage_bytes":mon.get("private_usage_bytes"),"stage_progress":mk,"root_exit_code":proc.exit()}
                try:G.append_jsonl(samples,sm);result["samples_count"]+=1
                except Exception as e:
                    result["controller_errors"].append({"operation":"sample_write","error":repr(e)});event(events_path,"critical_sample_write_failure",stage=stage,error=repr(e))
                    request_kill("CRITICAL_RESOURCE_RECORDING_FAILURE",now)
                next_sample=now+1_000_000_000;first=False
            av=mm.get("available_physical_bytes")
            if isinstance(av,int) and av<HARD_MEM and not triggered: request_kill("SEVERE_MEMORY_PRESSURE_IMMEDIATE",now)
            elif isinstance(av,int) and av<LOW_MEM:
                low_since=low_since or now
                if now-low_since>=30_000_000_000 and not triggered: request_kill("SEVERE_MEMORY_PRESSURE_SUSTAINED_30S",now)
            else: low_since=None
            if not triggered and consecutive_bad>=20:
                result["persistent_telemetry_fault"]=True;request_kill("PERSISTENT_TELEMETRY_FAILURE",now)
            if stage=="hold" and ready and not triggered and now-result["event_mono_ns"]["ready"]>=3_000_000_000:
                request_kill("HOLD_READY_PLUS_3S",now)
            root_exit=proc.exit()
            if not triggered and now-start>=int(hard_seconds*1e9):
                request_kill(f"{stage.upper()}_LAUNCH_HARD_TIMEOUT",now)
            if triggered and census.get("empty_verified"):
                result["events"]["zero"]=utc();result["event_mono_ns"]["zero"]=now;event(events_path,"job_zero",stage=stage);break
            if not triggered and root_exit is not None and census.get("empty_verified"):
                result["events"]["zero"]=utc();result["event_mono_ns"]["zero"]=now;result["event_mono_ns"]["zero"]=now;event(events_path,"job_zero_natural",stage=stage);break
            if triggered and zero_deadline is not None and now>zero_deadline:
                result["zero_deadline_exceeded"]=True;event(events_path,"job_zero_deadline_exceeded",stage=stage,active_pids=pids,issues=census.get("issues"),query_errors=census.get("query_errors"));break
            time.sleep(.1)
        end=job.census();result["end_census"]=end;result["active_pids_at_loop_end"]=end.get("pids");result["active_query_error_at_loop_end"]=end.get("query_error");result["job_extended_at_loop_end"]=job.extended();result["markers"]=stage_markers(stage,paths);result["native_exit_code"]=proc.exit()
    except Exception as e:
        result["controller_errors"].append({"operation":"stage_exception","error":repr(e)});result["status"]="FAIL";event(events_path,"stage_exception",stage=stage,error=repr(e))
    finally:
        if job is not None:
            try:
                c=job.census()
                if not c.get("empty_verified") and not result.get("termination_requested_by_controller"):
                    try: job.kill();result["termination_requested_by_controller"]=True;result["termination_reason"]=result.get("termination_reason") or "FINALLY_JOB_CLEANUP"
                    except Exception as e: result["controller_errors"].append({"operation":"finally_terminate","error":repr(e)})
                deadline=mono()+int(ZERO_GRACE_SECONDS*1e9)
                while not c.get("empty_verified") and mono()<deadline:
                    time.sleep(.1);c=job.census()
                result["final_census_before_close"]=c
            except Exception as e:
                result["controller_errors"].append({"operation":"finally_census","error":repr(e)})
            try:job.close()
            except Exception as e:result["controller_errors"].append({"operation":"job_close","error":repr(e)})
        if proc is not None:
            result["native_exit_code_final"]=proc.exit()
            try:proc.close()
            except Exception as e:result["controller_errors"].append({"operation":"process_close","error":repr(e)})
    result["post_native_processes"]=G.native_snapshot()
    result["artifacts"]=[info(p) for p in [log,journal,stdout,stderr,samples]]
    if result.get("event_mono_ns",{}).get("trigger") and result.get("event_mono_ns",{}).get("ready"):
        result["ready_to_trigger_seconds"]=(result["event_mono_ns"]["trigger"]-result["event_mono_ns"]["ready"])/1e9
    if result.get("event_mono_ns",{}).get("zero") and result.get("event_mono_ns",{}).get("trigger"):
        result["trigger_to_zero_seconds"]=(result["event_mono_ns"]["zero"]-result["event_mono_ns"]["trigger"])/1e9
    if result.get("event_mono_ns",{}).get("zero") and result.get("event_mono_ns",{}).get("launch"):
        result["launch_to_zero_seconds"]=(result["event_mono_ns"]["zero"]-result["event_mono_ns"]["launch"])/1e9
    return result

def stage_pass(stage,r):
    m=r.get("markers",{})
    basic=bool(r.get("binding_succeeded") and r.get("events",{}).get("zero") and r.get("final_census_before_close",{}).get("empty_verified") and not r.get("controller_errors") and not r.get("persistent_telemetry_fault"))
    if stage=="hold":
        timing=bool(r.get("ready_to_trigger_seconds") is not None and 3<=r["ready_to_trigger_seconds"]<=4.5 and r.get("trigger_to_zero_seconds") is not None and r["trigger_to_zero_seconds"]<=ZERO_GRACE_SECONDS and r.get("launch_to_zero_seconds") is not None and r["launch_to_zero_seconds"]<=65)
        return bool(basic and m.get("ready",{}).get("found") and r.get("ready_pid",0)>0 and r.get("termination_reason")=="HOLD_READY_PLUS_3S" and r.get("native_exit_code_final")==EXPECTED_CANCEL_EXIT and timing and r.get("stable_telemetry_samples",0)>=2)
    return bool(basic and m.get("ready",{}).get("found") and m.get("done",{}).get("found") and r.get("native_exit_code_final")==0 and r.get("unstable_after_ready_samples",0)<=3)
def verify_coordinate(attempt,stage,actual=False):
    args=[]
    if actual: args += ["--actual",attempt/"coordinate_actual.txt"]
    args += ["--sources",attempt/f"{stage}_actual_sources.csv","--identity",attempt/f"{stage}_project_identity.txt"]
    return run_python(VERIFY_COORD,*args)

def artifact_manifest(attempt):
    rows=[]
    for p in sorted(attempt.rglob("*")):
        if p.is_file() and p.name!="ATTEMPT_ARTIFACT_MANIFEST.json":
            rows.append(info(p))
    return rows

def complete(attempt,payload):
    ch=write_json(attempt/"ATTEMPT_COMPLETION.json",payload)
    clock=attempt/"report_clock.json"
    if clock.exists():
        c=json.loads(clock.read_text(encoding="utf-8"));c.update({"status":"COMPLETE","ended_utc":utc(),"final_status":payload.get("status")});write_json(clock,c)
    manifest={"schema":"cfo_coord003_artifact_manifest_v1","generated_utc":utc(),"attempt":str(attempt),"completion_sha256":ch,"artifacts":artifact_manifest(attempt)}
    mh=write_json(attempt/"ATTEMPT_ARTIFACT_MANIFEST.json",manifest)
    return ch,mh

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",type=Path,default=ROOT);ap.add_argument("--self-check",action="store_true");a=ap.parse_args();root=a.root.resolve()
    if a.self_check:
        checks={"v3_source":V3_PATH.is_file(),"ptr_size":G.PTR_SIZE==8,"accounting_class":G.JOB_ACCOUNTING==1,"census":callable(getattr(G.Job,"census",None)),"coordinate_tcl":COORD_TCL.is_file(),"source_lock":LOCK.is_file(),"no_native_started":True}
        print(json.dumps({"schema":"cfo_coord003_controller_self_check_v1","checks":checks,"native_started":False}));return 0 if all(checks.values()) else 2
    parent=root/"work/CFO_COORD003";parent.mkdir(parents=True,exist_ok=True);attempt=parent/f"attempt_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}_luna";attempt.mkdir()
    events_path=attempt/"controller_events.jsonl";write_json(attempt/"report_clock.json",{"schema":"cfo_coord003_report_clock_v1","thread_id":"01a076f0-d8c0-72a0-8371-cb2ff29c1b28","started_utc":utc(),"interval_minutes":15,"status":"ACTIVE"})
    preflight=identity_check();baseline=t10_baseline();mem_snapshot=G.mem();lock,members,lock_ok=locked_inputs(root)
    freeze=build_freeze(root,attempt,Path(__file__).resolve(),preflight,baseline,mem_snapshot,lock,members,lock_ok);freeze_sha=write_json(attempt/"EXECUTION_FREEZE.json",freeze);event(events_path,"execution_freeze_written",sha256=freeze_sha,checks=freeze["checks"])
    if not all(freeze["checks"].values()):
        c={"schema":"cfo_coord003_completion_v1","job_id":"CFO-COORD003","status":"BLOCKED_PREFLIGHT","attempt":str(attempt),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":freeze_sha},"checks":freeze["checks"],"scope_guards":freeze["scope_guards"]}
        ch,mh=complete(attempt,c);print(json.dumps({"status":c["status"],"attempt":str(attempt),"completion_sha256":ch,"manifest_sha256":mh}));return 3
    results={}
    hold_argv=freeze["commands"]["hold"];results["hold"]=run_stage(root,attempt,"hold",hold_argv,HOLD_HARD_SECONDS,events_path);results["hold"]["status"]="PASS" if stage_pass("hold",results["hold"]) else "FAIL"
    if results["hold"]["status"]!="PASS":
        c={"schema":"cfo_coord003_completion_v1","job_id":"CFO-COORD003","status":"BLOCKED_AFTER_HOLD","attempt":str(attempt),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":freeze_sha},"stages":results,"post_native_processes":G.native_snapshot(),"scope":"Hold telemetry probe failed; create/simulate not started.","t10_not_operated_by_controller":True,"no_matlab":True}
        ch,mh=complete(attempt,c);print(json.dumps({"status":c["status"],"attempt":str(attempt),"completion_sha256":ch,"manifest_sha256":mh}));return 4
    create_argv=freeze["commands"]["create"];results["create"]=run_stage(root,attempt,"create",create_argv,CREATE_HARD_SECONDS,events_path);results["create"]["coordinate_verify"]=verify_coordinate(attempt,"create",False);results["create"]["xpr"]=info(COORD_XPR);results["create"]["status"]="PASS" if stage_pass("create",results["create"]) and results["create"]["coordinate_verify"]["exit_code"]==0 else "FAIL"
    write_json(attempt/"create_verify.json",results["create"]["coordinate_verify"])
    if results["create"]["status"]!="PASS":
        c={"schema":"cfo_coord003_completion_v1","job_id":"CFO-COORD003","status":"BLOCKED_AFTER_CREATE","attempt":str(attempt),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":freeze_sha},"stages":results,"post_native_processes":G.native_snapshot(),"scope":"Create failed or source identity/project-member verification failed; simulate not started.","t10_not_operated_by_controller":True,"no_matlab":True}
        ch,mh=complete(attempt,c);print(json.dumps({"status":c["status"],"attempt":str(attempt),"completion_sha256":ch,"manifest_sha256":mh}));return 5
    sim_argv=freeze["commands"]["simulate"];results["simulate"]=run_stage(root,attempt,"simulate",sim_argv,SIMULATE_HARD_SECONDS,events_path);results["simulate"]["coordinate_verify"]=verify_coordinate(attempt,"simulate",True);results["simulate"]["status"]="PASS" if stage_pass("simulate",results["simulate"]) and results["simulate"]["coordinate_verify"]["exit_code"]==0 and results["simulate"]["markers"].get("passed",{}).get("found") else "FAIL"
    write_json(attempt/"simulate_verify.json",results["simulate"]["coordinate_verify"])
    post=G.native_snapshot();t10_ok,t10_delta=t10_unchanged(baseline,{"all_native_processes":post})
    status="PASS" if all(results[x]["status"]=="PASS" for x in ("hold","create","simulate")) and t10_ok else "FAIL"
    c={"schema":"cfo_coord003_completion_v1","job_id":"CFO-COORD003","status":status,"attempt":str(attempt),"generated_utc":utc(),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":freeze_sha},"stages":results,"post_native_processes":post,"t10_unchanged":t10_delta,"t10_not_operated_by_controller":True,"no_matlab":True,"no_old_runner":True,"no_computation_rerun":True,"no_synthesis_or_implementation":True,"scope":"One repaired hold telemetry probe followed by one independent CFO_COORD create and one behavioral XSim simulate, serially, under private Job objects."}
    ch,mh=complete(attempt,c);print(json.dumps({"status":status,"attempt":str(attempt),"completion_sha256":ch,"manifest_sha256":mh}));return 0 if status=="PASS" else 6

if __name__=="__main__":
    raise SystemExit(main())
