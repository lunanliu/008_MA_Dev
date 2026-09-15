#!/usr/bin/env python3
"""Private Windows Job Object supervisor for T08-LUNA-007."""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import datetime as dt
import json
import msvcrt
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)

HANDLE = wintypes.HANDLE
DWORD = wintypes.DWORD
BOOL = wintypes.BOOL
ULONG_PTR = ctypes.c_size_t
SIZE_T = ctypes.c_size_t
LONGLONG = ctypes.c_longlong

CREATE_SUSPENDED = 0x00000004
CREATE_NO_WINDOW = 0x08000000
CREATE_UNICODE_ENVIRONMENT = 0x00000400
STARTF_USESTDHANDLES = 0x00000100
WAIT_OBJECT_0 = 0
WAIT_TIMEOUT = 0x102
ERROR_MORE_DATA = 234
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
JOB_OBJECT_BASIC_ACCOUNTING_INFORMATION = 1
JOB_OBJECT_BASIC_PROCESS_ID_LIST = 3
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000

class FILETIME(ctypes.Structure):
    _fields_ = [("dwLowDateTime", DWORD), ("dwHighDateTime", DWORD)]

class STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ("cb", DWORD), ("lpReserved", ctypes.c_wchar_p), ("lpDesktop", ctypes.c_wchar_p),
        ("lpTitle", ctypes.c_wchar_p), ("dwX", DWORD), ("dwY", DWORD),
        ("dwXSize", DWORD), ("dwYSize", DWORD), ("dwXCountChars", DWORD),
        ("dwYCountChars", DWORD), ("dwFillAttribute", DWORD), ("dwFlags", DWORD),
        ("wShowWindow", wintypes.WORD), ("cbReserved2", wintypes.WORD),
        ("lpReserved2", ctypes.POINTER(ctypes.c_ubyte)), ("hStdInput", HANDLE),
        ("hStdOutput", HANDLE), ("hStdError", HANDLE),
    ]

class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", HANDLE), ("hThread", HANDLE),
                ("dwProcessId", DWORD), ("dwThreadId", DWORD)]

class IO_COUNTERS(ctypes.Structure):
    _fields_ = [("ReadOperationCount", LONGLONG), ("WriteOperationCount", LONGLONG),
                ("OtherOperationCount", LONGLONG), ("ReadTransferCount", LONGLONG),
                ("WriteTransferCount", LONGLONG), ("OtherTransferCount", LONGLONG)]

class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", LONGLONG), ("PerJobUserTimeLimit", LONGLONG),
        ("LimitFlags", DWORD), ("MinimumWorkingSetSize", SIZE_T),
        ("MaximumWorkingSetSize", SIZE_T), ("ActiveProcessLimit", DWORD),
        ("Affinity", ULONG_PTR), ("PriorityClass", DWORD), ("SchedulingClass", DWORD),
    ]

class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
        ("IoInfo", IO_COUNTERS), ("ProcessMemoryLimit", SIZE_T),
        ("JobMemoryLimit", SIZE_T), ("PeakProcessMemoryUsed", SIZE_T),
        ("PeakJobMemoryUsed", SIZE_T),
    ]

class JOBOBJECT_BASIC_ACCOUNTING_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("TotalUserTime", LONGLONG), ("TotalKernelTime", LONGLONG),
        ("ThisPeriodTotalUserTime", LONGLONG),
        ("ThisPeriodTotalKernelTime", LONGLONG),
        ("TotalPageFaultCount", DWORD), ("TotalProcesses", DWORD),
        ("ActiveProcesses", DWORD), ("TotalTerminatedProcesses", DWORD),
    ]

class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
    _fields_ = [
        ("cb", DWORD), ("PageFaultCount", DWORD),
        ("PeakWorkingSetSize", SIZE_T), ("WorkingSetSize", SIZE_T),
        ("QuotaPeakPagedPoolUsage", SIZE_T), ("QuotaPagedPoolUsage", SIZE_T),
        ("QuotaPeakNonPagedPoolUsage", SIZE_T), ("QuotaNonPagedPoolUsage", SIZE_T),
        ("PagefileUsage", SIZE_T), ("PeakPagefileUsage", SIZE_T),
    ]

kernel32.CreateJobObjectW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p]
kernel32.CreateJobObjectW.restype = HANDLE
kernel32.SetInformationJobObject.argtypes = [HANDLE, ctypes.c_int, ctypes.c_void_p, DWORD]
kernel32.SetInformationJobObject.restype = BOOL
kernel32.QueryInformationJobObject.argtypes = [HANDLE, ctypes.c_int, ctypes.c_void_p, DWORD, ctypes.POINTER(DWORD)]
kernel32.QueryInformationJobObject.restype = BOOL
kernel32.AssignProcessToJobObject.argtypes = [HANDLE, HANDLE]
kernel32.AssignProcessToJobObject.restype = BOOL
kernel32.TerminateJobObject.argtypes = [HANDLE, DWORD]
kernel32.TerminateJobObject.restype = BOOL
kernel32.ResumeThread.argtypes = [HANDLE]
kernel32.ResumeThread.restype = DWORD
kernel32.WaitForSingleObject.argtypes = [HANDLE, DWORD]
kernel32.WaitForSingleObject.restype = DWORD
kernel32.GetExitCodeProcess.argtypes = [HANDLE, ctypes.POINTER(DWORD)]
kernel32.GetExitCodeProcess.restype = BOOL
kernel32.GetProcessTimes.argtypes = [HANDLE, ctypes.POINTER(FILETIME), ctypes.POINTER(FILETIME), ctypes.POINTER(FILETIME), ctypes.POINTER(FILETIME)]
kernel32.GetProcessTimes.restype = BOOL
kernel32.OpenProcess.argtypes = [DWORD, BOOL, DWORD]
kernel32.OpenProcess.restype = HANDLE
kernel32.CloseHandle.argtypes = [HANDLE]
kernel32.CloseHandle.restype = BOOL
kernel32.QueryFullProcessImageNameW.argtypes = [HANDLE, DWORD, ctypes.c_wchar_p, ctypes.POINTER(DWORD)]
kernel32.QueryFullProcessImageNameW.restype = BOOL
psapi.GetProcessMemoryInfo.argtypes = [HANDLE, ctypes.POINTER(PROCESS_MEMORY_COUNTERS), DWORD]
psapi.GetProcessMemoryInfo.restype = BOOL

def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")

def win_error(prefix: str) -> RuntimeError:
    return RuntimeError(f"{prefix}; winerror={ctypes.get_last_error()}")

def ft_value(value: FILETIME) -> int:
    return (int(value.dwHighDateTime) << 32) | int(value.dwLowDateTime)

def ft_utc(value: FILETIME) -> str:
    unix_100ns = ft_value(value) - 116444736000000000
    return dt.datetime.fromtimestamp(unix_100ns / 10_000_000, tz=dt.timezone.utc).isoformat().replace("+00:00", "Z")

def creation_time(handle: HANDLE) -> str | None:
    created, exited, kernel, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
    if not kernel32.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(kernel), ctypes.byref(user)):
        return None
    return ft_utc(created)

def exit_code(handle: HANDLE) -> int | None:
    value = DWORD()
    return int(value.value) if kernel32.GetExitCodeProcess(handle, ctypes.byref(value)) else None

def job_active(job: HANDLE) -> int:
    value, returned = JOBOBJECT_BASIC_ACCOUNTING_INFORMATION(), DWORD()
    if not kernel32.QueryInformationJobObject(job, JOB_OBJECT_BASIC_ACCOUNTING_INFORMATION,
                                              ctypes.byref(value), ctypes.sizeof(value), ctypes.byref(returned)):
        raise win_error("QueryInformationJobObject(accounting) failed")
    return int(value.ActiveProcesses)

def job_pids(job: HANDLE) -> list[int]:
    capacity = 64
    while capacity <= 4096:
        item_size = ctypes.sizeof(ULONG_PTR)
        raw = (ctypes.c_ubyte * (8 + capacity * item_size))()
        returned = DWORD()
        ok = kernel32.QueryInformationJobObject(job, JOB_OBJECT_BASIC_PROCESS_ID_LIST,
                                                ctypes.byref(raw), ctypes.sizeof(raw), ctypes.byref(returned))
        if ok:
            count = int.from_bytes(bytes(raw[4:8]), "little")
            return [
                int.from_bytes(bytes(raw[8 + i * item_size:8 + (i + 1) * item_size]), "little")
                for i in range(min(count, capacity))
            ]
        if ctypes.get_last_error() != ERROR_MORE_DATA:
            return []
        capacity *= 2
    return []

def member_info(pid: int) -> dict[str, Any]:
    result: dict[str, Any] = {"pid": pid}
    access = PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
    handle = kernel32.OpenProcess(access, False, pid)
    if not handle:
        result["open_error"] = ctypes.get_last_error()
        return result
    try:
        result["creation_utc"] = creation_time(handle)
        size = DWORD(32768)
        image = ctypes.create_unicode_buffer(size.value)
        if kernel32.QueryFullProcessImageNameW(handle, 0, image, ctypes.byref(size)):
            result["image"] = image.value
        memory = PROCESS_MEMORY_COUNTERS()
        memory.cb = ctypes.sizeof(memory)
        if psapi.GetProcessMemoryInfo(handle, ctypes.byref(memory), ctypes.sizeof(memory)):
            result["working_set_bytes"] = int(memory.WorkingSetSize)
            result["peak_working_set_bytes"] = int(memory.PeakWorkingSetSize)
        created, exited, kernel, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
        if kernel32.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(kernel), ctypes.byref(user)):
            result["kernel_time_100ns"] = ft_value(kernel)
            result["user_time_100ns"] = ft_value(user)
    finally:
        kernel32.CloseHandle(handle)
    return result

def file_state(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    if not path.exists():
        return {"exists": False, "bytes": 0}
    try:
        stat = path.stat()
        return {"exists": True, "bytes": int(stat.st_size),
                "mtime_utc": dt.datetime.fromtimestamp(stat.st_mtime, tz=dt.timezone.utc).isoformat().replace("+00:00", "Z")}
    except OSError as exc:
        return {"exists": True, "error": repr(exc)}

def tail(path: Path | None, limit: int = 2048) -> str | None:
    if path is None or not path.exists():
        return None
    try:
        with path.open("rb") as stream:
            stream.seek(0, os.SEEK_END)
            stream.seek(max(0, stream.tell() - limit), os.SEEK_SET)
            return stream.read(limit).decode("utf-8", errors="replace")
    except OSError as exc:
        return f"<read-error:{exc!r}>"

class Evidence:
    def __init__(self, snapshots: Path, latest: Path):
        self.snapshots, self.latest = snapshots, latest
        snapshots.parent.mkdir(parents=True, exist_ok=True)
    def write(self, payload: dict[str, Any]) -> None:
        with self.snapshots.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        temporary = self.latest.with_suffix(".tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(temporary, self.latest)

def make_env(path_prepend: str | None) -> ctypes.Array[Any]:
    env = {str(key): str(value) for key, value in os.environ.items()}
    if path_prepend:
        env["PATH"] = path_prepend + ";" + env.get("PATH", "")
    block = "\0".join(f"{key}={value}" for key, value in sorted(env.items(), key=lambda item: item[0].upper())) + "\0\0"
    return ctypes.create_unicode_buffer(block)

def quote_command(argv: list[str]) -> str:
    return subprocess.list2cmdline(argv)

def create_suspended(argv: list[str], cwd: Path, out_path: Path, err_path: Path,
                     path_prepend: str | None) -> tuple[HANDLE, HANDLE, int, str]:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    err_path.parent.mkdir(parents=True, exist_ok=True)
    fds: list[int] = []
    try:
        fds = [
            os.open(str(out_path), os.O_CREAT | os.O_WRONLY | os.O_TRUNC | getattr(os, "O_BINARY", 0), 0o666),
            os.open(str(err_path), os.O_CREAT | os.O_WRONLY | os.O_TRUNC | getattr(os, "O_BINARY", 0), 0o666),
            os.open("NUL", os.O_RDONLY | getattr(os, "O_BINARY", 0)),
        ]
        for fd in fds:
            os.set_handle_inheritable(msvcrt.get_osfhandle(fd), True)
        startup = STARTUPINFOW()
        startup.cb = ctypes.sizeof(startup)
        startup.dwFlags = STARTF_USESTDHANDLES
        startup.wShowWindow = 0
        startup.hStdOutput = msvcrt.get_osfhandle(fds[0])
        startup.hStdError = msvcrt.get_osfhandle(fds[1])
        startup.hStdInput = msvcrt.get_osfhandle(fds[2])
        info = PROCESS_INFORMATION()
        env_block = make_env(path_prepend)
        command = quote_command(argv)
        command_buffer = ctypes.create_unicode_buffer(command)
        ok = kernel32.CreateProcessW(None, command_buffer, None, None, True,
                                     CREATE_SUSPENDED | CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
                                     ctypes.cast(env_block, ctypes.c_void_p), str(cwd),
                                     ctypes.byref(startup), ctypes.byref(info))
        if not ok:
            raise win_error("CreateProcessW failed")
        return info.hProcess, info.hThread, int(info.dwProcessId), command
    finally:
        for fd in fds:
            try:
                os.close(fd)
            except OSError:
                pass

def args_for() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", required=True)
    parser.add_argument("--attempt-id", required=True)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--stdout", required=True)
    parser.add_argument("--stderr", required=True)
    parser.add_argument("--snapshots", required=True)
    parser.add_argument("--latest", required=True)
    parser.add_argument("--exit-record", required=True)
    parser.add_argument("--cancel-path", required=True)
    parser.add_argument("--deadline-seconds", type=float, required=True)
    parser.add_argument("--snapshot-interval-seconds", type=float, default=10.0)
    parser.add_argument("--progress-path")
    parser.add_argument("--path-prepend")
    parser.add_argument("--execution-job-id", default="T08-LUNA-007")
    parser.add_argument("--source-job-id", default="T08-004")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    result = parser.parse_args()
    if result.command and result.command[0] == "--":
        result.command = result.command[1:]
    if not result.command:
        parser.error("missing child command after --")
    return result

def main() -> int:
    if os.name != "nt":
        raise SystemExit("Windows only")
    args = args_for()
    cwd = Path(args.cwd).resolve()
    out_path, err_path = Path(args.stdout).resolve(), Path(args.stderr).resolve()
    snapshots, latest = Path(args.snapshots).resolve(), Path(args.latest).resolve()
    exit_path, cancel_path = Path(args.exit_record).resolve(), Path(args.cancel_path).resolve()
    progress = Path(args.progress_path).resolve() if args.progress_path else None
    evidence = Evidence(snapshots, latest)
    started = utc_now()
    start_mono = time.monotonic()
    deadline = start_mono + float(args.deadline_seconds)
    job = process = thread = None
    pid: int | None = None
    root_created = root_exit_seen = job_empty = None
    root_rc = None
    timed_out = cancelled = False
    stop_note = None
    launch_error = terminate_error = None
    final_active = -1
    snapshot_count = 0
    last_snapshot = 0.0
    command = quote_command(args.command)

    def snap(event: str, active: int | None = None) -> None:
        nonlocal last_snapshot, snapshot_count
        active_error = None
        if active is None:
            try:
                active = job_active(job) if job else 0
            except Exception as exc:
                active, active_error = -1, repr(exc)
        pids = job_pids(job) if job else []
        payload = {
            "schema": "T08-LUNA-007-supervisor-snapshot-v1",
            "utc": utc_now(), "event": event, "stage": args.stage,
            "attempt_id": args.attempt_id, "execution_job_id": args.execution_job_id,
            "source_job_id": args.source_job_id,
            "root": {"pid": pid, "creation_utc": root_created},
            "job_active_processes": active, "job_member_pids": pids,
            "job_members": [member_info(member_pid) for member_pid in pids],
            "elapsed_seconds": round(time.monotonic() - start_mono, 3),
            "deadline_seconds": args.deadline_seconds,
            "cancel_requested": cancel_path.exists(), "active_query_error": active_error,
            "stdout": file_state(out_path), "stderr": file_state(err_path),
            "progress": file_state(progress), "progress_tail": tail(progress),
        }
        evidence.write(payload)
        snapshot_count += 1
        last_snapshot = time.monotonic()

    def stop_owned(reason: str, code: int) -> None:
        nonlocal terminate_error, final_active
        if not job:
            final_active = 0
            return
        try:
            if not kernel32.TerminateJobObject(job, DWORD(code)):
                raise win_error(f"TerminateJobObject({reason}) failed")
        except Exception as exc:
            terminate_error = repr(exc)
        stop_deadline = time.monotonic() + 60.0
        while time.monotonic() < stop_deadline:
            try:
                active = job_active(job)
            except Exception as exc:
                terminate_error = terminate_error or repr(exc)
                active = -1
            snap(reason + "_wait", active)
            if active == 0:
                final_active = 0
                return
            time.sleep(0.5)
        try:
            final_active = job_active(job)
        except Exception as exc:
            terminate_error = terminate_error or repr(exc)
            final_active = -1

    supervisor_rc = 2
    try:
        job = kernel32.CreateJobObjectW(None, f"T08_LUNA_007_{args.stage}_{os.getpid()}")
        if not job:
            raise win_error("CreateJobObjectW failed")
        limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not kernel32.SetInformationJobObject(job, JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
                                                ctypes.byref(limits), ctypes.sizeof(limits)):
            raise win_error("SetInformationJobObject failed")
        snap("job_created", 0)
        process, thread, pid, command = create_suspended(args.command, cwd, out_path, err_path, args.path_prepend)
        root_created = creation_time(process)
        if not kernel32.AssignProcessToJobObject(job, process):
            raise win_error("AssignProcessToJobObject failed")
        snap("root_assigned", job_active(job))
        if kernel32.ResumeThread(thread) == 0xFFFFFFFF:
            raise win_error("ResumeThread failed")
        snap("root_resumed", job_active(job))
        while True:
            active = job_active(job)
            if time.monotonic() - last_snapshot >= max(1.0, float(args.snapshot_interval_seconds)):
                snap("periodic", active)
            if cancel_path.exists():
                cancelled = True
                stop_note = "native batch has no supported graceful stop channel; only the dedicated owned job is terminated"
                snap("cancel_requested", active)
                stop_owned("cancel", 125)
                break
            if time.monotonic() >= deadline:
                timed_out = True
                stop_note = "hard deadline reached; native batch graceful stop unavailable"
                snap("hard_timeout", active)
                stop_owned("timeout", 124)
                break
            result = kernel32.WaitForSingleObject(process, 500)
            if result == WAIT_OBJECT_0 and root_exit_seen is None:
                root_rc = exit_code(process)
                root_exit_seen = utc_now()
                snap("root_exit", job_active(job))
            elif result not in (WAIT_TIMEOUT, WAIT_OBJECT_0):
                snap(f"wait_result_{result}", active)
            if root_exit_seen is not None:
                remaining = job_active(job)
                if remaining == 0:
                    job_empty = utc_now()
                    final_active = 0
                    snap("job_empty", 0)
                    break
        if root_exit_seen is None:
            root_rc = exit_code(process)
            root_exit_seen = utc_now()
        if final_active < 0:
            final_active = job_active(job)
        if final_active == 0 and job_empty is None:
            job_empty = utc_now()
            snap("job_empty_after_stop", 0)
        supervisor_rc = 125 if cancelled else (124 if timed_out else (root_rc if root_rc is not None else 2))
    except Exception as exc:
        launch_error = repr(exc)
        if process is not None and job is not None and final_active != 0:
            stop_owned("supervisor_error", 126)
        supervisor_rc = 126
    finally:
        if thread:
            kernel32.CloseHandle(thread)
        if process:
            kernel32.CloseHandle(process)
        if job:
            try:
                final_active = job_active(job)
            except Exception:
                pass
            kernel32.CloseHandle(job)

    empty_delta = None
    if root_exit_seen and job_empty:
        try:
            first = dt.datetime.fromisoformat(root_exit_seen.replace("Z", "+00:00"))
            last = dt.datetime.fromisoformat(job_empty.replace("Z", "+00:00"))
            empty_delta = (last - first).total_seconds()
        except ValueError:
            pass
    record = {
        "schema": "T08-LUNA-007-supervisor-exit-v1",
        "stage": args.stage, "attempt_id": args.attempt_id,
        "execution_job_id": args.execution_job_id, "source_job_id": args.source_job_id,
        "started_utc": started, "ended_utc": utc_now(),
        "elapsed_seconds": round(time.monotonic() - start_mono, 3),
        "command_argv": args.command, "command_line": command, "cwd": str(cwd),
        "private_path_prepend": args.path_prepend,
        "root": {"pid": pid, "creation_utc": root_created, "exit_seen_utc": root_exit_seen, "returncode": root_rc},
        "returncode": root_rc, "supervisor_returncode": supervisor_rc,
        "timed_out": timed_out, "cancelled": cancelled,
        "graceful_stop_available": False, "graceful_stop_note": stop_note,
        "owned_active_processes_after": final_active, "job_empty_utc": job_empty,
        "root_to_job_empty_seconds": empty_delta, "snapshot_count": snapshot_count,
        "ownership": {"windows_job_object": True, "kill_on_job_close": True,
                      "breakaway_allowed": False, "broad_process_name_kill": False,
                      "job_member_snapshots": True},
        "stdout": file_state(out_path), "stderr": file_state(err_path),
        "progress": file_state(progress), "launch_error": launch_error,
        "terminate_error": terminate_error,
    }
    exit_path.parent.mkdir(parents=True, exist_ok=True)
    exit_path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    return int(supervisor_rc)

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write(f"private_job_supervisor fatal: {exc!r}\n")
        raise
