#!/usr/bin/env python3
"""CFO-GUARD003: private Windows Job-object supervisor for frozen native probes."""
from __future__ import annotations
import argparse, ctypes, ctypes.wintypes as w, datetime as dt, hashlib, json, os, re, subprocess, sys, time
from pathlib import Path
from typing import Any

if os.name != "nt": raise SystemExit("Windows only")
ROOT=Path(r"D:\008_MA_Dev\T11_CFO"); VIVADO=Path(r"C:\NIFPGA\programs\Vivado2021_1\bin\vivado.bat"); PYTHON=Path(r"C:\Python314\python.exe")
PROBE=Path("vivado/guard_probe_v2.tcl"); XPR=Path("vivado/CFO_SYNC/CFO_SYNC.xpr"); VERIFY=Path("tools/verify_rotator.py")
LOCK=Path("docs/GUARD002_SOURCE_LOCK.json"); BASE_LOCK=Path("docs/ROTATOR_SOURCE_LOCK.json"); JOBDOC=Path("docs/GUARD_NATIVE_JOB_002.md"); REVIEW=Path("reports/CFO_NATIVE001_REVIEW_20260914/INDEPENDENT_REVIEW.json")
MODES=("normal","error","hold"); EXPECTED_XPR="8EE3459986419C34B42B4261A0E38B2D5C670B47E25E33D80B46074CD4EE8063"
CREATE_SUSPENDED=4; CREATE_UNICODE=0x400; CREATE_NO_WINDOW=0x08000000; USE_STD=0x100; KILL_ON_CLOSE=0x2000
JOB_EXT=9; JOB_PIDS=3; JOB_ACCOUNTING=1; PTR_SIZE=ctypes.sizeof(ctypes.c_size_t); ERROR_INSUFFICIENT_BUFFER=122; ERROR_MORE_DATA=234; MAX_PID_LIST_BYTES=8+PTR_SIZE*65536; SNAP=2; QLIMIT=0x1000; VMREAD=0x10; SYNC=0x100000; STILL=259; INHERIT=1
HARD_MEM=int(.25*1024**3); LOW_MEM=int(.50*1024**3)

class FT(ctypes.Structure): _fields_=[("lo",w.DWORD),("hi",w.DWORD)]
class MEM(ctypes.Structure): _fields_=[("n",w.DWORD),("load",w.DWORD),("total",ctypes.c_ulonglong),("avail",ctypes.c_ulonglong),("tp",ctypes.c_ulonglong),("ap",ctypes.c_ulonglong),("tv",ctypes.c_ulonglong),("av",ctypes.c_ulonglong),("ae",ctypes.c_ulonglong)]
class IO(ctypes.Structure): _fields_=[("a",ctypes.c_ulonglong),("b",ctypes.c_ulonglong),("c",ctypes.c_ulonglong),("d",ctypes.c_ulonglong),("e",ctypes.c_ulonglong),("f",ctypes.c_ulonglong)]
class JBASE(ctypes.Structure): _fields_=[("a",ctypes.c_longlong),("b",ctypes.c_longlong),("flags",w.DWORD),("c",ctypes.c_size_t),("d",ctypes.c_size_t),("e",w.DWORD),("f",ctypes.c_size_t),("g",w.DWORD),("h",w.DWORD)]
class JEXT(ctypes.Structure): _fields_=[("base",JBASE),("io",IO),("pml",ctypes.c_size_t),("jml",ctypes.c_size_t),("ppm",ctypes.c_size_t),("pjm",ctypes.c_size_t)]
class JACCOUNTING(ctypes.Structure): _fields_=[("total_user_time",ctypes.c_longlong),("total_kernel_time",ctypes.c_longlong),("this_period_total_user_time",ctypes.c_longlong),("this_period_total_kernel_time",ctypes.c_longlong),("total_page_fault_count",w.DWORD),("total_processes",w.DWORD),("active_processes",w.DWORD),("total_terminated_processes",w.DWORD)]
class PMC(ctypes.Structure): _fields_=[("cb",w.DWORD),("pf",w.DWORD),("pws",ctypes.c_size_t),("ws",ctypes.c_size_t),("qpp",ctypes.c_size_t),("qp",ctypes.c_size_t),("qpn",ctypes.c_size_t),("qn",ctypes.c_size_t),("pfu",ctypes.c_size_t),("ppfu",ctypes.c_size_t),("private",ctypes.c_size_t)]
class SI(ctypes.Structure): _fields_=[("cb",w.DWORD),("r",w.LPWSTR),("d",w.LPWSTR),("t",w.LPWSTR),("x",w.DWORD),("y",w.DWORD),("xs",w.DWORD),("ys",w.DWORD),("xc",w.DWORD),("yc",w.DWORD),("fill",w.DWORD),("flags",w.DWORD),("show",w.WORD),("r2",w.WORD),("p",ctypes.POINTER(ctypes.c_ubyte)),("hin",w.HANDLE),("hout",w.HANDLE),("herr",w.HANDLE)]
class PI(ctypes.Structure): _fields_=[("hp",w.HANDLE),("ht",w.HANDLE),("pid",w.DWORD),("tid",w.DWORD)]
class PE(ctypes.Structure): _fields_=[("size",w.DWORD),("u",w.DWORD),("pid",w.DWORD),("heap",ctypes.c_void_p),("mod",w.DWORD),("threads",w.DWORD),("ppid",w.DWORD),("pri",ctypes.c_long),("flags",w.DWORD),("image",w.WCHAR*260)]
k=ctypes.WinDLL("kernel32",use_last_error=True); p=ctypes.WinDLL("psapi",use_last_error=True)
k.CreateJobObjectW.argtypes=[ctypes.c_void_p,w.LPCWSTR]; k.CreateJobObjectW.restype=w.HANDLE
k.SetInformationJobObject.argtypes=[w.HANDLE,w.DWORD,ctypes.c_void_p,w.DWORD]; k.SetInformationJobObject.restype=w.BOOL
k.QueryInformationJobObject.argtypes=[w.HANDLE,w.DWORD,ctypes.c_void_p,w.DWORD,ctypes.POINTER(w.DWORD)]; k.QueryInformationJobObject.restype=w.BOOL
k.AssignProcessToJobObject.argtypes=[w.HANDLE,w.HANDLE]; k.AssignProcessToJobObject.restype=w.BOOL
k.TerminateJobObject.argtypes=[w.HANDLE,w.UINT]; k.TerminateJobObject.restype=w.BOOL
k.CloseHandle.argtypes=[w.HANDLE]; k.CloseHandle.restype=w.BOOL
k.CreateProcessW.argtypes=[w.LPCWSTR,w.LPWSTR,ctypes.c_void_p,ctypes.c_void_p,w.BOOL,w.DWORD,ctypes.c_void_p,w.LPCWSTR,ctypes.POINTER(SI),ctypes.POINTER(PI)]; k.CreateProcessW.restype=w.BOOL
k.ResumeThread.argtypes=[w.HANDLE]; k.ResumeThread.restype=w.DWORD
k.TerminateProcess.argtypes=[w.HANDLE,w.UINT]; k.TerminateProcess.restype=w.BOOL
k.GetExitCodeProcess.argtypes=[w.HANDLE,ctypes.POINTER(w.DWORD)]; k.GetExitCodeProcess.restype=w.BOOL
k.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD]; k.OpenProcess.restype=w.HANDLE
k.SetHandleInformation.argtypes=[w.HANDLE,w.DWORD,w.DWORD]; k.SetHandleInformation.restype=w.BOOL
k.GlobalMemoryStatusEx.argtypes=[ctypes.POINTER(MEM)]; k.GlobalMemoryStatusEx.restype=w.BOOL
k.GetProcessTimes.argtypes=[w.HANDLE,ctypes.POINTER(FT),ctypes.POINTER(FT),ctypes.POINTER(FT),ctypes.POINTER(FT)]; k.GetProcessTimes.restype=w.BOOL
k.QueryFullProcessImageNameW.argtypes=[w.HANDLE,w.DWORD,w.LPWSTR,ctypes.POINTER(w.DWORD)]; k.QueryFullProcessImageNameW.restype=w.BOOL
k.CreateToolhelp32Snapshot.argtypes=[w.DWORD,w.DWORD]; k.CreateToolhelp32Snapshot.restype=w.HANDLE
k.Process32FirstW.argtypes=[w.HANDLE,ctypes.POINTER(PE)]; k.Process32FirstW.restype=w.BOOL
k.Process32NextW.argtypes=[w.HANDLE,ctypes.POINTER(PE)]; k.Process32NextW.restype=w.BOOL
p.GetProcessMemoryInfo.argtypes=[w.HANDLE,ctypes.POINTER(PMC),w.DWORD]; p.GetProcessMemoryInfo.restype=w.BOOL
def utc(): return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00","Z")
def mono(): return time.monotonic_ns()
def err(s): return f"{s}: winerror={ctypes.get_last_error()} {ctypes.FormatError(ctypes.get_last_error())}"
def sha(path):
    h=hashlib.sha256(); n=0
    with path.open("rb") as f:
        while b:=f.read(1024*1024): h.update(b); n+=len(b)
    return h.hexdigest().upper(),n
def decode_pid_payload(raw,count,pointer_size=PTR_SIZE):
    raw=bytes(raw); count=int(count); pointer_size=int(pointer_size); issues=[]
    if pointer_size not in (4,8): return {"ids":[],"assigned_processes":None,"listed_processes":count,"capacity":0,"issues":["unsupported_pointer_size"],"stride_bytes":pointer_size}
    if len(raw)<8: return {"ids":[],"assigned_processes":None,"listed_processes":count,"capacity":0,"issues":["pid_list_header_short"],"stride_bytes":pointer_size}
    assigned=int.from_bytes(raw[0:4],"little"); listed=int.from_bytes(raw[4:8],"little"); capacity=max(0,(len(raw)-8)//pointer_size)
    if listed!=count: issues.append("header_count_mismatch")
    if listed>capacity: issues.append("pid_list_incomplete")
    n=min(listed,capacity); ids=[int.from_bytes(raw[8+pointer_size*i:8+pointer_size*(i+1)],"little") for i in range(n)]
    if any(pid==0 for pid in ids): issues.append("pid_zero")
    return {"ids":ids,"assigned_processes":assigned,"listed_processes":listed,"capacity":capacity,"issues":issues,"stride_bytes":pointer_size}
def info(path):
    try:
        h,n=sha(path); return {"path":str(path),"exists":True,"bytes":n,"sha256":h}
    except Exception as e: return {"path":str(path),"exists":False,"error":repr(e)}
def write_json(path,value):
    text=json.dumps(value,ensure_ascii=False,indent=2)+"\n"; tmp=path.with_name(path.name+".tmp"); tmp.write_text(text,encoding="utf-8",newline="\n"); os.replace(tmp,path); return hashlib.sha256(text.encode()).hexdigest().upper()
def append_jsonl(path,value):
    with path.open("a",encoding="utf-8",newline="\n") as f: f.write(json.dumps(value,ensure_ascii=False,separators=(",",":"))+"\n"); f.flush(); os.fsync(f.fileno())
def mem():
    x=MEM(); x.n=ctypes.sizeof(x)
    if not k.GlobalMemoryStatusEx(ctypes.byref(x)): return {"available_physical_bytes":None,"error":err("GlobalMemoryStatusEx")}
    return {"available_physical_bytes":int(x.avail),"total_physical_bytes":int(x.total),"available_physical_gib":round(int(x.avail)/1024**3,6),"memory_load_percent":int(x.load)}
def table():
    bad=ctypes.c_void_p(-1).value; h=k.CreateToolhelp32Snapshot(SNAP,0)
    if h in (0,bad): return {}
    out={}
    try:
        x=PE(); x.size=ctypes.sizeof(x)
        if not k.Process32FirstW(h,ctypes.byref(x)): return out
        while True:
            out[int(x.pid)]={"pid":int(x.pid),"parent_pid":int(x.ppid),"image_name":str(x.image)}
            if not k.Process32NextW(h,ctypes.byref(x)): break
    finally: k.CloseHandle(h)
    return out
def detail(pid,ent=None):
    d={"pid":int(pid)}; d.update({key:ent.get(key) for key in ("parent_pid","image_name")} if ent else {})
    h=k.OpenProcess(QLIMIT|VMREAD|SYNC,False,int(pid))
    if not h: d["query_error"]=err("OpenProcess"); return d
    try:
        b=ctypes.create_unicode_buffer(32768); n=w.DWORD(len(b))
        if k.QueryFullProcessImageNameW(h,0,b,ctypes.byref(n)): d["image_path"]=b.value
        c=PMC(); c.cb=ctypes.sizeof(c)
        if p.GetProcessMemoryInfo(h,ctypes.byref(c),ctypes.sizeof(c)): d.update({"private_usage_bytes":int(c.private),"working_set_bytes":int(c.ws),"pagefile_usage_bytes":int(c.pfu)})
        else: d["memory_error"]=err("GetProcessMemoryInfo")
        a=FT(); b2=FT(); kt=FT(); ut=FT()
        if k.GetProcessTimes(h,ctypes.byref(a),ctypes.byref(b2),ctypes.byref(kt),ctypes.byref(ut)):
            d["cpu_time_100ns"]=(int(kt.hi)<<32|int(kt.lo))+(int(ut.hi)<<32|int(ut.lo)); d["creation_filetime_100ns"]=int(a.hi)<<32|int(a.lo)
    finally: k.CloseHandle(h)
    return d
def snapshot(pids):
    t=table(); return [detail(x,t.get(x)) for x in sorted(set(int(x) for x in pids if int(x)>0))]
def native_snapshot():
    t=table(); return sorted([detail(pid,e) for pid,e in t.items() if str(e["image_name"]).lower() in {"vivado.exe","xsimk.exe","xelab.exe","xvlog.exe"}],key=lambda x:x["pid"])

API_CONTRACT=(("kernel32", "CreateJobObjectW"),("kernel32", "SetInformationJobObject"),("kernel32", "QueryInformationJobObject"),("kernel32", "AssignProcessToJobObject"),("kernel32", "TerminateJobObject"),("kernel32", "CloseHandle"),("kernel32", "CreateProcessW"),("kernel32", "ResumeThread"),("kernel32", "TerminateProcess"),("kernel32", "GetExitCodeProcess"),("kernel32", "OpenProcess"),("kernel32", "SetHandleInformation"),("kernel32", "GlobalMemoryStatusEx"),("kernel32", "GetProcessTimes"),("kernel32", "QueryFullProcessImageNameW"),("kernel32", "CreateToolhelp32Snapshot"),("kernel32", "Process32FirstW"),("kernel32", "Process32NextW"),("psapi", "GetProcessMemoryInfo"))
def api_contract_complete():
    return all(getattr(k if owner=="kernel32" else p,name).argtypes is not None and getattr(k if owner=="kernel32" else p,name).restype is not None for owner,name in API_CONTRACT)
def telemetry_self_check():
    raw=(2).to_bytes(4,"little")+(2).to_bytes(4,"little")+(1234).to_bytes(PTR_SIZE,"little")+(5678).to_bytes(PTR_SIZE,"little")
    decoded=decode_pid_payload(raw,2,PTR_SIZE); api_ok=api_contract_complete()
    checks={"pointer_size_bytes":PTR_SIZE==8,"pid_stride_bytes":decoded["stride_bytes"],"pid_width_bits":decoded["stride_bytes"]*8,"basic_accounting_class":JOB_ACCOUNTING,"pid_parser_expected":decoded["ids"]==[1234,5678] and not decoded["issues"],"api_argtypes_restype_complete":api_ok,"job_census_method":callable(getattr(Job,"census",None)),"job_accounting_active_field":"active_processes" in {name for name,_ in JACCOUNTING._fields_}}
    return {"schema":"cfo_guard003_self_check_v1","checks":checks,"decoded_synthetic":decoded,"native_started":False}
class Job:
    def __init__(self):
        self.h=k.CreateJobObjectW(None,None)
        if not self.h: raise RuntimeError(err("CreateJobObjectW"))
        self.closed=False; x=JEXT(); x.base.flags=KILL_ON_CLOSE
        if not k.SetInformationJobObject(self.h,JOB_EXT,ctypes.byref(x),ctypes.sizeof(x)): self.close(); raise RuntimeError(err("SetInformationJobObject"))
    def assign(self,h):
        if not k.AssignProcessToJobObject(self.h,h): raise RuntimeError(err("AssignProcessToJobObject"))
    def pid_list(self):
        size=8+PTR_SIZE*256
        for _ in range(8):
            b=ctypes.create_string_buffer(size); ret=w.DWORD()
            if k.QueryInformationJobObject(self.h,JOB_PIDS,b,size,ctypes.byref(ret)):
                listed=int.from_bytes(b.raw[4:8],"little") if size>=8 else 0; decoded=decode_pid_payload(b.raw,listed,PTR_SIZE)
                issues=list(decoded["issues"]); assigned=decoded.get("assigned_processes")
                if assigned is not None and listed is not None and assigned>listed: issues.append("pid_list_incomplete")
                decoded.update({"api_available":True,"success":True,"query_bytes":int(ret.value),"buffer_bytes":size,"issues":list(dict.fromkeys(issues))})
                return decoded
            code=ctypes.get_last_error()
            if code in (ERROR_INSUFFICIENT_BUFFER,ERROR_MORE_DATA):
                next_size=min(size*2,MAX_PID_LIST_BYTES)
                if next_size<=size: return {"api_available":False,"success":False,"ids":[],"assigned_processes":None,"listed_processes":None,"capacity":0,"stride_bytes":PTR_SIZE,"issues":["pid_list_buffer_limit"],"error":f"QueryInformationJobObject(PID list): winerror={code} {ctypes.FormatError(code)}"}
                size=next_size; continue
            return {"api_available":False,"success":False,"ids":[],"assigned_processes":None,"listed_processes":None,"capacity":0,"stride_bytes":PTR_SIZE,"issues":["pid_list_query_failed"],"error":f"QueryInformationJobObject(PID list): winerror={code} {ctypes.FormatError(code)}"}
        return {"api_available":False,"success":False,"ids":[],"assigned_processes":None,"listed_processes":None,"capacity":0,"stride_bytes":PTR_SIZE,"issues":["pid_list_retry_exhausted"],"error":"PID-list buffer growth exhausted"}
    def accounting(self):
        x=JACCOUNTING(); ret=w.DWORD()
        if not k.QueryInformationJobObject(self.h,JOB_ACCOUNTING,ctypes.byref(x),ctypes.sizeof(x),ctypes.byref(ret)): return {"api_available":False,"active_processes":None,"total_processes":None,"error":err("QueryInformationJobObject(accounting)")}
        return {"api_available":True,"active_processes":int(x.active_processes),"total_processes":int(x.total_processes),"total_terminated_processes":int(x.total_terminated_processes),"total_page_fault_count":int(x.total_page_fault_count)}
    def census(self):
        pl=self.pid_list(); ac=self.accounting(); issues=list(pl.get("issues",[])); query_errors=[]
        if pl.get("error"): query_errors.append(pl["error"])
        if ac.get("error"): query_errors.append(ac["error"])
        pids=list(pl.get("ids",[])); assigned=pl.get("assigned_processes"); listed=pl.get("listed_processes"); active=ac.get("active_processes")
        if assigned is not None and listed is not None and assigned!=listed: issues.append("assigned_vs_listed_mismatch")
        if listed is not None and listed!=len(pids): issues.append("listed_vs_decoded_mismatch")
        if active is not None and active!=len(pids): issues.append("active_vs_decoded_mismatch")
        if 0 in pids: issues.append("pid_zero")
        issues=list(dict.fromkeys(issues)); cross=None if active is None or listed is None else {"active_accounting":active,"pid_list_count":listed,"decoded_count":len(pids),"match":active==listed==len(pids)}
        empty=bool(pl.get("api_available") and pl.get("success") and ac.get("api_available") and active==0 and assigned==0 and listed==0 and not pids and not issues)
        return {"pids":pids,"assigned_processes":assigned,"listed_processes":listed,"active_processes":active,"pid_stride_bytes":PTR_SIZE,"pid_width_bits":PTR_SIZE*8,"active_accounting":ac,"pid_list":pl,"pid_cross_check":cross,"issues":issues,"query_errors":query_errors,"query_error":query_errors[0] if query_errors else None,"empty_verified":empty}
    def extended(self):
        x=JEXT(); ret=w.DWORD()
        if not k.QueryInformationJobObject(self.h,JOB_EXT,ctypes.byref(x),ctypes.sizeof(x),ctypes.byref(ret)): return {"api_available":False,"peak_job_private_commit_bytes":None,"error":err("QueryInformationJobObject(extended)")}
        return {"api_available":True,"peak_job_private_commit_bytes":int(x.pjm),"peak_process_memory_bytes":int(x.ppm),"job_memory_limit_bytes":int(x.jml)}
    def kill(self):
        if not k.TerminateJobObject(self.h,0xC000013A): raise RuntimeError(err("TerminateJobObject"))
    def close(self):
        if not self.closed: k.CloseHandle(self.h); self.closed=True

class Suspended:
    def __init__(self,hp,ht,pid,tid): self.hp,self.ht,self.pid,self.tid,self.closed=hp,ht,int(pid),int(tid),False
    def resume(self):
        if k.ResumeThread(self.ht)==0xFFFFFFFF: raise RuntimeError(err("ResumeThread"))
        k.CloseHandle(self.ht); self.ht=0
    def prekill(self):
        if self.hp and not k.TerminateProcess(self.hp,0xC000013A): raise RuntimeError(err("TerminateProcess(pre-resume)"))
    def exit(self):
        x=w.DWORD()
        if not self.hp or not k.GetExitCodeProcess(self.hp,ctypes.byref(x)) or int(x.value)==STILL: return None
        return int(x.value)
    def close(self):
        if self.closed:return
        if self.ht:k.CloseHandle(self.ht);self.ht=0
        if self.hp:k.CloseHandle(self.hp);self.hp=0
        self.closed=True

def inh(f):
    import msvcrt
    h=int(msvcrt.get_osfhandle(f.fileno()))
    if not k.SetHandleInformation(h,INHERIT,INHERIT): raise RuntimeError(err("SetHandleInformation"))
    return h
def spawn(root,argv,out,errfile):
    com=os.environ.get("ComSpec",os.environ.get("COMSPEC",r"C:\Windows\System32\cmd.exe")); native=subprocess.list2cmdline(argv); cmd=f'"{com}" /d /s /c "{native}"'
    fi=open(os.devnull,"rb"); fo=open(out,"ab",buffering=0); fe=open(errfile,"ab",buffering=0)
    try:
        si=SI();si.cb=ctypes.sizeof(si);si.flags=USE_STD;si.hin=inh(fi);si.hout=inh(fo);si.herr=inh(fe); pi=PI(); cb=ctypes.create_unicode_buffer(cmd)
        if not k.CreateProcessW(com,cb,None,None,True,CREATE_SUSPENDED|CREATE_UNICODE|CREATE_NO_WINDOW,None,str(root),ctypes.byref(si),ctypes.byref(pi)): raise RuntimeError(err("CreateProcessW"))
        return Suspended(pi.hp,pi.ht,pi.pid,pi.tid)
    finally: fi.close();fo.close();fe.close()

class Log:
    def __init__(self,path): self.path=path;self.f=path.open("a",encoding="utf-8",newline="\n");self.errors=[]
    def event(self,name,**data):
        try:self.f.write(json.dumps({"utc":utc(),"event":name,**data},ensure_ascii=False,separators=(",",":"))+"\n");self.f.flush();os.fsync(self.f.fileno())
        except Exception as e:self.errors.append(repr(e))
    def close(self):
        try:self.f.close()
        except Exception as e:self.errors.append(repr(e))

def markers(paths,mode):
    txt=[];sizes={}
    for x in paths:
        try:txt.append(x.read_text(encoding="utf-8",errors="replace"));sizes[str(x)]=x.stat().st_size
        except FileNotFoundError:sizes[str(x)]=0
    s="\n".join(txt)
    return {"ready":bool(re.search(rf"CFO_GUARD_READY mode={re.escape(mode)}\b",s)),"normal_end":bool(re.search(r"(?m)^\s*CFO_GUARD_NORMAL_END\s*$",s)),"expected_error":bool(re.search(r"(?m)^\s*CFO_GUARD_EXPECTED_ERROR\s*$",s)),"log_sizes":sizes}

def verify(root):
    actual=root/"reports/rotator_native/actual_sources.csv"; base=[str(PYTHON),"-I","-B","-X","utf8",str(root/VERIFY)];out=[]
    for argv in (base,base+["--actual",str(actual)]):
        r=subprocess.run(argv,cwd=str(root),stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8",errors="replace",shell=False,check=False)
        out.append({"argv":argv,"exit_code":int(r.returncode),"stdout":r.stdout,"stderr":r.stderr})
    return {"identity":out[0],"actual_project":out[1]}

def freeze(root,attempt,script):
    lock=json.loads((root/LOCK).read_text(encoding="utf-8")); members=[];ok=True
    for m in lock["files"]:
        x=info(root/m["path"]);x.update({"relative_path":m["path"],"expected_bytes":m["bytes"],"expected_sha256":m["sha256"]});x["matches"]=bool(x.get("exists") and x.get("bytes")==m["bytes"] and x.get("sha256")==m["sha256"]);ok=ok and x["matches"];members.append(x)
    v=verify(root);xp=info(root/XPR);checks={"guard_source_lock_6_of_6":len(members)==6 and ok,"identity_verify_exit_0":v["identity"]["exit_code"]==0,"actual_project_verify_exit_0":v["actual_project"]["exit_code"]==0,"actual_project_17_marker":"CFO_ACTUAL_PROJECT_PASS files=17" in v["actual_project"]["stdout"],"xpr_expected_dynamic_hash":xp.get("sha256")==EXPECTED_XPR,"frozen_part_top":True}
    deps=[info(script),info(PYTHON),info(VIVADO),info(root/PROBE),info(root/("vivado/run_threads.tcl")),info(root/LOCK),info(root/BASE_LOCK),info(root/JOBDOC),info(root/VERIFY),info(root/REVIEW),xp]
    return {"schema":"cfo_guard003_execution_freeze_v1","job_id":"CFO-GUARD003","recorded_utc":utc(),"controller_pid":os.getpid(),"controller_script":str(script),"attempt_path":str(attempt),"root":str(root),"source_lock_path":str(root/LOCK),"source_lock_sha256":info(root/LOCK).get("sha256"),"source_lock_members":members,"verification":v,"xpr":{**xp,"expected_sha256":EXPECTED_XPR,"matches_expected":xp.get("sha256")==EXPECTED_XPR},"frozen_project":{"part":"xcvu11p-flgb2104-2-e","hardware_top":"cfo_rotate4","simulation_top":"cfo_rotate4_tb"},"tools":{"python":str(PYTHON),"python_version":sys.version,"vivado_bat":str(VIVADO)},"dependencies":deps,"preexisting_native_processes":native_snapshot(),"startup_memory":mem(),"limits":{"normal_error_seconds":60,"hold_ready_trigger_seconds":3,"hold_zero_seconds":5,"hold_launch_absolute_seconds":60,"hard_memory_available_gib":.25,"sustained_memory_available_gib":.50,"sustained_memory_seconds":30,"planned_peak_gib_warning":4,"startup_free_recommendation_gib":6},"native_modes":list(MODES),"native_command_template":"vivado.bat -mode batch -source D:/008_MA_Dev/T11_CFO/vivado/guard_probe_v2.tcl -log <attempt>/<mode>.log -journal <attempt>/<mode>.jou -tclargs <mode>","checks":checks,"no_native_started_before_freeze":True,"no_matlab":True,"no_old_runner":True}

class Mode:
    def __init__(self,root,attempt,log):self.root,self.attempt,self.log=root,attempt,log
    def run(self,mode):
        nlog=self.attempt/f"{mode}.log";njou=self.attempt/f"{mode}.jou";so=self.attempt/f"{mode}.stdout.log";se=self.attempt/f"{mode}.stderr.log";samples=self.attempt/f"{mode}.samples.jsonl"
        argv=[str(VIVADO),"-mode","batch","-source",str(self.root/PROBE).replace("\\","/"),"-log",str(nlog).replace("\\","/"),"-journal",str(njou).replace("\\","/"),"-tclargs",mode]
        R={"mode":mode,"native_argv":argv,"native_command_line":subprocess.list2cmdline(argv),"expected_exit_code":0 if mode=="normal" else 7 if mode=="error" else None,"paths":{"native_log":str(nlog),"native_journal":str(njou),"stdout":str(so),"stderr":str(se),"samples":str(samples)},"events":{x:None for x in ("create_suspended","job_assigned","launch","ready","trigger","zero")},"event_mono_ns":{x:None for x in ("create_suspended","job_assigned","launch","ready","trigger","zero")},"binding_succeeded":False,"termination_reason":None,"termination_requested_by_controller":False,"samples_count":0,"resource_recording_errors":[]}
        proc=None;job=None;triggered=False;zero_deadline=None;low_since=None;paths=[nlog,so,se]
        try:
            R["events"]["create_suspended"]=utc();R["event_mono_ns"]["create_suspended"]=mono();self.log.event("create_suspended_begin",mode=mode,native_argv=argv)
            proc=spawn(self.root,argv,so,se);R["launcher_pid"]=proc.pid;self.log.event("create_suspended_done",mode=mode,launcher_pid=proc.pid)
            job=Job()
            try:job.assign(proc.hp)
            except Exception as e:R["binding_error"]=repr(e);self.log.event("job_binding_failed",mode=mode,error=repr(e));proc.prekill();R["termination_reason"]="BINDING_FAILED_BEFORE_RESUME";raise
            R["binding_succeeded"]=True;R["events"]["job_assigned"]=utc();R["event_mono_ns"]["job_assigned"]=mono();self.log.event("job_assigned",mode=mode,launcher_pid=proc.pid,kill_on_job_close=True)
            proc.resume();R["events"]["launch"]=utc();R["event_mono_ns"]["launch"]=mono();start=R["event_mono_ns"]["launch"];self.log.event("native_resumed_launch",mode=mode)
            first=True;next_sample=start;ready=False
            while True:
                now=mono();mk=markers(paths,mode)
                if mk["ready"] and not ready:ready=True;R["events"]["ready"]=utc();R["event_mono_ns"]["ready"]=now;self.log.event("ready",mode=mode)
                census=job.census();pids=census["pids"];qerr=census.get("query_error");tree=snapshot(pids);mm=mem();ji=job.extended();mon=detail(os.getpid(),table().get(os.getpid()))
                failures=[{"pid":int(x["pid"]),"query_error":x.get("query_error"),"memory_error":x.get("memory_error")} for x in tree if x.get("query_error") or x.get("memory_error")]
                complete_private=not census["issues"] and not failures and len(tree)==len(pids) and all(x.get("private_usage_bytes") is not None for x in tree)
                instant=(0 if census["empty_verified"] else sum(int(x["private_usage_bytes"]) for x in tree) if complete_private else None)
                sm={"utc":utc(),"monotonic_ns":now,"mode":mode,"active_process_count":census.get("active_processes"),"active_process_ids":pids,"active_process_tree":tree,"job_pid_list_count":census.get("listed_processes"),"job_pid_list_assigned_processes":census.get("assigned_processes"),"job_pid_stride_bytes":PTR_SIZE,"job_pid_width_bits":PTR_SIZE*8,"job_active_accounting":census.get("active_accounting"),"job_pid_cross_check":census.get("pid_cross_check"),"job_census_issues":census.get("issues"),"job_census_error":census.get("query_error"),"job_process_open_failures":failures,"job_active_query_error":qerr,"system_memory":mm,"instant_job_private_commit_bytes":instant,"job_memory":ji,"monitor_private_usage_bytes":mon.get("private_usage_bytes"),"stage_progress":mk,"root_exit_code":proc.exit()}
                if first or now>=next_sample:
                    try:append_jsonl(samples,sm);R["samples_count"]+=1
                    except Exception as e:
                        R["resource_recording_errors"].append(repr(e));self.log.event("critical_sample_write_failure",mode=mode,error=repr(e))
                        if not triggered:
                            job.kill();triggered=True;R["termination_requested_by_controller"]=True;R["termination_reason"]="CRITICAL_RESOURCE_RECORDING_FAILURE";R["events"]["trigger"]=utc();R["event_mono_ns"]["trigger"]=now;zero_deadline=now+5_000_000_000
                    next_sample=now+1_000_000_000;first=False
                av=mm.get("available_physical_bytes")
                if isinstance(av,int) and av<HARD_MEM and not triggered:job.kill();triggered=True;R["termination_requested_by_controller"]=True;R["termination_reason"]="SEVERE_MEMORY_PRESSURE_IMMEDIATE";R["events"]["trigger"]=utc();R["event_mono_ns"]["trigger"]=now;zero_deadline=now+5_000_000_000
                elif isinstance(av,int) and av<LOW_MEM:
                    low_since=low_since or now
                    if now-low_since>=30_000_000_000 and not triggered:job.kill();triggered=True;R["termination_requested_by_controller"]=True;R["termination_reason"]="SEVERE_MEMORY_PRESSURE_SUSTAINED_30S";R["events"]["trigger"]=utc();R["event_mono_ns"]["trigger"]=now;zero_deadline=now+5_000_000_000
                else:low_since=None
                if mode=="hold" and ready and not triggered and now-R["event_mono_ns"]["ready"]>=3_000_000_000:job.kill();triggered=True;R["termination_requested_by_controller"]=True;R["termination_reason"]="HOLD_READY_PLUS_3S";R["events"]["trigger"]=utc();R["event_mono_ns"]["trigger"]=now;zero_deadline=now+5_000_000_000;self.log.event("hold_trigger",mode=mode,ready_to_trigger_ns=now-R["event_mono_ns"]["ready"])
                root_exit=proc.exit()
                if now-start>=60_000_000_000 and not triggered and not(root_exit is not None and not pids):job.kill();triggered=True;R["termination_requested_by_controller"]=True;R["termination_reason"]="LAUNCH_PLUS_60S_HARD_TIMEOUT";R["events"]["trigger"]=utc();R["event_mono_ns"]["trigger"]=now;zero_deadline=now+5_000_000_000;self.log.event("hard_timeout",mode=mode)
                if triggered and census["empty_verified"]:R["events"]["zero"]=utc();R["event_mono_ns"]["zero"]=now;self.log.event("job_zero",mode=mode);break
                if triggered and zero_deadline and now>zero_deadline:R["zero_deadline_exceeded"]=True;self.log.event("job_zero_deadline_exceeded",mode=mode,active_pids=pids);break
                if not triggered and root_exit is not None and census["empty_verified"]:R["events"]["zero"]=utc();R["event_mono_ns"]["zero"]=now;self.log.event("job_zero_natural",mode=mode);break
                time.sleep(.1)
            end_census=job.census();R["markers"]=markers(paths,mode);R["native_exit_code"]=proc.exit();R["active_pids_at_loop_end"]=end_census["pids"];R["active_query_error_at_loop_end"]=end_census.get("query_error");R["job_census_at_loop_end"]=end_census;R["job_extended_at_loop_end"]=job.extended()
            if mode=="normal":R["status"]="PASS" if R["binding_succeeded"] and R["native_exit_code"]==0 and R["markers"]["ready"] and R["markers"]["normal_end"] and R["events"]["zero"] and not R["resource_recording_errors"] else "FAIL"
            elif mode=="error":R["status"]="PASS" if R["binding_succeeded"] and R["native_exit_code"]==7 and R["markers"]["ready"] and R["markers"]["expected_error"] and R["events"]["zero"] and not R["resource_recording_errors"] else "FAIL"
            else:
                a=(R["event_mono_ns"]["trigger"]-R["event_mono_ns"]["ready"])/1e9 if R["event_mono_ns"]["trigger"] and R["event_mono_ns"]["ready"] else None;b=(R["event_mono_ns"]["zero"]-R["event_mono_ns"]["trigger"])/1e9 if R["event_mono_ns"]["zero"] and R["event_mono_ns"]["trigger"] else None;c=(R["event_mono_ns"]["zero"]-R["event_mono_ns"]["launch"])/1e9 if R["event_mono_ns"]["zero"] and R["event_mono_ns"]["launch"] else None
                R.update({"ready_to_trigger_seconds":a,"trigger_to_zero_seconds":b,"launch_to_zero_seconds":c,"termination_status":"TERMINATED_EXPECTED" if R.get("termination_reason")=="HOLD_READY_PLUS_3S" else "NOT_EXPECTED_TERMINATION"})
                R["status"]="PASS" if R["binding_succeeded"] and R["markers"]["ready"] and R.get("termination_reason")=="HOLD_READY_PLUS_3S" and a is not None and 3<=a<=4.5 and b is not None and b<=5 and c is not None and c<=65 and R["events"]["zero"] and not R["resource_recording_errors"] else "FAIL"
        except Exception as e:
            R["status"]="FAIL";R["monitor_error"]=repr(e);self.log.event("mode_exception",mode=mode,error=repr(e))
            if job is not None:
                try:job.kill();R["termination_requested_by_controller"]=True;R["termination_reason"]=R.get("termination_reason") or "MONITOR_EXCEPTION"
                except Exception as x:R.setdefault("termination_errors",[]).append(repr(x))
        finally:
            if job is not None:
                try:
                    cfinal=job.census()
                    if not cfinal["empty_verified"] and not R.get("termination_requested_by_controller"):job.kill();R["termination_requested_by_controller"]=True;R["termination_reason"]=R.get("termination_reason") or "FINALLY_JOB_CLEANUP"
                    deadline=mono()+5_000_000_000
                    while not cfinal["empty_verified"] and mono()<deadline:time.sleep(.1);cfinal=job.census()
                    R["active_pids_after_finally"]=cfinal["pids"];R["active_query_error_after_finally"]=cfinal.get("query_error");R["job_census_after_finally"]=cfinal
                except Exception as e:R.setdefault("termination_errors",[]).append(repr(e))
                job.close()
            if proc is not None:
                if not R.get("binding_succeeded") and not proc.closed:
                    try:proc.prekill();R["pre_resume_cleanup"]="TerminateProcess"
                    except Exception as e:R.setdefault("termination_errors",[]).append(repr(e))
                R["native_exit_code_final"]=proc.exit();proc.close()
        R["controller_log_errors"]=list(self.log.errors);R["artifacts"]=[info(x) for x in (nlog,njou,so,se,samples)];return R

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",type=Path,default=ROOT);ap.add_argument("--self-check",action="store_true");a=ap.parse_args();root=a.root.resolve()
    if a.self_check:
        checks={"root":root.is_dir(),"python":PYTHON.is_file(),"vivado":VIVADO.is_file(),"xpr":(root/XPR).is_file(),"probe":(root/PROBE).is_file(),"lock":(root/LOCK).is_file(),"job_kill_on_close":KILL_ON_CLOSE==0x2000,"create_suspended":CREATE_SUSPENDED==4}
        telemetry=telemetry_self_check(); checks.update({"pointer_size_8":telemetry["checks"]["pointer_size_bytes"],"pid_stride_8":telemetry["checks"]["pid_stride_bytes"]==8,"accounting_class_1":telemetry["checks"]["basic_accounting_class"]==1,"pid_parser_expected":telemetry["checks"]["pid_parser_expected"],"api_argtypes_restype_complete":telemetry["checks"]["api_argtypes_restype_complete"],"job_census_method":telemetry["checks"]["job_census_method"]})
        print(json.dumps({"schema":"cfo_guard003_self_check_v1","checks":checks,"telemetry":telemetry,"native_started":False}));return 0 if all(checks.values()) else 2
    parent=root/"work/CFO_GUARD003";parent.mkdir(parents=True,exist_ok=True);attempt=parent/f"attempt_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}_luna";attempt.mkdir();write_json(attempt/"report_clock.json",{"schema":"cfo_guard003_report_clock_v1","thread_id":"01a076f0-d8c0-72a0-8371-cb2ff29c1b28","started_utc":utc(),"interval_minutes":15,"status":"ACTIVE"});log=Log(attempt/"guard_controller.log")
    try:
        frozen=freeze(root,attempt,Path(__file__).resolve());fh=write_json(attempt/"EXECUTION_FREEZE.json",frozen);log.event("execution_freeze_written",sha256=fh,checks=frozen["checks"])
        if not all(frozen["checks"].values()):
            c={"schema":"cfo_guard003_completion_v1","status":"BLOCKED_PREFLIGHT","attempt":str(attempt),"execution_freeze_sha256":fh,"checks":frozen["checks"]};ch=write_json(attempt/"ATTEMPT_COMPLETION.json",c);print(json.dumps({"status":c["status"],"attempt":str(attempt),"completion_sha256":ch}));return 3
        results=[];binding_stop=False;runner=Mode(root,attempt,log)
        for mode in MODES:
            r=runner.run(mode);results.append(r)
            if not r.get("binding_succeeded") and r.get("binding_error"):binding_stop=True;log.event("binding_failure_stops_remaining",mode=mode);break
        c={"schema":"cfo_guard003_completion_v1","job_id":"CFO-GUARD003","generated_utc":utc(),"attempt":str(attempt),"controller_pid":os.getpid(),"execution_freeze":{"path":str(attempt/"EXECUTION_FREEZE.json"),"sha256":fh},"modes":results,"all_modes_pass":len(results)==3 and all(r.get("status")=="PASS" for r in results),"binding_failure_stopped_remaining":binding_stop,"post_native_processes":native_snapshot(),"t10_not_operated_by_controller":True,"no_matlab":True,"no_computation_rerun":True,"no_compile_simulation_synthesis_or_ip_generation":True,"scope":"Only frozen normal/error/hold guard_probe_v2.tcl execution protection."}
        ch=write_json(attempt/"ATTEMPT_COMPLETION.json",c);log.event("completion_written",sha256=ch,all_modes_pass=c["all_modes_pass"]);print(json.dumps({"status":"PASS" if c["all_modes_pass"] else "FAIL","attempt":str(attempt),"completion_sha256":ch}));return 0 if c["all_modes_pass"] else 4
    except Exception as e:
        log.event("controller_exception",error=repr(e));c={"schema":"cfo_guard003_completion_v1","status":"CONTROLLER_FAILURE","generated_utc":utc(),"attempt":str(attempt),"error":repr(e)}
        try:ch=write_json(attempt/"ATTEMPT_COMPLETION.json",c)
        except Exception:ch=None
        print(json.dumps({"status":c["status"],"attempt":str(attempt),"completion_sha256":ch,"error":repr(e)}));return 5
    finally:log.close()

if __name__=="__main__":raise SystemExit(main())
