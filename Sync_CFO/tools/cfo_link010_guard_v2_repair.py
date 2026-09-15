"""LINK010 execution-only repair: reuse a verified fast create checkpoint and run simulate once.

The frozen v1 controller rejected the completed create because the native process
exited before one post-ready telemetry sample could be collected.  This repair
does not recreate the project and does not change RTL, vectors, thresholds, or
the native Tcl flow.  It accepts only the existing native create evidence and
then uses the frozen stage guard for the single required simulate stage.
"""
from pathlib import Path
import argparse
import datetime as dt
import importlib.util
import json
import shutil


ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
PARENT = ROOT / "work/CFO_LINK010"
V1_PATH = ROOT / "tools/cfo_link010_guard_v1.py"
V1_SHA = "9C34DD60865CBBCE90B1443AF8A6934AB830371598D8ADA6DAB9B297EB39CB9B"


def load_v1():
    spec = importlib.util.spec_from_file_location("link010_guard_v1_frozen", V1_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


V = load_v1()


def read_json(path):
    return json.loads(Path(path).read_text("utf-8-sig"))


def checkpoint(old):
    completion = read_json(old / "ATTEMPT_COMPLETION.json")
    result = read_json(old / "create_result.json")
    verify = result.get("verify", {})
    parsed = verify.get("parsed") or {}
    markers = result.get("markers", {})
    census = result.get("final_census_before_close", {})
    source_check = result.get("source_check", {})
    checks = {
        "old_completion_is_create_block": completion.get("status") == "BLOCKED_AFTER_CREATE",
        "old_stage_is_wrapper_fail_only": result.get("status") == "FAIL",
        "native_exit_zero": result.get("native_exit_code_final") == 0,
        "binding_succeeded": bool(result.get("binding_succeeded")),
        "natural_zero_event": bool(result.get("events", {}).get("zero")),
        "native_not_terminated": not result.get("termination_requested_by_controller"),
        "no_controller_errors": not result.get("controller_errors"),
        "ready_marker": bool(markers.get("ready", {}).get("found")),
        "done_marker": bool(markers.get("done", {}).get("found")),
        "empty_job_census": bool(census.get("empty_verified")) and census.get("active_accounting", {}).get("active_processes") == 0,
        "source_check_pass": bool(source_check.get("all_checks")),
        "source_vector_verify_pass": verify.get("exit_code") == 0 and parsed.get("status") == "LINK010_SOURCE_VECTOR_PASS",
        "project_identity_pass": parsed.get("project_identity") == "PASS",
        "fast_exit_telemetry_is_only_defect": result.get("stable_telemetry_samples") == 0 and result.get("unstable_after_ready_samples", 0) <= 3,
        "xpr_exists": V.XPR.exists(),
    }
    return {
        "schema": "link010_create_checkpoint_repair_v1",
        "old_attempt": str(old),
        "old_completion_status": completion.get("status"),
        "old_stage_status": result.get("status"),
        "accepted": all(checks.values()),
        "checks": checks,
        "reason": "Native create completed with exit 0 and an empty Job; v1 lacked a post-ready stable sample because the stage completed in about 12 seconds.",
        "native_create_result": {
            "native_exit_code_final": result.get("native_exit_code_final"),
            "ready_pid": result.get("ready_pid"),
            "stable_telemetry_samples": result.get("stable_telemetry_samples"),
            "unstable_after_ready_samples": result.get("unstable_after_ready_samples"),
            "launch_to_zero_seconds": result.get("launch_to_zero_seconds"),
            "peak_job_private_commit_bytes": result.get("job_extended_at_loop_end", {}).get("peak_job_private_commit_bytes"),
            "final_census_empty_verified": census.get("empty_verified"),
        },
        "source_verify": verify,
    }


def copy_reused(old, dst):
    names = [
        "ATTEMPT_COMPLETION.json", "ATTEMPT_ARTIFACT_MANIFEST.json", "EXECUTION_FREEZE.json",
        "create_result.json", "create.log", "create.jou", "create.stdout.log",
        "create.stderr.log", "create.samples.jsonl", "create_actual_sources.csv",
        "create_project_identity.txt", "controller_events.jsonl",
    ]
    rows = []
    for name in names:
        src = old / name
        if not src.exists():
            rows.append({"name": name, "exists": False})
            continue
        out = dst / name
        shutil.copy2(src, out)
        rows.append(V.info(out))
    return rows


def old_projects():
    names = ["CFO_SYNC", "CFO_COORD", "CFO_PHASE74", "CFO_FFT256", "CFO_BACKEND74", "CFO_FFT2048", "CFO_FRONT2048"]
    return {str(ROOT / "vivado" / n / (n + ".xpr")): V.info(ROOT / "vivado" / n / (n + ".xpr")) for n in names}


def sim_outputs_absent():
    names = ["xvlog.log", "compile.log", "elaborate.log", "xelab.log", "simulate.log", "xsim.log", "xvlog.prj"]
    return not any((V.SIM / name).exists() for name in names)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--resume-create", required=True)
    args = ap.parse_args()
    old = Path(args.resume_create).resolve()
    if not old.is_dir() or old.parent != PARENT.resolve():
        raise SystemExit("resume-create must be an existing direct child of work/CFO_LINK010")

    PARENT.mkdir(exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    attempt = PARENT / f"attempt_{stamp}_luna_repair_v1"
    attempt.mkdir()
    shutil.copy2(V1_PATH, attempt / "cfo_link010_guard_v1_original_frozen.py")
    shutil.copy2(Path(__file__), attempt / "cfo_link010_guard_v2_repair_frozen.py")
    reused = attempt / "reused_create"
    reused.mkdir()
    reused_rows = copy_reused(old, reused)
    ep = attempt / "controller_events.jsonl"
    V.wjson(attempt / "report_clock.json", {"thread_id": "01a076f0-d8c0-72a0-8371-cb2ff29c1b28", "status": "ACTIVE", "started_utc": V.Q.utc(), "interval_minutes": 15})

    cp = checkpoint(old)
    lock, lc = V.check_lock()
    verify_create = V.verify(old, "create")
    admission = V.A.snapshot("simulate", Q=V.Q)
    oldx = old_projects()
    pre_checks = {
        "repair_controller_v1_hash": V.info(V1_PATH).get("sha256") == V1_SHA,
        "source_lock": lc["all_checks"],
        "reused_create_checkpoint": cp["accepted"],
        "create_checkpoint_reverify": verify_create.get("exit_code") == 0,
        "fresh_xpr_present": V.XPR.exists(),
        "simulation_outputs_absent": sim_outputs_absent(),
        "admission": admission.get("all_checks", False),
        "old_projects_present": all(row.get("exists") for row in oldx.values()),
        "planned_memory_gate": admission.get("memory", {}).get("available_physical_bytes", 0) >= 6 * 1024 ** 3,
    }
    fr = {
        "schema": "link010_execution_repair_freeze_v1",
        "job_id": "CFO-LINK010",
        "utc": V.Q.utc(),
        "attempt": str(attempt),
        "repair_controller": V.info(Path(__file__)),
        "original_frozen_controller": V.info(V1_PATH),
        "original_controller_sha256": V1_SHA,
        "reused_create_attempt": str(old),
        "reused_create_checkpoint": cp,
        "source_lock": lc,
        "project": {key: lock[key] for key in ["part", "hardware_top", "simulation_top", "project_members"]},
        "old_projects": oldx,
        "preflight_verify_create": verify_create,
        "admission": admission,
        "reused_create_files": reused_rows,
        "commands": {"simulate": V.command(attempt, "simulate")},
        "hard_timeout_seconds": {"simulate": 600},
        "repair_scope": "Execution wrapper only: preserve v1 create, run simulate once; no RTL, vector, threshold, hierarchy, source-lock, or Tcl algorithm changes.",
        "checks": pre_checks,
    }
    freeze_sha = V.wjson(attempt / "EXECUTION_FREEZE.json", fr)
    V.Q.event(ep, "execution_repair_freeze_written", sha256=freeze_sha, reused_create=str(old))
    completion = {
        "schema": "link010_completion_repair_v1",
        "attempt": str(attempt),
        "execution_freeze_sha256": freeze_sha,
        "status": "BLOCKED_REPAIR_PREFLIGHT",
        "native_started": False,
        "stages": {"create_reused_checkpoint": cp},
        "checks": pre_checks,
        "repair_scope": fr["repair_scope"],
    }
    if not all(pre_checks.values()):
        return V.artifact_manifest(attempt, completion)

    # A fresh slot/process/source check is mandatory immediately before the only native launch.
    admission2 = V.A.snapshot("simulate", Q=V.Q)
    _, lc2 = V.check_lock()
    V.wjson(attempt / "PRE_SIMULATE_ADMISSION.json", admission2)
    V.wjson(attempt / "PRE_SIMULATE_SOURCE_CHECK.json", lc2)
    if not admission2.get("all_checks") or not lc2.get("all_checks") or admission2.get("memory", {}).get("available_physical_bytes", 0) < 6 * 1024 ** 3:
        completion.update(status="BLOCKED_BEFORE_SIMULATE", second_admission=admission2, second_source_check=lc2)
        return V.artifact_manifest(attempt, completion)

    stage = V.Q.stage(ROOT, attempt, "simulate", V.command(attempt, "simulate"), 600, ep)
    verify = V.verify(attempt, "simulate")
    _, postlock = V.check_lock()
    stage["verify"] = verify
    stage["source_check"] = postlock
    stage["xpr"] = V.info(V.XPR)
    if V.XPR.exists():
        shutil.copy2(V.XPR, attempt / "CFO_LINK010_simulate.xpr")
    stage["status"] = "PASS" if V.passed(stage, verify, "simulate") and postlock["all_checks"] and V.XPR.exists() else "FAIL"
    for name in ["xvlog.log", "compile.log", "elaborate.log", "simulate.log", "xvlog.prj"]:
        src = V.SIM / name
        if src.exists():
            shutil.copy2(src, attempt / ("native_" + name))
    V.wjson(attempt / "simulate_result.json", stage)
    completion["native_started"] = True
    completion["stages"]["simulate"] = stage
    if stage["status"] != "PASS":
        completion["status"] = "BLOCKED_AFTER_SIMULATE"
        return V.artifact_manifest(attempt, completion)

    post = V.A.post_snapshot(admission2, Q=V.Q)
    V.wjson(attempt / "POST_NATIVE_INTEGRITY.json", post)
    controller_unchanged = V.info(Path(__file__)).get("sha256") == V.info(attempt / "cfo_link010_guard_v2_repair_frozen.py").get("sha256")
    completion.update({
        "status": "PASS" if post.get("all_checks") and controller_unchanged else "FAIL",
        "post_native_integrity": post,
        "controller_bytes_unchanged": controller_unchanged,
        "old_projects_bytes_unchanged": all(V.info(Path(path)).get("sha256") == row.get("sha256") for path, row in oldx.items()),
        "t10_not_operated": True,
        "no_matlab": True,
        "no_synthesis_or_implementation": True,
    })
    return V.artifact_manifest(attempt, completion)


if __name__ == "__main__":
    raise SystemExit(main())
