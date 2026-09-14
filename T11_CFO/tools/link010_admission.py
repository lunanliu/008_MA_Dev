#!/usr/bin/env python3
"""LINK010 read-only, per-stage resource admission; never launch or stop a tool.

snapshot("create"|"simulate", Q=<frozen phase74 module>) returns evidence only.
The wrapper must call it anew immediately before EACH stage, preserve the result,
and refuse admission unless all_checks is true. This is NOT an atomic slot lock.
--self-check exercises pure decision functions only, without loading Win32/guards.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import hashlib
import importlib.util
import json
import ntpath
import os
from pathlib import Path
import re
import struct
import sys

ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
SLOT = Path(r"D:\007 Dev\OTA_RTL_0829\reports\operations\sync_frontend\resource_slot.json")
ASTRA = "01a076f1-ad1b-7d33-a29c-4ea34ae84d01"
LUNA = "01a076f0-d8c0-72a0-8371-cb2ff29c1b28"
MANAGER = "01a06e5a-ad5f-7bb3-9fb2-a4eb4560bbb7"
T10 = {34768: ("vivado.exe", 134338317352384478),
       28856: ("xsimk.exe", 134338327375072737)}
GUI_PID = 14300
GUI_CREATION = 134338922191654740
VIVADO_EXE = r"C:\NIFPGA\programs\Vivado2021_1\bin\unwrapped\win64.o\vivado.exe"
T10_XSIM_EXE = r"D:\008_MA_Dev\vivado\T10_SFO_exec_20260914_run03\T10_SFO.sim\sim_1\behav\xsim\xsim.dir\t10_full023_tb_behav\xsimk.exe"
EXPECTED_EXES = {34768: VIVADO_EXE, 28856: T10_XSIM_EXE, GUI_PID: VIVADO_EXE}
GUI_XPR = r"D:\008_MA_Dev\I16_AddSub_CLIP\vivado\I16_AddSub\I16_AddSub.xpr"
GUI_LOG = Path(r"C:\NIFPGA\programs\Vivado2021_1\bin\vivado.log")
GUARD_SHA = "B35F872630D2995B5EEB5257666188D3506C864FC4004294423078AE0CFE9583"
G_SHA = "FD2AB067BB509A2BAE4F26270DCC4E77EF0EC61DE62B564EC4DEA2B1A3D37034"
NATIVE = {"vivado.exe", "xsim.exe", "xsimk.exe", "xelab.exe", "xvlog.exe",
          "xvhdl.exe", "rdiargs.exe", "synth_design.exe", "vitis_hls.exe",
          "vivado_hls.exe", "ise.exe", "xst.exe", "map.exe", "par.exe"}
GIB = 1024 ** 3
MAX_LOG_BYTES = 16 * 1024 ** 2


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")


def canon(path):
    return ntpath.normcase(ntpath.normpath(str(path).replace("/", "\\")))


def digest(data):
    return hashlib.sha256(data).hexdigest().upper()


def identity(record):
    return (int(record["pid"]), int(record.get("creation_filetime_100ns", -1)),
            str(record.get("image_name", "")).lower(), canon(record.get("image_path", "")))


def grant_checks(slot):
    status = str(slot.get("shared_slot_status", "")).upper()
    return {
        "manager_identity": slot.get("manager_thread_id") == MANAGER,
        "manager_grants_t11_owner": slot.get("shared_slot_owner") == "T11_T13",
        "manager_grants_this_astra": slot.get("granted_astra") == ASTRA,
        "manager_grants_this_luna": slot.get("granted_luna") == LUNA,
        "grant_id_present": isinstance(slot.get("grant_id"), str) and bool(slot["grant_id"].strip()),
        "status_granted_and_not_hold": status.startswith("GRANTED") and "HOLD" not in status,
        "global_limit_is_two": slot.get("global_vivado_main_limit") == 2,
        "pair_limit_is_one": slot.get("per_pair_limit") == 1,
    }


def descendant_ids(table, root):
    found = {root} if root in table else set()
    while True:
        extra = {pid for pid, row in table.items() if row.get("parent_pid") in found}
        new = extra - found
        if not new:
            return found
        found.update(new)


def evaluate_snapshot(slot, processes, *, memory, gui, inventory_stable,
                      slot_stable, stage):
    """Pure policy. Input process list contains native/MATLAB and all GUI/T10 descendants."""
    rows = {int(row["pid"]): row for row in processes}
    checks = grant_checks(slot)
    checks.update({"supported_stage": stage in ("create", "simulate"),
                   "inventory_stable": bool(inventory_stable),
                   "manager_slot_unchanged_during_probe": bool(slot_stable)})
    protected = []
    for pid, (name, creation) in T10.items():
        row = rows.get(pid, {})
        good = bool(row and identity(row) == (pid, creation, name, canon(EXPECTED_EXES[pid])) and not row.get("query_error"))
        checks["protected_t10_identity_" + str(pid)] = good
        protected.append({"pid": pid, "expected_name": name, "expected_creation": creation, "expected_executable": EXPECTED_EXES[pid],
                          "matches": good, "actual": row or None})
    gui_row = rows.get(GUI_PID)
    gui_exact = bool(gui_row and identity(gui_row) == (GUI_PID, GUI_CREATION, "vivado.exe", canon(VIVADO_EXE)))
    checks["gui_absent_or_exact_identity"] = not gui_row or gui_exact
    gui_ids = set(gui.get("tree_pids", []))
    editor_ok = bool(gui_exact and gui.get("editor_only_confirmed"))
    checks["gui_absent_or_editor_only_verified"] = not gui_row or editor_ok

    # T10 descendants may be members of its SINGLE reserved job. A new actual
    # compute PID, even in that tree, requires review; only the two frozen native
    # identities are exempt from the no-new-compute check.
    unexpected = []
    for row in processes:
        pid = int(row["pid"])
        name = str(row.get("image_name", "")).lower()
        if name not in NATIVE:
            continue
        if pid in T10 and identity(row) == (pid, T10[pid][1], T10[pid][0], canon(EXPECTED_EXES[pid])):
            continue
        if pid == GUI_PID and editor_ok:
            continue
        unexpected.append(row)
    checks["no_unapproved_native_compute_or_ambiguous_gui"] = not unexpected
    matlab = [r for r in processes if str(r.get("image_name", "")).lower() == "matlab.exe"]
    matlab_ids = {int(r["pid"]) for r in matlab}
    matlab_roots = [r for r in matlab if int(r.get("parent_pid", -1)) not in matlab_ids]
    checks["matlab_at_most_one_process_group"] = len(matlab_roots) <= 1
    missing = [r for r in processes if r.get("query_error") or r.get("memory_error")
               or not isinstance(r.get("private_usage_bytes"), int)
               or not isinstance(r.get("creation_filetime_100ns"), int)]
    checks["selected_process_identity_and_memory_complete"] = not missing
    available = memory.get("available_physical_bytes")
    checks["physical_memory_readable"] = isinstance(available, int) and available >= 0
    checks["no_current_severe_physical_memory_pressure"] = isinstance(available, int) and available >= GIB // 2
    private = sum(r["private_usage_bytes"] for r in processes) if not missing else None
    gui_rows = [r for r in processes if int(r["pid"]) in gui_ids]
    gui_private = (sum(r["private_usage_bytes"] for r in gui_rows)
                   if all(isinstance(r.get("private_usage_bytes"), int) for r in gui_rows) else None)
    warnings = []
    if isinstance(available, int) and available < 6 * GIB:
        warnings.append("Available physical memory is below the 6 GiB recommendation; estimate alone is not a veto.")
    if isinstance(available, int) and available < 4 * GIB:
        warnings.append("The 4 GiB planning warning budget exceeds available physical memory; record actual resource judgement.")
    if gui_row and not editor_ok:
        warnings.append("GUI computation/editor-only state is unresolved or active; do not infer it from CPU usage.")
    return {
        "checks": checks, "all_checks": all(checks.values()),
        "blocking_checks": [key for key, value in checks.items() if not value],
        "protected_t10": protected, "unexpected_native_compute": unexpected,
        "matlab": {"processes": matlab, "main_group_count": len(matlab_roots), "limit": 1,
                   "planned_matlab_groups": 0},
        "compute_groups": {"t10_reserved": 1, "gui_editor": 0 if editor_ok or not gui_row else None,
                           "t11_existing": 0 if not unexpected else None, "t11_planned": 1,
                           "expected_after_admission": 2 if not unexpected and (editor_ok or not gui_row) else None,
                           "global_limit": 2, "pair_limit": 1},
        "memory": {**memory, "selected_process_private_bytes": private,
                   "gui_and_editor_children_private_bytes": gui_private,
                   "recommended_available_physical_gib": 6,
                   "planned_t11_peak_expected_gib": [1.5, 3],
                   "planned_t11_peak_warning_gib": 4,
                   "available_after_planned_4gib_bytes": available - 4 * GIB if isinstance(available, int) else None,
                   "note": "Private bytes are commit, not physical use; current GUI/T10 memory is already reflected in available physical and is not subtracted again."},
        "incomplete_process_queries": missing, "warnings": warnings,
    }


def _load_g(Q=None):
    # Importing these frozen files defines APIs only. Never call their main,
    # stage, spawn, Job, kill, write_json or append_jsonl functions.
    for path, expected in ((ROOT / "tools/cfo_phase74_guard_v1.py", GUARD_SHA),
                           (ROOT / "tools/cfo_native_guard_v3.py", G_SHA)):
        if digest(path.read_bytes()) != expected:
            raise RuntimeError("Frozen read-only guard changed: " + str(path))
    if Q is not None:
        G = Q.G
        if canon(G.__file__) != canon(ROOT / "tools/cfo_native_guard_v3.py"):
            raise RuntimeError("Unexpected Q.G module path")
        return G
    spec = importlib.util.spec_from_file_location("_link010_readonly_g", ROOT / "tools/cfo_native_guard_v3.py")
    module = importlib.util.module_from_spec(spec)
    exec(compile((ROOT / "tools/cfo_native_guard_v3.py").read_bytes(), str(spec.origin), "exec"), module.__dict__)
    return module


def _table(G):
    """Toolhelp enumeration, unlike legacy table(), does not hide query errors."""
    handle = G.k.CreateToolhelp32Snapshot(G.SNAP, 0)
    if handle in (0, ctypes.c_void_p(-1).value):
        raise RuntimeError(G.err("CreateToolhelp32Snapshot"))
    result = {}
    try:
        entry = G.PE()
        entry.size = ctypes.sizeof(entry)
        if not G.k.Process32FirstW(handle, ctypes.byref(entry)):
            raise RuntimeError(G.err("Process32FirstW"))
        while True:
            result[int(entry.pid)] = {"pid": int(entry.pid), "parent_pid": int(entry.ppid),
                                      "image_name": str(entry.image)}
            ctypes.set_last_error(0)
            if not G.k.Process32NextW(handle, ctypes.byref(entry)):
                if ctypes.get_last_error() != 18:  # ERROR_NO_MORE_FILES
                    raise RuntimeError(G.err("Process32NextW"))
                break
        return result
    finally:
        G.k.CloseHandle(handle)


def _command_line(G, pid):
    """Read-only 64-bit Windows PEB query; unsupported layouts fail closed."""
    import ctypes.wintypes as w
    if ctypes.sizeof(ctypes.c_void_p) != 8:
        raise RuntimeError("64-bit process-parameter reader required")
    ntdll = ctypes.WinDLL("ntdll")
    query = ntdll.NtQueryInformationProcess
    query.argtypes = [w.HANDLE, w.ULONG, ctypes.c_void_p, w.ULONG, ctypes.POINTER(w.ULONG)]
    query.restype = ctypes.c_long
    read = G.k.ReadProcessMemory
    read.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
    read.restype = w.BOOL
    handle = G.k.OpenProcess(G.QLIMIT | G.VMREAD, False, pid)
    if not handle:
        raise RuntimeError(G.err("OpenProcess command line"))
    def read_bytes(address, size):
        if not address or size < 0 or size > 65536:
            raise RuntimeError("Invalid process-parameter read")
        buffer = ctypes.create_string_buffer(size)
        got = ctypes.c_size_t()
        if not read(handle, address, buffer, size, ctypes.byref(got)) or got.value != size:
            raise RuntimeError(G.err("ReadProcessMemory"))
        return buffer.raw
    try:
        basic = ctypes.create_string_buffer(48)
        returned = w.ULONG()
        if query(handle, 0, basic, 48, ctypes.byref(returned)) != 0:
            raise RuntimeError("NtQueryInformationProcess basic failed")
        peb = struct.unpack_from("<Q", basic.raw, 8)[0]
        params = struct.unpack("<Q", read_bytes(peb + 0x20, 8))[0]
        descriptor = read_bytes(params + 0x70, 16)
        length, maximum = struct.unpack_from("<HH", descriptor)
        address = struct.unpack_from("<Q", descriptor, 8)[0]
        if length > maximum or length % 2:
            raise RuntimeError("Invalid command-line UNICODE_STRING")
        return read_bytes(address, length).decode("utf-16-le") if length else ""
    finally:
        G.k.CloseHandle(handle)


def _titles(pid):
    import ctypes.wintypes as w
    user = ctypes.WinDLL("user32", use_last_error=True)
    callback_type = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
    user.EnumWindows.argtypes = [callback_type, w.LPARAM]
    user.EnumWindows.restype = w.BOOL
    user.GetWindowThreadProcessId.argtypes = [w.HWND, ctypes.POINTER(w.DWORD)]
    user.GetWindowTextLengthW.argtypes = [w.HWND]
    user.GetWindowTextLengthW.restype = ctypes.c_int
    user.GetWindowTextW.argtypes = [w.HWND, w.LPWSTR, ctypes.c_int]
    titles = []
    @callback_type
    def visit(hwnd, _):
        owner = w.DWORD()
        user.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            text = ctypes.create_unicode_buffer(user.GetWindowTextLengthW(hwnd) + 1)
            user.GetWindowTextW(hwnd, text, len(text))
            if text.value:
                titles.append(text.value)
        return True
    if not user.EnumWindows(visit, 0):
        raise RuntimeError("EnumWindows failed")
    return titles


def _read_log(path, records):
    path = Path(path)
    before = path.stat()
    with path.open("rb") as stream:
        data = stream.read(MAX_LOG_BYTES + 1)
    after = path.stat()
    if len(data) > MAX_LOG_BYTES:
        raise RuntimeError("GUI activity log exceeds bounded reader: " + str(path))
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError("GUI activity log changed during read: " + str(path))
    records.append({"path": str(path), "bytes": len(data), "sha256": digest(data),
                    "mtime_ns": after.st_mtime_ns})
    return data.decode("utf-8-sig", errors="replace")


def _local_stamp(text):
    return dt.datetime.strptime(text.strip(), "%a %b %d %H:%M:%S %Y").astimezone().timestamp()


def gui_activity(G, table, rows, gui_log_paths=None):
    """Known GUI only: current identity/title/tree plus bound session/run evidence."""
    tree = descendant_ids(table, GUI_PID)
    result = {"tree_pids": sorted(tree), "children": [rows[p] for p in sorted(tree - {GUI_PID})],
              "editor_only_confirmed": False, "log_evidence": [], "completed_runs": [],
              "unresolved_activity": [], "cpu_is_not_compute_classifier": True}
    if GUI_PID not in table:
        result["state"] = "KNOWN_GUI_NOT_PRESENT"
        return result
    try:
        if identity(rows[GUI_PID]) != (GUI_PID, GUI_CREATION, "vivado.exe", canon(VIVADO_EXE)):
            raise RuntimeError("Known GUI PID creation identity changed")
        titles = result["window_titles"] = _titles(GUI_PID)
        if not any(canon(GUI_XPR) in canon(title) for title in titles):
            raise RuntimeError("Current GUI title does not identify I16_AddSub.xpr")
        for pid in sorted(tree - {GUI_PID}, key=lambda p: (rows[p].get("image_name", "").lower() != "java.exe", p)):
            row = rows[pid]
            parent = rows.get(row.get("parent_pid"), {})
            if row.get("creation_filetime_100ns", -1) < parent.get("creation_filetime_100ns", 2 ** 64):
                raise RuntimeError("GUI child ancestry has stale/reused PID")
            name = row.get("image_name", "").lower()
            row["command_line"] = _command_line(G, pid)
            if name == "java.exe":
                if (row.get("parent_pid") != GUI_PID
                        or "com.sigasi.lsp.server.BootstrappedLspServer" not in row["command_line"]
                        or not canon(row.get("image_path", "")).startswith(canon(r"C:\NIFPGA\programs\Vivado2021_1\tps") + "\\")):
                    raise RuntimeError("Unrecognized GUI Java child")
                row["admission_role"] = "SIGASI_EDITOR"
            elif name == "conhost.exe":
                if parent.get("admission_role") != "SIGASI_EDITOR" or canon(row.get("image_path", "")) != canon(r"C:\Windows\System32\conhost.exe"):
                    raise RuntimeError("Unrecognized GUI console child")
                row["admission_role"] = "SIGASI_EDITOR_CONSOLE"
            else:
                raise RuntimeError("GUI child is a compute tool or cannot be classified: " + str(pid) + "/" + name)
        # Exact log paths, never latest/mtime source selection. An override must
        # still bind to this GUI PID and the current session/XPR.
        paths = list(gui_log_paths) if gui_log_paths is not None else [GUI_LOG]
        if len(paths) != 1:
            raise RuntimeError("Exactly one bound GUI session log is required")
        text = _read_log(paths[0], result["log_evidence"])
        pids = re.findall(r"(?m)^# Process ID:\s*(\d+)\s*$", text)
        starts = re.findall(r"(?m)^# Start of session at:\s*(.+)$", text)
        if pids != [str(GUI_PID)] or len(starts) != 1 or canon(GUI_XPR) not in canon(text):
            raise RuntimeError("GUI log session/PID/project binding failed")
        creation_unix = GUI_CREATION / 10_000_000 - 11644473600
        if abs(_local_stamp(starts[0]) - creation_unix) > 120:
            raise RuntimeError("GUI log is not from the current PID creation")
        launch_lines = re.findall(r"(?m)^\[([^\]]+)\] Launched ([^.\r\n]+)\.\.\.\s*$", text)
        output_paths = re.findall(r"(?m)^Run output will be captured here:\s*(.+)$", text)
        if len(launch_lines) != len(output_paths):
            raise RuntimeError("GUI run launch/output records are incomplete")
        launch_commands = re.findall(r"(?m)^\s*launch_runs\b[^\r\n]*", text)
        if len(launch_commands) > len(launch_lines):
            raise RuntimeError("GUI has a pending launch_runs command without a bound run record")
        project_dir = ntpath.dirname(GUI_XPR)
        for (stamp, run_name), run_path in zip(launch_lines, output_paths):
            run_path = Path(run_path.strip())
            if not canon(run_path).startswith(canon(project_dir) + "\\"):
                raise RuntimeError("GUI run evidence escaped its project")
            log = _read_log(run_path, result["log_evidence"])
            begin = run_path.parent / ".vivado.begin.rst"
            end = run_path.parent / ".vivado.end.rst"
            begin_text = _read_log(begin, result["log_evidence"])
            _read_log(end, result["log_evidence"])
            run_pid_match = re.search(r'\bPid="(\d+)"', begin_text)
            if not run_pid_match:
                raise RuntimeError("GUI run begin marker has no PID")
            run_pid = int(run_pid_match[1])
            launch_time = _local_stamp(stamp)
            exits = re.findall(r"Exiting Vivado at (.+?)\.\.\.", log)
            if (not exits or _local_stamp(exits[-1]) < launch_time
                    or end.stat().st_mtime < begin.stat().st_mtime
                    or end.stat().st_mtime < launch_time or run_pid in table):
                raise RuntimeError("GUI run lacks matched exit/end evidence or its run PID is still present")
            result["completed_runs"].append({"name": run_name, "pid": run_pid, "log": str(run_path),
                                             "launched_local": stamp, "exit_local": exits[-1]})
        for command in ("synth_design", "opt_design", "place_design", "phys_opt_design",
                        "route_design", "write_bitstream"):
            begins = [m.start() for m in re.finditer(r"(?m)^" + command + r"(?:\s|$)", text)]
            ends = [m.start() for m in re.finditer(r"(?m)^" + command + r": Time \(s\):", text)]
            if begins and (not ends or max(ends) < max(begins)):
                raise RuntimeError("GUI has unresolved in-process computation: " + command)
        sim_starts = [m.start() for m in re.finditer(r"(?m)^(?:launch_simulation|run\s+all)\b", text)]
        sim_closes = [m.start() for m in re.finditer(r"(?m)^close_sim(?:\s|$)", text)]
        if sim_starts and (not sim_closes or max(sim_closes) < max(sim_starts)):
            raise RuntimeError("GUI simulation activity is not explicitly closed")
        result.update(state="EDITOR_ONLY_FRESHLY_VERIFIED", editor_only_confirmed=True)
    except Exception as exc:
        result["state"] = "ACTIVE_OR_UNRESOLVED"
        result["unresolved_activity"].append(str(exc))
    return result


def snapshot(stage, *, Q=None, gui_log_paths=None, slot_path=SLOT):
    """Fresh read-only stage admission. No filesystem writes and no process control."""
    started = utc()
    result = {"schema": "link010_resource_admission_v1", "stage": stage,
              "recorded_utc": started, "native_started": False, "external_processes_modified": False,
              "reuse_for_next_stage_forbidden": True, "not_an_atomic_resource_lock": True}
    try:
        if os.name != "nt":
            raise RuntimeError("Live admission is Windows only; use --self-check for pure checks")
        G = _load_g(Q)
        slot_path = Path(slot_path)
        slot_error = None
        try:
            slot_raw = slot_path.read_bytes()
            slot = json.loads(slot_raw.decode("utf-8-sig"))
        except Exception as exc:
            if stage != "post":
                raise
            slot_raw, slot, slot_error = b"", {}, repr(exc)
        table = _table(G)
        wanted = {pid for pid, r in table.items()
                  if r["image_name"].lower() in NATIVE | {"matlab.exe"}}
        wanted |= descendant_ids(table, GUI_PID)
        for pid in T10:
            wanted |= descendant_ids(table, pid)
        rows = {pid: G.detail(pid, table[pid]) for pid in sorted(wanted)}
        for pid, row in rows.items():
            if row.get("image_name", "").lower() in NATIVE and pid not in T10 and pid != GUI_PID:
                try:
                    row["command_line"] = _command_line(G, pid)
                except Exception as exc:
                    row["command_line_error"] = repr(exc)
        gui = gui_activity(G, table, rows, gui_log_paths)
        memory = G.mem()
        after = _table(G)
        after_wanted = {pid for pid, r in after.items()
                        if r["image_name"].lower() in NATIVE | {"matlab.exe"}}
        after_wanted |= descendant_ids(after, GUI_PID)
        for pid in T10:
            after_wanted |= descendant_ids(after, pid)
        stable = wanted == after_wanted and os.getpid() in table and os.getpid() in after
        for pid, row in rows.items():
            if pid not in after:
                stable = False
                continue
            again = G.detail(pid, after[pid])
            stable = stable and identity(row) == identity(again) and row.get("parent_pid") == again.get("parent_pid")
        for evidence in gui["log_evidence"]:
            path = Path(evidence["path"])
            if digest(path.read_bytes()) != evidence["sha256"]:
                stable = False
        try:
            slot_same = slot_path.read_bytes() == slot_raw
        except Exception:
            slot_same = False
        result.update(evaluate_snapshot(slot, list(rows.values()), memory=memory, gui=gui,
                                        inventory_stable=stable, slot_stable=slot_same, stage=stage))
        result.update({"grant": {"path": str(slot_path), "sha256": digest(slot_raw),
                                  "grant_id": slot.get("grant_id"), "slot": slot, "read_error": slot_error},
                       "native_identities": [r for r in rows.values() if r.get("image_name", "").lower() in NATIVE],
                       "selected_processes": list(rows.values()), "gui": gui,
                       "probe_finished_utc": utc(),
                       "guard_sha256": {"cfo_phase74_guard_v1.py": GUARD_SHA, "cfo_native_guard_v3.py": G_SHA}})
    except Exception as exc:
        result.update({"all_checks": False, "checks": {"probe_completed": False},
                       "blocking_checks": ["probe_completed"], "probe_error": repr(exc),
                       "probe_finished_utc": utc()})
    return result



def external_integrity(before, current):
    """Pure post-stage protection; manager transfer and new external work are allowed.

    This is supplementary evidence only. The wrapper's own Job-object census,
    including unknown/non-native descendants, remains the sole own-tree gate.
    """
    rows = {int(r["pid"]): r for r in current.get("selected_processes", [])}
    old = {int(r["pid"]): r for r in before.get("selected_processes", [])}
    checks = {"post_probe_completed": "probe_error" not in current,
              "post_inventory_stable": current.get("checks", {}).get("inventory_stable") is True}
    for pid, (name, creation) in T10.items():
        expected = (pid, creation, name, canon(EXPECTED_EXES[pid]))
        checks["protected_t10_unchanged_" + str(pid)] = bool(
            pid in old and pid in rows and identity(old[pid]) == expected
            and identity(rows[pid]) == expected and not rows[pid].get("query_error"))
    gui = rows.get(GUI_PID)
    expected_gui = (GUI_PID, GUI_CREATION, "vivado.exe", canon(VIVADO_EXE))
    checks["gui_if_present_keeps_known_identity"] = not gui or (
        identity(gui) == expected_gui and not gui.get("query_error")
        and (GUI_PID not in old or identity(old[GUI_PID]) == expected_gui))
    gui_ids = set(current.get("gui", {}).get("tree_pids", []))
    pair_residual, unclassified, external = [], [], []
    for row in current.get("native_identities", []):
        pid = int(row["pid"])
        if pid in T10 or (pid in gui_ids and checks["gui_if_present_keeps_known_identity"]):
            continue
        image = canon(row.get("image_path", ""))
        command = row.get("command_line", "")
        if image.startswith(canon(ROOT) + "\\") or canon(ROOT) in canon(command):
            pair_residual.append(row)
            continue
        # Other users' completed-stage/new work is not our cancellation target.
        # A readable absolute source path or external xsim image gives its scope;
        # an unclassified common-install executable does not.
        source = re.search(r'(?:^|\s)-source\s+(?:"([^"]+)"|(\S+))', command)
        source_path = (source.group(1) or source.group(2)) if source else ""
        if (source_path and ntpath.isabs(source_path)) or (
                "\\xsim.dir\\" in image and not image.startswith(canon(ROOT) + "\\")):
            external.append(row)
        else:
            unclassified.append(row)
    checks["no_visible_t11_native_residue"] = not pair_residual
    checks["no_unclassified_native_process"] = not unclassified
    checks["native_identity_queries_complete"] = all(
        r.get("image_path") and isinstance(r.get("creation_filetime_100ns"), int)
        and not r.get("query_error") for r in current.get("native_identities", []))
    return {"external_integrity_checks": checks, "all_external_checks": all(checks.values()),
            "all_checks": all(checks.values()),
            "blocking_checks": [key for key, value in checks.items() if not value],
            "visible_t11_native_residue": pair_residual, "unclassified_native_processes": unclassified,
            "new_identified_external_native": external,
            "slot_owner_budget_and_gui_editor_state_ignored_after_stage": True,
            "own_full_tree_zero_requires_wrapper_job_census": True}


def post_snapshot(before, *, Q=None, gui_log_paths=None, slot_path=SLOT):
    """Fresh end-of-stage check; a manager slot transfer cannot fail finished work."""
    current = snapshot("post", Q=Q, gui_log_paths=gui_log_paths, slot_path=slot_path)
    decision = external_integrity(before, current)
    return {"schema": "link010_post_resource_integrity_v1", **decision,
            "recorded_utc": current.get("recorded_utc"), "probe_finished_utc": current.get("probe_finished_utc"),
            "native_started": False, "external_processes_modified": False,
            "current_snapshot": current}


def self_check():
    """Pure regression examples: does not import G, query processes or read GUI logs."""
    slot = {"manager_thread_id": MANAGER, "shared_slot_owner": "T11_T13",
            "granted_astra": ASTRA, "granted_luna": LUNA, "grant_id": "SELF_CHECK",
            "shared_slot_status": "GRANTED", "global_vivado_main_limit": 2, "per_pair_limit": 1}
    rows = [{"pid": pid, "parent_pid": 0 if pid == 34768 else 34768,
             "image_name": name, "creation_filetime_100ns": creation,
             "private_usage_bytes": GIB, "image_path": EXPECTED_EXES[pid]} for pid, (name, creation) in T10.items()]
    gui_row = {"pid": GUI_PID, "parent_pid": 1, "image_name": "vivado.exe",
               "creation_filetime_100ns": GUI_CREATION, "private_usage_bytes": GIB, "image_path": VIVADO_EXE}
    child = {"pid": 18096, "parent_pid": GUI_PID, "image_name": "java.exe",
             "creation_filetime_100ns": GUI_CREATION + 1, "private_usage_bytes": GIB // 2}
    gui = {"tree_pids": [GUI_PID, 18096], "editor_only_confirmed": True}
    def run(s=slot, r=None, g=gui, available=10 * GIB, stable=True):
        return evaluate_snapshot(s, r or rows + [gui_row, child], memory={"available_physical_bytes": available},
                                 gui=g, inventory_stable=stable, slot_stable=True, stage="create")
    checks = {
        "known_editor_not_counted_as_compute": run()["all_checks"],
        "editor_child_private_memory_included": run()["memory"]["gui_and_editor_children_private_bytes"] == GIB + GIB // 2,
        "hold_denied": not run({**slot, "shared_slot_status": "HOLD"})["all_checks"],
        "other_owner_denied": not run({**slot, "shared_slot_owner": "SYNC_FRONTEND"})["all_checks"],
        "wrong_luna_denied": not run({**slot, "granted_luna": "other"})["all_checks"],
        "reused_t10_pid_denied": not run(r=[{**rows[0], "creation_filetime_100ns": 1}, rows[1], gui_row, child])["all_checks"],
        "unknown_compute_denied": not run(r=rows + [gui_row, child, {"pid": 555, "image_name": "xelab.exe", "parent_pid": 3, "creation_filetime_100ns": 5, "private_usage_bytes": 1}])["all_checks"],
        "unresolved_gui_denied": not run(g={**gui, "editor_only_confirmed": False})["all_checks"],
        "unstable_inventory_denied": not run(stable=False)["all_checks"],
        "recommendation_is_warning_only": run(available=5 * GIB)["all_checks"] and bool(run(available=5 * GIB)["warnings"]),
        "severe_memory_pressure_denied": not run(available=GIB // 4)["all_checks"],
        "windows_path_aliases_equal": canon("D:/x/Y") == canon(r"d:\X\y"),
    }
    base = {"selected_processes": rows + [gui_row, child],
            "native_identities": rows + [gui_row], "gui": gui,
            "checks": {"inventory_stable": True}}
    post = external_integrity(base, base)
    wrong_path = [{**rows[0], "image_path": r"D:\wrong\vivado.exe"}, rows[1], gui_row, child]
    checks["wrong_absolute_executable_denied"] = not run(r=wrong_path)["all_checks"]
    checks["post_ignores_slot_and_gui_editor_changes"] = external_integrity(
        base, {**base, "checks": {**base["checks"], "manager_grants_t11_owner": False},
               "gui": {**gui, "editor_only_confirmed": False}})["all_checks"]
    checks["post_protects_t10_identity"] = not external_integrity(
        base, {**base, "selected_processes": wrong_path})["all_checks"]
    checks["post_allows_user_to_close_known_gui"] = external_integrity(
        base, {**base, "selected_processes": rows, "native_identities": rows,
               "gui": {"tree_pids": []}})["all_checks"]
    own = {"pid": 666, "parent_pid": 1, "image_name": "vivado.exe",
           "image_path": VIVADO_EXE, "creation_filetime_100ns": GUI_CREATION + 3,
           "command_line": 'vivado.exe -source "D:/008_MA_Dev/T11_CFO/vivado/link010_project.tcl"'}
    checks["post_detects_visible_pair_native_residue"] = not external_integrity(
        base, {**base, "native_identities": base["native_identities"] + [own]})["all_checks"]
    other = {**own, "command_line": 'vivado.exe -source "D:/008_MA_Dev/Sync_Frontend/vivado/check.tcl"'}
    checks["post_allows_identified_new_external_work"] = external_integrity(
        base, {**base, "native_identities": base["native_identities"] + [other]})["all_checks"]
    checks["post_default_pass"] = post["all_checks"]
    return {"schema": "link010_admission_self_check_v1", "checks": checks,
            "all_checks": all(checks.values()), "native_started": False,
            "live_process_or_gui_queries": False, "filesystem_writes": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--snapshot", action="store_true", help="One read-only live snapshot; defaults to create")
    parser.add_argument("--stage", choices=("create", "simulate"))
    args = parser.parse_args()
    if not args.self_check and not args.stage and not args.snapshot:
        parser.error("Specify --self-check or --stage; neither mode starts any native tool")
    value = self_check() if args.self_check else snapshot(args.stage or "create")
    print(json.dumps(value, ensure_ascii=False, indent=2))
    return 0 if value["all_checks"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
