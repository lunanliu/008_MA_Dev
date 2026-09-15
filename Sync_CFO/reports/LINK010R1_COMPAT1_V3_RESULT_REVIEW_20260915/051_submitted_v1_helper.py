"""Read-only GUI/process admission repair for the LINK010R1 compat1 retry."""
from pathlib import Path
import ast
import hashlib
import json
import types


ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
BASE_HELPER_PATH = ROOT / "tools/link010r1_admission_v2_repair.py"
BASE_HELPER_SHA = "CE1D6B786FE9DD495616A9F5B79155BA2D6653B5B4320DFC897500679060ABD3"
RUNNER_PATH = ROOT / "tools/cfo_link010r1_compat1_guard.py"
TCL_PATH = ROOT / "vivado/link010r1_compat1_project.tcl"
LOCK_PATH = ROOT / "docs/LINK010R1_COMPAT1_SOURCE_LOCK.json"
LOCK_SHA = "4245E75E0D3049F9F7E92EDCF68B4E286BE30DE59747D8A03A0BBE14C2C3FFA3"
AUTHORIZED_JOB = "CFO-LINK010R1-COMPAT1"


def file_sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def load_exact(name, path, approved_sha):
    path = Path(path)
    observed = file_sha256(path)
    if observed != approved_sha:
        raise RuntimeError(f"dependency SHA mismatch: {path} {observed} != {approved_sha}")
    source = path.read_bytes()
    module = types.ModuleType(name)
    module.__file__ = str(path)
    exec(compile(source, str(path), "exec"), module.__dict__)
    if file_sha256(path) != approved_sha:
        raise RuntimeError(f"dependency SHA changed during load: {path}")
    return module


BASE = load_exact("link010r1_admission_v2_repair_frozen", BASE_HELPER_PATH, BASE_HELPER_SHA)


def snapshot(stage, *, Q=None, gui_log_paths=None, slot_path=BASE.A.SLOT):
    if stage != "simulate":
        raise ValueError("compat1 admission is simulate-only")
    old = BASE.A.gui_activity
    BASE.A.gui_activity = BASE._gui_activity
    try:
        result = BASE.A.snapshot(stage, Q=Q, gui_log_paths=gui_log_paths, slot_path=slot_path)
    finally:
        BASE.A.gui_activity = old
    slot = result.get("grant", {}).get("slot", {})
    exact = {
        "job": slot.get("authorized_job") == AUTHORIZED_JOB,
        "manifest": slot.get("manifest_sha256") == LOCK_SHA,
        "runner": slot.get("script_sha256") == file_sha256(RUNNER_PATH) if RUNNER_PATH.exists() else False,
    }
    result["compat1_exact_grant_checks"] = exact
    result["all_checks"] = bool(result.get("all_checks")) and all(exact.values())
    result["blocking_checks"] = list(result.get("blocking_checks", []))
    result["blocking_checks"] += ["compat1_exact_grant_" + k for k, v in exact.items() if not v]
    return result


def post_snapshot(before, *, Q=None, gui_log_paths=None, slot_path=BASE.A.SLOT):
    old = BASE.A.gui_activity
    BASE.A.gui_activity = BASE._gui_activity
    try:
        return BASE.A.post_snapshot(before, Q=Q, gui_log_paths=gui_log_paths, slot_path=slot_path)
    finally:
        BASE.A.gui_activity = old


def self_check():
    checks = {
        "base_helper_sha": BASE_HELPER_PATH.exists() and file_sha256(BASE_HELPER_PATH) == BASE_HELPER_SHA,
        "compat_lock_sha": LOCK_PATH.exists() and file_sha256(LOCK_PATH) == LOCK_SHA,
        "compat_lock_members": False,
        "compat_tb_present": (ROOT / "sim/tb/cfo_estimator_link_r1_compat1_tb.sv").is_file(),
        "runner_present": RUNNER_PATH.is_file(),
        "tcl_present": TCL_PATH.is_file(),
        "reused_xpr_present": (ROOT / "vivado/CFO_LINK010R1/CFO_LINK010R1.xpr").is_file(),
        "simulate_only": True,
        "base_syntax": ast.parse((BASE_HELPER_PATH).read_text("utf-8")) is not None,
    }
    if checks["compat_lock_sha"]:
        lock = json.loads(LOCK_PATH.read_text("utf-8-sig"))
        checks["compat_lock_members"] = (
            len(lock.get("project_members", [])) == 25
            and lock.get("simulation_top") == "cfo_estimator_link_tb"
            and any(x.get("path") == "sim/tb/cfo_estimator_link_r1_compat1_tb.sv" for x in lock.get("files", []))
        )
    return {
        "schema": "link010r1_compat1_admission_self_check_v1",
        "checks": checks,
        "all_checks": all(checks.values()),
        "native_started": False,
        "external_processes_modified": False,
    }
