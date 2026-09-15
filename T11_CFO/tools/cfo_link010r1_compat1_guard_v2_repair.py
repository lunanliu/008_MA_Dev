"""LINK010R1 compat1 simulate-only controller with closed dependency/evidence gates."""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import re
import shutil
import types


ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
BASE_XPR = ROOT / "vivado/CFO_LINK010R1/CFO_LINK010R1.xpr"
BASE_XPR_SHA = "5123211F34830D04D27268E252715051FFE5D53C07E75674E15D4D25B356DB0F"
LOCK = ROOT / "docs/LINK010R1_COMPAT1_SOURCE_LOCK.json"
LOCK_SHA = "4245E75E0D3049F9F7E92EDCF68B4E286BE30DE59747D8A03A0BBE14C2C3FFA3"
COMPAT_TB = ROOT / "sim/tb/cfo_estimator_link_r1_compat1_tb.sv"
COMPAT_TB_SHA = "4C7EC8E1FB2F194FF982130439CE90375C6414FC7B1B2C8A0F2D646A518B078E"
TCL = ROOT / "vivado/link010r1_compat1_project_v2_repair.tcl"
TCL_SHA = "B106E35A3A6FF3F17A61863ADBD897C1C620D36DACDC84E944F5D08A020289E6"
CHECKER = ROOT / "tools/verify_link010r1_compat1.py"
VERIFY = ROOT / "tools/verify_link010r1.py"
BINDING = ROOT / "tools/verify_link010r1_binding.py"
HELPER = ROOT / "tools/link010r1_compat1_admission_repair_v2.py"
HELPER_SHA = "B16765EF64A900A5FFF6A6D995A2FD3B7BC3776F9E27C359C3FA707E431FC218"
SUBMITTED_V1_RUNNER = ROOT / "tools/cfo_link010r1_compat1_guard.py"
SUBMITTED_V1_RUNNER_SHA = "95B4179580E524B0008A71E3323813C4B8DC6CEE4813F7AB9F709E229245A3CD"
SUBMITTED_V1_HELPER = ROOT / "tools/link010r1_compat1_admission_repair.py"
SUBMITTED_V1_HELPER_SHA = "B3F8D17A8B73226643EBD0C7453550B5660EFA1F315082266CEFC1EFC4837B37"
SUBMITTED_V1_TCL = ROOT / "vivado/link010r1_compat1_project.tcl"
SUBMITTED_V1_TCL_SHA = "575520FAF9C28291E8DB79E657F7DB111669ECA870E95F9439035B9E10D72881"
ORIGINAL_V1_GUARD = ROOT / "tools/cfo_link010r1_guard_v1.py"
ORIGINAL_V1_GUARD_SHA = "9654C5B8B9ED5D252C9CA4F3008A08590CF972D332678FE876F70F097D887E84"
ORIGINAL_R1_REPAIR = ROOT / "tools/cfo_link010r1_guard_v2_repair.py"
ORIGINAL_R1_REPAIR_SHA = "486C678D4BD0EEC29942BBCFD3A884A7A59CC025B01A63F68FD48C6CEA65636F"
BASE_GUI_HELPER = ROOT / "tools/link010r1_admission_v2_repair.py"
BASE_GUI_HELPER_SHA = "CE1D6B786FE9DD495616A9F5B79155BA2D6653B5B4320DFC897500679060ABD3"
PHASE_GUARD = ROOT / "tools/cfo_phase74_guard_v1.py"
PHASE_GUARD_SHA = "B35F872630D2995B5EEB5257666188D3506C864FC4004294423078AE0CFE9583"
NUMERIC_MODELS = ROOT / "tools/verify_link010r1_models.py"
NUMERIC_MODELS_SHA = "C5FD9B54075C918FCD60CFB04CD8C7C9FEB3DBB596532367F529CE7CDAE6ED58"
RESET_CHECKER = ROOT / "tools/verify_link010r1_reset.py"
RESET_CHECKER_SHA = "E28F55CBF483C9B904E56A3D54D747377A1EC27610A5A2B70A6F2342C7D760C0"
ORIGINAL_TCL = ROOT / "vivado/link010r1_project.tcl"
ORIGINAL_TCL_SHA = "A04D3BC4F063779028288B72074696F99ABF2287A277171B8DD0947E23718037"
PARALLEL_TCL = ROOT / "vivado/configure_parallel_jobs.tcl"
PARALLEL_TCL_SHA = "50B5FCAB461B47C19D3E7B2C02EE111F7D203B3791B2C6D4807A45382C2585B3"
AUTHORIZED_JOB = "CFO-LINK010R1-COMPAT1"
HARD_TIMEOUT = 600


def file_sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_exact(name, path, approved_sha):
    path = Path(path)
    observed = file_sha(path)
    if observed != approved_sha:
        raise RuntimeError(f"dependency SHA mismatch: {path} {observed} != {approved_sha}")
    module = load_module(name, path)
    if file_sha(path) != approved_sha:
        raise RuntimeError(f"dependency SHA changed during load: {path}")
    return module


Q = load_exact("link010r1_compat1_v2_stage_guard", PHASE_GUARD, PHASE_GUARD_SHA)
B = load_module("link010r1_compat1_v2_binding", BINDING)
H = load_module("link010r1_compat1_v2_admission", HELPER)
V1 = load_exact("link010r1_compat1_submitted_v1", SUBMITTED_V1_RUNNER, SUBMITTED_V1_RUNNER_SHA)
ACTIVE_SIM = BASE_XPR.parent / "CFO_LINK010R1.sim/sim_1/behav/xsim"


def dependency_specs():
    return {
        "entry_runner": (Path(__file__), None),
        "admission_helper_v2": (HELPER, HELPER_SHA),
        "compat1_tcl_v2": (TCL, TCL_SHA),
        "base_gui_helper": (BASE_GUI_HELPER, BASE_GUI_HELPER_SHA),
        "original_v1_guard": (ORIGINAL_V1_GUARD, ORIGINAL_V1_GUARD_SHA),
        "original_r1_repair": (ORIGINAL_R1_REPAIR, ORIGINAL_R1_REPAIR_SHA),
        "submitted_v1_runner": (SUBMITTED_V1_RUNNER, SUBMITTED_V1_RUNNER_SHA),
        "submitted_v1_helper": (SUBMITTED_V1_HELPER, SUBMITTED_V1_HELPER_SHA),
        "submitted_v1_tcl": (SUBMITTED_V1_TCL, SUBMITTED_V1_TCL_SHA),
        "compat_checker": (CHECKER, "2491BED375EE0ED51AC70E095EED4F8DA36BF8D80254A7AC6C701D6E9143955D"),
        "binding_checker": (BINDING, "589DF51BC1B689FA16BB07ED378880C4A6F9DC6060B72C8523990324FAE0B4DA"),
        "numeric_verifier": (VERIFY, "8099CA4EC39373EF82C910E21C39B12E4B3723FE832E2B1FBE9C10B337B9A2D1"),
        "numeric_models": (NUMERIC_MODELS, NUMERIC_MODELS_SHA),
        "reset_checker": (RESET_CHECKER, RESET_CHECKER_SHA),
        "original_tcl": (ORIGINAL_TCL, ORIGINAL_TCL_SHA),
        "parallel_tcl": (PARALLEL_TCL, PARALLEL_TCL_SHA),
        "source_lock": (LOCK, LOCK_SHA),
        "compat_tb": (COMPAT_TB, COMPAT_TB_SHA),
        "reused_xpr": (BASE_XPR, BASE_XPR_SHA),
    }


def dependency_snapshot(slot=None):
    rows = {}
    for key, (path, expected) in dependency_specs().items():
        exists = Path(path).is_file()
        actual = file_sha(path) if exists else None
        rows[key] = {"path": str(path), "approved_sha256": expected, "loaded_sha256": actual,
                     "exists": exists, "matches": bool(exists and (expected is None or actual == expected))}
    runner_match = bool(slot and slot.get("script_sha256") == rows["entry_runner"]["loaded_sha256"])
    rows["entry_runner"]["grant_sha_match"] = runner_match
    return rows, all(row["matches"] for row in rows.values()) and runner_match


def frozen_dependency_copies(attempt, before):
    target = attempt / "execution_dependencies"
    target.mkdir(parents=True, exist_ok=True)
    records = {}
    errors = []
    for key, row in before.items():
        source = Path(row["path"])
        destination = target / f"{key}{source.suffix}"
        try:
            shutil.copy2(source, destination)
            frozen_sha = file_sha(destination)
            records[key] = {"source_path": str(source), "frozen_path": str(destination),
                            "source_sha256": row.get("loaded_sha256"), "frozen_sha256": frozen_sha,
                            "matches": frozen_sha == row.get("loaded_sha256")}
            if not records[key]["matches"]:
                errors.append(f"frozen SHA mismatch: {key}")
        except Exception as exc:
            records[key] = {"source_path": str(source), "frozen_path": str(destination), "matches": False,
                            "error": repr(exc)}
            errors.append(f"freeze failed: {key}: {exc!r}")
    return records, errors


def frozen_integrity(records):
    errors = []
    for key, row in records.items():
        path = Path(row["frozen_path"])
        if not path.is_file() or file_sha(path) != row.get("source_sha256"):
            errors.append(key)
    return not errors, errors


def dependency_unchanged(before, after):
    errors = []
    for key, row in before.items():
        if key == "reused_xpr":
            continue
        if after.get(key, {}).get("loaded_sha256") != row.get("loaded_sha256"):
            errors.append(key)
    return not errors, errors


def paths(root, attempt, stage):
    return [attempt / f"{stage}{s}" for s in [".log", ".jou", ".stdout.log", ".stderr.log", "_actual_sources.csv", "_project_identity.txt"]] + [
        attempt / "link010_actual.txt", attempt / "link010r1_reset_audit.txt",
    ] + [ACTIVE_SIM / x for x in ["xvlog.log", "compile.log", "elaborate.log", "xelab.log", "simulate.log", "xsim.log",
                                   "xsim.dir/cfo_estimator_link_tb_behav/xsimkernel.log"]]


def marks(root, attempt, stage):
    ps = paths(root, attempt, stage)
    return {"ready": Q.marker(ps, f"CFO_LINK010R1_COMPAT1_READY action={stage} "),
            "done": Q.marker(ps, f"CFO_LINK010R1_NATIVE_DONE action={stage}"),
            "passed": Q.marker(ps, "CFO_LINK010_PASS ")}


Q.paths = paths
Q.marks = marks


def lock_check():
    lock = json.loads(LOCK.read_text("utf-8-sig"))
    rows = []
    for item in lock.get("files", []) + lock.get("vendor_dependencies", []):
        path = Path(item["path"])
        actual = Q.info(path if path.is_absolute() else ROOT / path)
        rows.append({"path": item["path"], "expected_sha256": item["sha256"], "actual": actual,
                     "matches": actual.get("sha256") == item["sha256"] and actual.get("bytes") == item["bytes"]})
    return lock, {"lock_sha256": Q.info(LOCK).get("sha256"), "all_members_match": all(x["matches"] for x in rows),
                  "members": rows, "all_checks": Q.info(LOCK).get("sha256") == LOCK_SHA and all(x["matches"] for x in rows)}


def parsed(result):
    try:
        lines = [line for line in result.get("stdout", "").splitlines() if line.strip()]
        return json.loads(lines[-1]) if lines else None
    except Exception:
        return None


def checker(attempt):
    result = Q.py(CHECKER, "--sources", attempt / "simulate_actual_sources.csv")
    result["parsed"] = parsed(result)
    return result


def numeric_verify(attempt):
    result = Q.py(VERIFY, "--identity", attempt / "simulate_project_identity.txt", "--actual",
                  attempt / "link010_actual.txt", "--reset-audit", attempt / "link010r1_reset_audit.txt")
    result["parsed"] = parsed(result)
    return result


def command(attempt):
    return [str(Q.VIVADO), "-mode", "batch", "-source", str(TCL), "-log", str(attempt / "simulate.log"),
            "-journal", str(attempt / "simulate.jou"), "-tclargs", "simulate", str(attempt)]


def snapshot_preexisting_simdir(attempt):
    target = attempt / "preexisting_simdir_snapshot"
    target.mkdir(parents=True, exist_ok=True)
    records = []
    for source in [ACTIVE_SIM / x for x in ["xvlog.log", "compile.log", "elaborate.log", "xelab.log", "simulate.log", "xsim.log",
                                             "compile.bat", "cfo_estimator_link_tb_vlog.prj", "xsim.ini", "link010_actual.txt", "link010r1_reset_audit.txt"]]:
        row = {"source": str(source), "exists": source.is_file()}
        if source.is_file():
            destination = target / source.name
            try:
                shutil.copy2(source, destination)
                row.update(destination=str(destination), sha256=file_sha(destination), copied=True)
            except Exception as exc:
                row.update(copied=False, error=repr(exc))
        records.append(row)
    Q.wjson(attempt / "preexisting_simdir_snapshot.json", {"schema": "compat1_preexisting_simdir_v1", "records": records})
    return records


def save_current_native_evidence(attempt):
    records = []
    for source in [ACTIVE_SIM / x for x in ["xvlog.log", "compile.log", "elaborate.log", "xelab.log", "simulate.log", "xsim.log",
                                             "compile.bat", "cfo_estimator_link_tb_vlog.prj", "xsim.ini", "link010_actual.txt", "link010r1_reset_audit.txt"]]:
        row = {"source": str(source), "exists": source.is_file()}
        if source.is_file():
            destination = attempt / f"native_{source.name}"
            try:
                shutil.copy2(source, destination)
                row.update(destination=str(destination), sha256=file_sha(destination), copied=True)
            except Exception as exc:
                row.update(copied=False, error=repr(exc))
        records.append(row)
    kernel = ACTIVE_SIM / "xsim.dir/cfo_estimator_link_tb_behav/xsimkernel.log"
    row = {"source": str(kernel), "exists": kernel.is_file()}
    if kernel.is_file():
        destination = attempt / "native_xsimkernel.log"
        try:
            shutil.copy2(kernel, destination)
            row.update(destination=str(destination), sha256=file_sha(destination), copied=True)
        except Exception as exc:
            row.update(copied=False, error=repr(exc))
    records.append(row)
    Q.wjson(attempt / "native_evidence_copy.json", {"schema": "compat1_native_evidence_copy_v2", "records": records})
    return records, all(row.get("copied", True) for row in records if row.get("exists"))


def safe_wjson(path, value, errors):
    try:
        return Q.wjson(path, value)
    except Exception as exc:
        errors.append({"operation": "write_json", "path": str(path), "error": repr(exc)})
        return None


def finish_clock(attempt, status, errors):
    path = attempt / "report_clock.json"
    try:
        value = json.loads(path.read_text("utf-8"))
        value.update(status="COMPLETE", ended_utc=Q.utc(), final_status=status, evidence_errors=errors)
        Q.wjson(path, value)
        return True
    except Exception as exc:
        errors.append({"operation": "finish_report_clock", "error": repr(exc)})
        return False


def artifact_manifest(attempt, completion_sha, errors):
    rows = []
    seen = set()
    candidates = list(attempt.rglob("*")) + [BASE_XPR] + [ACTIVE_SIM / x for x in ["xvlog.log", "compile.log", "elaborate.log", "xelab.log", "simulate.log", "xsim.log"]]
    for path in candidates:
        if path.is_file() and str(path) not in seen and path.name != "ATTEMPT_ARTIFACT_MANIFEST.json":
            try:
                rows.append(Q.info(path)); seen.add(str(path))
            except Exception as exc:
                errors.append({"operation": "artifact_info", "path": str(path), "error": repr(exc)})
    return safe_wjson(attempt / "ATTEMPT_ARTIFACT_MANIFEST.json", {"schema": "link010r1_compat1_artifacts_v2",
                                                                     "completion_sha256": completion_sha, "artifacts": rows}, errors)


def self_check():
    lock, lock_result = lock_check()
    static = Q.py(CHECKER)
    static_json = parsed(static)
    checks = {"lock": lock_result["all_checks"], "checker": static.get("exit_code") == 0 and static_json and static_json.get("native_started") is False,
              "tb_sha": COMPAT_TB.is_file() and file_sha(COMPAT_TB) == COMPAT_TB_SHA,
              "base_xpr_sha": BASE_XPR.is_file() and file_sha(BASE_XPR) == BASE_XPR_SHA,
              "helper_sha": HELPER.is_file() and file_sha(HELPER) == HELPER_SHA,
              "tcl_sha": TCL.is_file() and file_sha(TCL) == TCL_SHA,
              "original_dependencies": all(row["matches"] for key, row in dependency_snapshot()[0].items() if key not in {"entry_runner", "admission_helper_v2", "compat1_tcl_v2"}),
              "simulate_only": True, "x64_job": Q.G.PTR_SIZE == 8 and Q.G.JOB_ACCOUNTING == 1}
    return {"schema": "link010r1_compat1_guard_v2_self_check_v1", "checks": checks, "all_checks": all(checks.values()),
            "native_started": False, "external_processes_modified": False, "lock": lock_result}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        value = self_check()
        print(json.dumps(value, ensure_ascii=False))
        return 0 if value["all_checks"] else 2

    parent = ROOT / "work/CFO_LINK010R1_COMPAT1_V2"
    parent.mkdir(parents=True, exist_ok=True)
    attempt = parent / f"attempt_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}_luna"
    attempt.mkdir()
    errors = []
    frozen_runner = attempt / "cfo_link010r1_compat1_guard_v2_repair_frozen.py"
    try:
        shutil.copy2(Path(__file__), frozen_runner)
    except Exception as exc:
        errors.append({"operation": "freeze_runner", "error": repr(exc)})
    events = attempt / "controller_events.jsonl"
    safe_wjson(attempt / "report_clock.json", {"thread_id": "01a076f0-d8c0-72a0-8371-cb2ff29c1b28", "status": "ACTIVE",
                                                  "started_utc": Q.utc(), "interval_minutes": 15}, errors)
    lock, lock_result = lock_check()
    static = Q.py(CHECKER)
    static["parsed"] = parsed(static)
    admission = H.snapshot("simulate", Q=Q)
    slot = admission.get("grant", {}).get("slot", {})
    deps_before, deps_ok = dependency_snapshot(slot)
    frozen_deps, freeze_errors = frozen_dependency_copies(attempt, deps_before)
    errors.extend({"operation": "freeze_dependency", "detail": x} for x in freeze_errors)
    snapshot_preexisting_simdir(attempt)
    xpr_before = Q.info(BASE_XPR)
    try:
        shutil.copy2(BASE_XPR, attempt / "CFO_LINK010R1_pre_compat1.xpr")
    except Exception as exc:
        errors.append({"operation": "copy_pre_xpr", "error": repr(exc)})
    old_paths = [ROOT / "vivado" / name / f"{name}.xpr" for name in ["CFO_SYNC", "CFO_COORD", "CFO_PHASE74", "CFO_FFT256",
                                                                        "CFO_BACKEND74", "CFO_FFT2048", "CFO_FRONT2048", "CFO_LINK010"]]
    old = {str(path): Q.info(path) for path in old_paths}
    checks = {"admission": admission.get("all_checks") is True, "source_lock": lock_result["all_checks"],
              "static_checker": static.get("exit_code") == 0 and static.get("parsed", {}).get("native_started") is False,
              "dependencies": deps_ok and not freeze_errors, "reused_xpr": xpr_before.get("sha256") == BASE_XPR_SHA,
              "planned_free_memory": admission.get("memory", {}).get("available_physical_bytes", 0) >= 6 * 1024 ** 3,
              "old_projects_present": all(item.get("exists") for item in old.values()), "simulate_only": True}
    preflight = {"schema": "link010r1_compat1_pre_simulate_admission_v2", "admission": admission,
                 "source_check": lock_result, "dependency_check": deps_before, "frozen_dependencies": frozen_deps,
                 "reused_xpr": xpr_before, "static_checker": static, "checks": checks, "all_checks": all(checks.values())}
    safe_wjson(attempt / "PRE_SIMULATE_ADMISSION.json", preflight, errors)
    freeze = {"schema": "link010r1_compat1_execution_freeze_v2", "job_id": AUTHORIZED_JOB, "utc": Q.utc(),
              "attempt": str(attempt), "controller": Q.info(Path(__file__)), "source_lock": lock_result,
              "full_pre_simulate_admission": admission, "preflight": preflight, "dependencies": deps_before,
              "frozen_dependencies": frozen_deps, "reused_created_project": {"xpr": str(BASE_XPR), "pre_simulate": xpr_before,
                                                                                "expected_sha256": BASE_XPR_SHA, "compat1_replacement_expected": True},
              "old_projects": old, "commands": {"simulate": command(attempt)}, "hard_timeout_seconds": {"simulate": HARD_TIMEOUT},
              "zero_grace_seconds": 5, "memory": {"expected_gib": [1.5, 3.0], "warning_gib": 4, "preflight_free_gib": 6,
                                                     "immediate_severe_free_gib": .25, "sustained_severe_free_gib": .5, "sustained_seconds": 30},
              "parallel": {"general": 8, "synth": 8, "xelab": 16, "native_groups": 1, "matlab": 0}, "checks": checks}
    freeze_sha = safe_wjson(attempt / "EXECUTION_FREEZE.json", freeze, errors)
    Q.event(events, "execution_freeze_written", sha256=freeze_sha, checks=checks)
    completion = {"schema": "link010r1_compat1_completion_v2", "attempt": str(attempt), "execution_freeze_sha256": freeze_sha,
                  "status": "BLOCKED_PREFLIGHT", "stages": {}, "checks": checks, "native_started": False,
                  "scope": "Only compat1 sim_1 TB alias repair; no create, no algorithm change, no synthesis, no implementation, no full CFO chain.",
                  "evidence_errors": errors}
    if not all(checks.values()):
        finish_clock(attempt, completion["status"], errors)
        completion["evidence_errors"] = errors
        completion_sha = safe_wjson(attempt / "ATTEMPT_COMPLETION.json", completion, errors)
        artifact_manifest(attempt, completion_sha, errors)
        print(json.dumps({"status": completion["status"], "attempt": str(attempt), "completion_sha256": completion_sha,
                          "manifest_sha256": Q.info(attempt / "ATTEMPT_ARTIFACT_MANIFEST.json").get("sha256")}))
        return 1

    # Repeat every mutable admission/input check immediately before the only native launch.
    launch_admission = H.snapshot("simulate", Q=Q)
    launch_slot = launch_admission.get("grant", {}).get("slot", {})
    launch_lock, launch_lock_result = lock_check()
    launch_deps, launch_deps_ok = dependency_snapshot(launch_slot)
    launch_static = Q.py(CHECKER)
    launch_static["parsed"] = parsed(launch_static)
    launch_xpr = Q.info(BASE_XPR)
    launch_checks = {"admission": launch_admission.get("all_checks") is True,
                     "source_lock": launch_lock_result["all_checks"],
                     "static_checker": launch_static.get("exit_code") == 0 and launch_static.get("parsed", {}).get("native_started") is False,
                     "dependencies": launch_deps_ok, "reused_xpr": launch_xpr.get("sha256") == BASE_XPR_SHA,
                     "planned_free_memory": launch_admission.get("memory", {}).get("available_physical_bytes", 0) >= 6 * 1024 ** 3,
                     "simulate_only": True}
    preflight["launch_recheck"] = {"admission": launch_admission, "source_check": launch_lock_result,
                                    "dependency_check": launch_deps, "reused_xpr": launch_xpr,
                                    "static_checker": launch_static, "checks": launch_checks,
                                    "all_checks": all(launch_checks.values())}
    safe_wjson(attempt / "PRE_SIMULATE_ADMISSION.json", preflight, errors)
    freeze["launch_recheck"] = preflight["launch_recheck"]
    freeze_sha = safe_wjson(attempt / "EXECUTION_FREEZE.json", freeze, errors)
    completion["execution_freeze_sha256"] = freeze_sha
    Q.event(events, "execution_freeze_launch_recheck_written", sha256=freeze_sha, checks=launch_checks)
    if not all(launch_checks.values()):
        completion["status"] = "BLOCKED_BEFORE_SIMULATE"
        completion["checks"]["launch_recheck"] = launch_checks
        finish_clock(attempt, completion["status"], errors)
        completion["evidence_errors"] = errors
        completion_sha = safe_wjson(attempt / "ATTEMPT_COMPLETION.json", completion, errors)
        artifact_manifest(attempt, completion_sha, errors)
        print(json.dumps({"status": completion["status"], "attempt": str(attempt), "completion_sha256": completion_sha,
                          "manifest_sha256": Q.info(attempt / "ATTEMPT_ARTIFACT_MANIFEST.json").get("sha256")}))
        return 1
    admission = launch_admission

    Q.event(events, "simulate_stage_begin")
    result = None
    try:
        result = Q.stage(ROOT, attempt, "simulate", command(attempt), HARD_TIMEOUT, events)
        completion["native_started"] = True
        completion["stages"]["simulate"] = result
        native_records, native_copy_ok = save_current_native_evidence(attempt)
        completion["native_evidence_copy"] = native_records
        numeric = numeric_verify(attempt)
        source_result = checker(attempt)
        result["verify"] = numeric
        result["compat_verify"] = source_result
        _, post_lock = lock_check()
        result["source_check"] = post_lock
        result["xpr"] = Q.info(BASE_XPR)
        try:
            stage_pass = bool(V1.passed(result, numeric, source_result, attempt))
        except Exception as exc:
            stage_pass = False
            errors.append({"operation": "stage_pass_parse", "error": repr(exc)})
        result["status"] = "PASS" if stage_pass and post_lock["all_checks"] and native_copy_ok else "FAIL"
        safe_wjson(attempt / "simulate_result.json", result, errors)
    except Exception as exc:
        errors.append({"operation": "post_stage_evidence", "error": repr(exc)})
        if result is None:
            result = {"schema": "cfo_phase004_stage_result_v1", "stage": "simulate", "status": "FAIL",
                      "controller_errors": [{"operation": "v2_wrapper", "error": repr(exc)}]}
        completion["native_started"] = True
        completion["stages"]["simulate"] = result

    post = {}
    try:
        post = H.post_snapshot(admission, Q=Q)
    except Exception as exc:
        errors.append({"operation": "post_admission", "error": repr(exc)})
        post = {"all_checks": False, "error": repr(exc)}
    deps_after, _ = dependency_snapshot(slot)
    deps_stable, deps_changed = dependency_unchanged(deps_before, deps_after)
    frozen_ok, frozen_bad = frozen_integrity(frozen_deps)
    xpr_after = Q.info(BASE_XPR)
    try:
        shutil.copy2(BASE_XPR, attempt / "CFO_LINK010R1_post_compat1.xpr")
    except Exception as exc:
        errors.append({"operation": "copy_post_xpr", "error": repr(exc)})
    old_unchanged = all(Q.info(Path(path)).get("sha256") == item.get("sha256") for path, item in old.items())
    controller_unchanged = file_sha(frozen_runner) == file_sha(Path(__file__)) if frozen_runner.is_file() else False
    stage_pass = bool(result and result.get("status") == "PASS")
    final_gates = {"stage_pass": stage_pass, "post_admission": post.get("all_checks") is True,
                   "source_lock_after": result.get("source_check", {}).get("all_checks") is True if result else False,
                   "old_project_bytes_unchanged": old_unchanged, "controller_bytes_unchanged": controller_unchanged,
                   "entry_dependencies_unchanged": deps_stable, "frozen_dependencies_intact": frozen_ok,
                   "reused_xpr_post_present": xpr_after.get("exists") is True,
                   "evidence_copy_errors": not errors, "report_clock_finalized": False}
    completion.update(stages={"simulate": result}, post_native_inventory=post, dependencies_after=deps_after,
                      frozen_dependency_integrity={"all_checks": frozen_ok, "bad": frozen_bad}, dependency_changes=deps_changed,
                      reused_xpr_post=xpr_after, old_project_bytes_unchanged=old_unchanged,
                      controller_bytes_unchanged=controller_unchanged, final_pass_gates=final_gates,
                      evidence_errors=errors)
    tentative_status = "PASS" if all(value for key, value in final_gates.items() if key != "report_clock_finalized") else ("BLOCKED_AFTER_SIMULATE_EVIDENCE" if errors else "BLOCKED_AFTER_SIMULATE")
    clock_ok = finish_clock(attempt, tentative_status, errors)
    final_gates["report_clock_finalized"] = clock_ok
    final_gates["evidence_copy_errors"] = not errors
    completion["final_pass_gates"] = final_gates
    completion["report_clock_finalized"] = clock_ok
    completion["status"] = "PASS" if all(final_gates.values()) else ("BLOCKED_AFTER_SIMULATE_EVIDENCE" if errors else "BLOCKED_AFTER_SIMULATE")
    completion["evidence_errors"] = errors
    completion_sha = safe_wjson(attempt / "ATTEMPT_COMPLETION.json", completion, errors)
    manifest_sha = artifact_manifest(attempt, completion_sha, errors)
    if errors:
        completion["final_pass_gates"]["evidence_copy_errors"] = False
        completion["status"] = "BLOCKED_AFTER_SIMULATE_EVIDENCE"
        completion["evidence_errors"] = errors
        finish_clock(attempt, completion["status"], errors)
        completion_sha = safe_wjson(attempt / "ATTEMPT_COMPLETION.json", completion, errors)
        manifest_sha = artifact_manifest(attempt, completion_sha, errors)
    print(json.dumps({"status": completion["status"], "attempt": str(attempt), "completion_sha256": completion_sha,
                      "manifest_sha256": manifest_sha}))
    return 0 if completion["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
