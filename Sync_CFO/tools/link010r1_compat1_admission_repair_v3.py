"""Read-only GUI/process admission repair for the reviewed LINK010R1 compat1 v3 entrypoint."""
from pathlib import Path
import ast
import hashlib
import json
import types


ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
BASE_HELPER_PATH = ROOT / "tools/link010r1_admission_v2_repair.py"
BASE_HELPER_SHA = "CE1D6B786FE9DD495616A9F5B79155BA2D6653B5B4320DFC897500679060ABD3"
RUNNER_PATH = ROOT / "tools/cfo_link010r1_compat1_guard_v3_repair.py"
TCL_PATH = ROOT / "vivado/link010r1_compat1_project_v2_repair.tcl"
TCL_SHA = "B106E35A3A6FF3F17A61863ADBD897C1C620D36DACDC84E944F5D08A020289E6"
LOCK_PATH = ROOT / "docs/LINK010R1_COMPAT1_SOURCE_LOCK.json"
LOCK_SHA = "4245E75E0D3049F9F7E92EDCF68B4E286BE30DE59747D8A03A0BBE14C2C3FFA3"
AUTHORIZED_JOB = "CFO-LINK010R1-COMPAT1"
ORIGINAL_V1_GUARD = ROOT / "tools/cfo_link010r1_guard_v1.py"
ORIGINAL_V1_GUARD_SHA = "9654C5B8B9ED5D252C9CA4F3008A08590CF972D332678FE876F70F097D887E84"
ORIGINAL_R1_REPAIR = ROOT / "tools/cfo_link010r1_guard_v2_repair.py"
ORIGINAL_R1_REPAIR_SHA = "486C678D4BD0EEC29942BBCFD3A884A7A59CC025B01A63F68FD48C6CEA65636F"


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


def dependency_checks(runner_path=RUNNER_PATH):
    rows = {
        "base_gui_helper": {"path": str(BASE_HELPER_PATH), "approved_sha256": BASE_HELPER_SHA},
        "original_v1_guard": {"path": str(ORIGINAL_V1_GUARD), "approved_sha256": ORIGINAL_V1_GUARD_SHA},
        "original_r1_repair": {"path": str(ORIGINAL_R1_REPAIR), "approved_sha256": ORIGINAL_R1_REPAIR_SHA},
        "compat1_tcl": {"path": str(TCL_PATH), "approved_sha256": TCL_SHA},
        "compat1_source_lock": {"path": str(LOCK_PATH), "approved_sha256": LOCK_SHA},
    }
    for row in rows.values():
        path = Path(row["path"])
        actual = file_sha256(path) if path.exists() else None
        row["loaded_sha256"] = actual
        row["matches"] = bool(actual and row["approved_sha256"] and actual == row["approved_sha256"])
    rows["runner_entry"] = {"path": str(runner_path), "loaded_sha256": file_sha256(runner_path) if Path(runner_path).exists() else None,
                             "matches": Path(runner_path).exists()}
    return rows


def snapshot(stage, *, Q=None, gui_log_paths=None, slot_path=BASE.A.SLOT):
    if stage != "simulate":
        raise ValueError("compat1 v3 admission is simulate-only")
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
        "allowed_stages": slot.get("allowed_stages") == ["simulate"],
    }
    deps = dependency_checks()
    exact["dependencies"] = all(row.get("matches") for key, row in deps.items() if key != "runner_entry")
    result["compat1_v3_exact_grant_checks"] = exact
    result["compat1_v3_dependency_checks"] = deps
    result["all_checks"] = bool(result.get("all_checks")) and all(exact.values())
    result["blocking_checks"] = list(result.get("blocking_checks", []))
    result["blocking_checks"] += ["compat1_v3_exact_grant_" + key for key, value in exact.items() if not value]
    return result


def post_snapshot(before, *, Q=None, gui_log_paths=None, slot_path=BASE.A.SLOT):
    old = BASE.A.gui_activity
    BASE.A.gui_activity = BASE._gui_activity
    try:
        return BASE.A.post_snapshot(before, Q=Q, gui_log_paths=gui_log_paths, slot_path=slot_path)
    finally:
        BASE.A.gui_activity = old


def self_check():
    deps = dependency_checks()
    checks = {
        "base_helper_sha": deps["base_gui_helper"]["matches"],
        "original_v1_sha": deps["original_v1_guard"]["matches"],
        "original_r1_repair_sha": deps["original_r1_repair"]["matches"],
        "compat_tcl_sha": deps["compat1_tcl"]["matches"],
        "compat_lock_sha": deps["compat1_source_lock"]["matches"],
        "runner_present": RUNNER_PATH.is_file(),
        "simulate_only": True,
        "base_syntax": ast.parse(BASE_HELPER_PATH.read_text("utf-8")) is not None,
    }
    return {"schema": "link010r1_compat1_admission_v3_self_check_v1", "checks": checks,
            "all_checks": all(checks.values()), "native_started": False,
            "external_processes_modified": False, "dependencies": deps}
