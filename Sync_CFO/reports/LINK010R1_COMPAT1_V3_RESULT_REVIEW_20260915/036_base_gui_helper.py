"""LINK010R1 read-only admission repair for one GUI session with project switches.

The original admission helper bound every historical GUI run to the currently
displayed XPR.  This version keeps the exact PID/executable/creation and child
classification checks, but parses the current GUI log in order so each launch
is bound to the open_project that was active at that point.  It never controls
the GUI or any external process.
"""
from pathlib import Path
import argparse
import ast
import datetime as dt
import hashlib
import importlib.util
import json
import ntpath
import re


ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
BASE_PATH = ROOT / "tools/link010_admission.py"
RUNNER_PATH = ROOT / "tools/cfo_link010r1_guard_v2_repair.py"


def load_base():
    spec = importlib.util.spec_from_file_location("link010_admission_frozen", BASE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


A = load_base()


def file_sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def canon(path):
    return A.canon(path)


def _argument_path(text):
    value = text.strip()
    if value.startswith("{") and value.endswith("}"):
        value = value[1:-1]
    elif len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    return value.strip()


def _current_xpr(titles):
    for title in titles:
        start = title.find("[")
        end = title.rfind("]")
        if start >= 0 and end > start:
            value = title[start + 1:end]
            if value.lower().endswith(".xpr"):
                return value
    return None


def project_history(text):
    current = None
    opens = []
    closes = []
    launch_commands = []
    simulation_commands = []
    launches = []
    pending = None
    for number, line in enumerate(text.splitlines(), 1):
        match = re.match(r'^\s*open_project\s+(\{[^}]+\}|"[^"]+"|\S+)\s*$', line)
        if match:
            current = _argument_path(match.group(1))
            opens.append({"line": number, "project": current})
        elif re.match(r"^\s*close_project(?:\s|$)", line):
            closes.append({"line": number, "project": current})
            current = None
        if re.match(r"^\s*launch_runs\b", line):
            launch_commands.append({"line": number, "project": current, "command": line.strip()})
        if re.match(r"^\s*(?:launch_simulation|run\s+all)\b", line):
            simulation_commands.append({"line": number, "project": current, "command": line.strip()})
        match = re.match(r"^\[([^\]]+)\]\s+Launched\s+([^\.\r\n]+)\.\.\.\s*$", line)
        if match:
            pending = {
                "line": number,
                "stamp": match.group(1),
                "name": match.group(2).strip(),
                "project": current,
                "output": None,
            }
            launches.append(pending)
        match = re.match(r"^Run output will be captured here:\s*(.+?)\s*$", line)
        if match and pending is not None and pending["output"] is None:
            pending["output"] = match.group(1).strip()
    return {
        "opens": opens,
        "closes": closes,
        "launch_commands": launch_commands,
        "simulation_commands": simulation_commands,
        "launches": launches,
        "last_project": current,
    }


def _gui_activity(G, table, rows, gui_log_paths=None):
    tree = A.descendant_ids(table, A.GUI_PID)
    result = {
        "tree_pids": sorted(tree),
        "children": [rows[p] for p in sorted(tree - {A.GUI_PID})],
        "editor_only_confirmed": False,
        "log_evidence": [],
        "completed_runs": [],
        "unresolved_activity": [],
        "cpu_is_not_compute_classifier": True,
    }
    if A.GUI_PID not in table:
        result["state"] = "KNOWN_GUI_NOT_PRESENT"
        return result
    try:
        gui_row = rows[A.GUI_PID]
        expected_gui = (A.GUI_PID, A.GUI_CREATION, "vivado.exe", A.canon(A.VIVADO_EXE))
        if A.identity(gui_row) != expected_gui:
            raise RuntimeError("Known GUI PID creation identity changed")
        titles = result["window_titles"] = A._titles(A.GUI_PID)
        title_xpr = _current_xpr(titles)
        if not title_xpr:
            raise RuntimeError("Current GUI title has no XPR identity")
        result["current_title_xpr"] = title_xpr

        for pid in sorted(tree - {A.GUI_PID}, key=lambda p: (rows[p].get("image_name", "").lower() != "java.exe", p)):
            row = rows[pid]
            parent = rows.get(row.get("parent_pid"), {})
            if row.get("creation_filetime_100ns", -1) < parent.get("creation_filetime_100ns", 2 ** 64):
                raise RuntimeError("GUI child ancestry has stale/reused PID")
            name = row.get("image_name", "").lower()
            row["command_line"] = A._command_line(G, pid)
            if name == "java.exe":
                if (
                    row.get("parent_pid") != A.GUI_PID
                    or "com.sigasi.lsp.server.BootstrappedLspServer" not in row["command_line"]
                    or not A.canon(row.get("image_path", "")).startswith(A.canon(r"C:\NIFPGA\programs\Vivado2021_1\tps") + chr(92))
                ):
                    raise RuntimeError("Unrecognized GUI Java child")
                row["admission_role"] = "SIGASI_EDITOR"
            elif name == "conhost.exe":
                if parent.get("admission_role") != "SIGASI_EDITOR" or A.canon(row.get("image_path", "")) != A.canon(r"C:\Windows\System32\conhost.exe"):
                    raise RuntimeError("Unrecognized GUI console child")
                row["admission_role"] = "SIGASI_EDITOR_CONSOLE"
            else:
                raise RuntimeError("GUI child is a compute tool or cannot be classified: " + str(pid) + "/" + name)

        paths = list(gui_log_paths) if gui_log_paths is not None else [A.GUI_LOG]
        if len(paths) != 1:
            raise RuntimeError("Exactly one bound GUI session log is required")
        text = A._read_log(paths[0], result["log_evidence"])
        pids = re.findall(r"(?m)^# Process ID:\s*(\d+)\s*$", text)
        starts = re.findall(r"(?m)^# Start of session at:\s*(.+)$", text)
        if pids != [str(A.GUI_PID)] or len(starts) != 1:
            raise RuntimeError("GUI log session/PID binding failed")
        creation_unix = A.GUI_CREATION / 10_000_000 - 11644473600
        if abs(A._local_stamp(starts[0]) - creation_unix) > 120:
            raise RuntimeError("GUI log is not from the current PID creation")

        history = project_history(text)
        result["project_history"] = history
        if canon(history.get("last_project", "")) != canon(title_xpr):
            raise RuntimeError("Current GUI title does not identify the last open_project")
        if len(history["launch_commands"]) != len(history["launches"]):
            raise RuntimeError("GUI launch command/output records are incomplete")
        project_at_launch = [x.get("project") for x in history["launches"]]
        if any(not x for x in project_at_launch):
            raise RuntimeError("A GUI launch has no bound open_project")

        for record in history["launches"]:
            run_path = Path(record["output"]) if record.get("output") else None
            if run_path is None:
                raise RuntimeError("GUI launch has no output path")
            project_dir = ntpath.dirname(record["project"])
            if not canon(run_path).startswith(canon(project_dir) + chr(92)):
                raise RuntimeError("GUI run evidence escaped its bound project: " + str(run_path))
            log = A._read_log(run_path, result["log_evidence"])
            begin = run_path.parent / ".vivado.begin.rst"
            end = run_path.parent / ".vivado.end.rst"
            begin_text = A._read_log(begin, result["log_evidence"])
            A._read_log(end, result["log_evidence"])
            run_pid_match = re.search(r'\bPid="(\d+)"', begin_text)
            if not run_pid_match:
                raise RuntimeError("GUI run begin marker has no PID")
            run_pid = int(run_pid_match[1])
            launch_time = A._local_stamp(record["stamp"])
            exits = re.findall(r"Exiting Vivado at (.+?)\.\.\.", log)
            if (
                not exits
                or A._local_stamp(exits[-1]) < launch_time
                or end.stat().st_mtime < begin.stat().st_mtime
                or end.stat().st_mtime < launch_time
                or run_pid in table
            ):
                raise RuntimeError("GUI run lacks matched natural exit/end evidence or its run PID is still present")
            result["completed_runs"].append(
                {
                    "name": record["name"],
                    "pid": run_pid,
                    "project": record["project"],
                    "log": str(run_path),
                    "launched_local": record["stamp"],
                    "exit_local": exits[-1],
                }
            )

        for command in ("synth_design", "opt_design", "place_design", "phys_opt_design", "route_design", "write_bitstream"):
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


def snapshot(stage, *, Q=None, gui_log_paths=None, slot_path=A.SLOT):
    old = A.gui_activity
    A.gui_activity = _gui_activity
    try:
        result = A.snapshot(stage, Q=Q, gui_log_paths=gui_log_paths, slot_path=slot_path)
    finally:
        A.gui_activity = old
    slot = result.get("grant", {}).get("slot", {})
    runner_sha = file_sha256(RUNNER_PATH) if RUNNER_PATH.exists() else None
    exact = {
        "job": slot.get("authorized_job") == "CFO-LINK010R1",
        "manifest": slot.get("manifest_sha256") == "F01D289223D90FE71F3767B1030B35809AA1C651FC249EDA3362AB5E455F3069",
        "runner": slot.get("script_sha256") == runner_sha,
    }
    result["r1_exact_grant_checks"] = exact
    result["all_checks"] = bool(result.get("all_checks")) and all(exact.values())
    result["blocking_checks"] = list(result.get("blocking_checks", []))
    result["blocking_checks"] += ["r1_exact_grant_" + key for key, value in exact.items() if not value]
    return result


def post_snapshot(before, *, Q=None, gui_log_paths=None, slot_path=A.SLOT):
    old = A.gui_activity
    A.gui_activity = _gui_activity
    try:
        return A.post_snapshot(before, Q=Q, gui_log_paths=gui_log_paths, slot_path=slot_path)
    finally:
        A.gui_activity = old


def self_check():
    good = "\n".join(
        [
            "open_project D:/old/I16.xpr",
            "launch_runs synth_1 -jobs 16",
            "[Mon Sep 14 22:51:26 2026] Launched synth_1...",
            "Run output will be captured here: D:/old/I16.runs/synth_1/runme.log",
            "close_project",
            "open_project D:/current/Sync_Frontend.xpr",
        ]
    )
    bad = "\n".join(["open_project D:/current/Sync_Frontend.xpr", "launch_runs synth_1 -jobs 16"])
    good_h = project_history(good)
    bad_h = project_history(bad)
    checks = {
        "syntax_base": ast.parse(BASE_PATH.read_text("utf-8")) is not None,
        "good_history_binds_old_project": good_h["last_project"] == "D:/current/Sync_Frontend.xpr" and good_h["launches"][0]["project"] == "D:/old/I16.xpr",
        "bad_unmatched_launch_rejected_by_parser": len(bad_h["launch_commands"]) == 1 and len(bad_h["launches"]) == 0,
        "runner_exists": RUNNER_PATH.exists(),
    }
    return {"schema": "link010r1_admission_repair_self_check_v1", "checks": checks, "all_checks": all(checks.values()), "native_started": False, "external_processes_modified": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--stage", choices=("create", "simulate"))
    args = parser.parse_args()
    if args.self_check:
        value = self_check()
    elif args.stage:
        value = snapshot(args.stage)
    else:
        parser.error("Specify --self-check or --stage")
    print(json.dumps(value, ensure_ascii=False, indent=2))
    return 0 if value.get("all_checks") else 2


if __name__ == "__main__":
    raise SystemExit(main())
