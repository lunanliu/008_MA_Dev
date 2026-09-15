"""LINK010R1 compat1 simulate-only controller; no create and no automatic retry."""
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
TCL = ROOT / "vivado/link010r1_compat1_project.tcl"
CHECKER = ROOT / "tools/verify_link010r1_compat1.py"
VERIFY = ROOT / "tools/verify_link010r1.py"
BINDING = ROOT / "tools/verify_link010r1_binding.py"
HELPER = ROOT / "tools/link010r1_compat1_admission_repair.py"
HELPER_SHA = "B3F8D17A8B73226643EBD0C7453550B5660EFA1F315082266CEFC1EFC4837B37"
AUTHORIZED_JOB = "CFO-LINK010R1-COMPAT1"
HARD_TIMEOUT = 600


def file_sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


Q = load("link010r1_compat1_stage_guard", ROOT / "tools/cfo_phase74_guard_v1.py")
B = load("link010r1_compat1_binding", BINDING)
H = load("link010r1_compat1_admission", HELPER)
Q.info = Q.info
ACTIVE_SIM = BASE_XPR.parent / "CFO_LINK010R1.sim/sim_1/behav/xsim"


def paths(root, attempt, stage):
    return [attempt / f"{stage}{s}" for s in [".log", ".jou", ".stdout.log", ".stderr.log", "_actual_sources.csv", "_project_identity.txt"]] + [
        attempt / "link010_actual.txt",
        attempt / "link010r1_reset_audit.txt",
    ] + [ACTIVE_SIM / x for x in [
        "xvlog.log", "compile.log", "elaborate.log", "xelab.log", "simulate.log", "xsim.log",
        "xsim.dir/cfo_estimator_link_tb_behav/xsimkernel.log",
    ]]


def marks(root, attempt, stage):
    ps = paths(root, attempt, stage)
    return {
        "ready": Q.marker(ps, f"CFO_LINK010R1_COMPAT1_READY action={stage} "),
        "done": Q.marker(ps, f"CFO_LINK010R1_NATIVE_DONE action={stage}"),
        "passed": Q.marker(ps, "CFO_LINK010_PASS "),
    }


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
    all_members = all(row["matches"] for row in rows)
    return lock, {"lock_sha256": Q.info(LOCK).get("sha256"), "all_members_match": all_members,
                  "members": rows, "all_checks": Q.info(LOCK).get("sha256") == LOCK_SHA and all_members}


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
    args = ["--identity", attempt / "simulate_project_identity.txt", "--actual", attempt / "link010_actual.txt",
            "--reset-audit", attempt / "link010r1_reset_audit.txt"]
    result = Q.py(VERIFY, *args)
    result["parsed"] = parsed(result)
    return result


def native_identity_samples(result):
    path = Path(result["paths"]["samples"])
    expected = "c:/nifpga/programs/vivado2021_1/bin/unwrapped/win64.o/vivado.exe"
    rows = []
    if path.is_file():
        for line in path.read_text("utf-8").splitlines():
            item = json.loads(line)
            ids = item.get("active_process_ids", [])
            tree = item.get("active_process_tree", [])
            record = next((x for x in tree if x.get("pid") == result.get("ready_pid")), None)
            if not record:
                continue
            good = (result.get("ready_pid") in ids and not item.get("job_census_issues") and
                    not item.get("job_census_error") and not item.get("job_process_open_failures") and
                    item.get("job_pid_cross_check", {}).get("match") and len(tree) == len(ids) and
                    str(record.get("image_path", "")).replace("\\", "/").casefold() == expected and
                    record.get("creation_filetime_100ns", 0) > 0 and
                    record.get("private_usage_bytes") is not None and record.get("cpu_time_100ns") is not None)
            if good:
                rows.append({"utc": item["utc"], "pid": record["pid"],
                             "creation_filetime_100ns": record["creation_filetime_100ns"],
                             "ready_already_visible": item.get("stage_progress", {}).get("ready", {}).get("found", False)})
    return {"samples": len(rows), "consistent_creation_identity": len({x["creation_filetime_100ns"] for x in rows}) == 1,
            "observations": rows}


def passed(result, numeric, source_result, attempt):
    markers = result.get("markers", {})
    census = result.get("final_census_before_close", {})
    observed = native_identity_samples(result)
    result["saved_native_identity_check"] = observed
    common = bool(result.get("binding_succeeded") and result.get("events", {}).get("zero") and
                  census.get("empty_verified") and result.get("native_exit_code_final") == 0 and
                  not result.get("controller_errors") and not result.get("persistent_telemetry_fault") and
                  not result.get("termination_requested_by_controller") and markers.get("ready", {}).get("found") and
                  markers.get("done", {}).get("found") and result.get("ready_pid", 0) > 0 and
                  observed["samples"] >= 1 and observed["consistent_creation_identity"])
    diagnostics = []
    logs = [Path(result["paths"][x]) for x in ["log", "stdout", "stderr"]]
    logs += [ACTIVE_SIM / x for x in ["compile.log", "xvlog.log", "elaborate.log", "xelab.log", "simulate.log", "xsim.log"]]
    for path in logs:
        if path.exists():
            diagnostics += [{"path": str(path), "line": line} for line in path.read_text("utf-8", errors="replace").splitlines()
                            if re.match(r"^(?:ERROR:|Error:|FATAL:|Fatal:|FATAL_ERROR:)", line.strip())]
    result["native_error_diagnostics"] = diagnostics
    binding_after = B.run(ACTIVE_SIM)
    result["vendor_binding_check"] = binding_after
    before_path = attempt / "compat1_binding_before.json"
    after_path = attempt / "compat1_binding_after.json"
    before = json.loads(before_path.read_text("utf-8")) if before_path.exists() else {}
    after = json.loads(after_path.read_text("utf-8")) if after_path.exists() else {}
    result["compat1_binding_before"] = before
    result["compat1_binding_after"] = after
    values = re.fullmatch(r"CFO_LINK010_PASS unique=4 completed=22 protocol_errors=10 max_tail=(\d+) max_total=(\d+) source_stalls=(\d+) full_runs=21 reset_discards=4 abort_discards=4",
                          markers.get("passed", {}).get("line") or "")
    numeric_ok = bool(values and numeric.get("parsed") and numeric["parsed"].get("native_checked") and
                      numeric["parsed"].get("reset_audit", {}).get("status") == "LINK010R1_RESET_AUDIT_PASS" and
                      int(values[1]) <= 7800 and int(values[2]) <= 1170000 and int(values[3]) > 0)
    binding_ok = bool(before.get("all_checks") and after.get("all_checks") and binding_after.get("all_checks"))
    source_ok = bool(source_result.get("exit_code") == 0 and source_result.get("parsed", {}).get("actual_project_members") == 25 and
                     source_result.get("parsed", {}).get("all_actual_source_properties_preserved"))
    return bool(common and not diagnostics and numeric.get("exit_code") == 0 and numeric.get("parsed") and
                source_ok and numeric_ok and binding_ok)


def command(attempt):
    return [str(Q.VIVADO), "-mode", "batch", "-source", str(TCL), "-log", str(attempt / "simulate.log"),
            "-journal", str(attempt / "simulate.jou"), "-tclargs", "simulate", str(attempt)]


def artifact_manifest(attempt, completion):
    completion_sha = Q.wjson(attempt / "ATTEMPT_COMPLETION.json", completion)
    rows = []
    seen = set()
    candidates = list(attempt.rglob("*")) + [BASE_XPR]
    candidates += [ACTIVE_SIM / x for x in ["xvlog.log", "compile.log", "elaborate.log", "xelab.log", "simulate.log", "xsim.log",
                                             "compile.bat", "cfo_estimator_link_tb_vlog.prj", "xsim.ini"]]
    for path in candidates:
        if path.is_file() and str(path) not in seen:
            rows.append(Q.info(path)); seen.add(str(path))
    manifest_sha = Q.wjson(attempt / "ATTEMPT_ARTIFACT_MANIFEST.json",
                           {"schema": "link010r1_compat1_artifacts_v1", "completion_sha256": completion_sha, "artifacts": rows})
    return completion_sha, manifest_sha


def self_check():
    lock, lock_result = lock_check()
    checks = {
        "lock": lock_result["all_checks"],
        "compat_checker": parsed(Q.py(CHECKER)).get("status") == "EXACT_TB_EQUIVALENCE_PASS_PENDING_NATIVE",
        "compat_checker_native_false": parsed(Q.py(CHECKER)).get("native_started") is False,
        "tb_sha": COMPAT_TB.exists() and file_sha(COMPAT_TB) == COMPAT_TB_SHA,
        "base_xpr_sha": BASE_XPR.exists() and file_sha(BASE_XPR) == BASE_XPR_SHA,
        "helper_sha": HELPER.exists() and file_sha(HELPER) == HELPER_SHA,
        "tcl": TCL.exists(),
        "simulate_only": True,
        "x64_job": Q.G.PTR_SIZE == 8 and Q.G.JOB_ACCOUNTING == 1,
    }
    return {"schema": "link010r1_compat1_guard_self_check_v1", "checks": checks,
            "all_checks": all(checks.values()), "native_started": False, "external_processes_modified": False,
            "lock": lock_result}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        value = self_check()
        print(json.dumps(value, ensure_ascii=False))
        return 0 if value["all_checks"] else 2

    parent = ROOT / "work/CFO_LINK010R1_COMPAT1"
    parent.mkdir(parents=True, exist_ok=True)
    attempt = parent / f"attempt_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}_luna"
    attempt.mkdir()
    frozen_runner = attempt / "cfo_link010r1_compat1_guard_frozen.py"
    frozen_helper = attempt / "link010r1_compat1_admission_repair_frozen.py"
    shutil.copy2(Path(__file__), frozen_runner)
    shutil.copy2(HELPER, frozen_helper)
    if file_sha(frozen_runner) != file_sha(Path(__file__)) or file_sha(frozen_helper) != file_sha(HELPER):
        raise RuntimeError("execution dependency freeze copy mismatch")
    events = attempt / "controller_events.jsonl"
    Q.wjson(attempt / "report_clock.json", {"thread_id": "01a076f0-d8c0-72a0-8371-cb2ff29c1b28", "status": "ACTIVE",
                                               "started_utc": Q.utc(), "interval_minutes": 15})
    lock, lock_result = lock_check()
    source_static = Q.py(CHECKER)
    source_static["parsed"] = parsed(source_static)
    admission = H.snapshot("simulate", Q=Q)
    base_xpr_info = Q.info(BASE_XPR)
    old_paths = [ROOT / "vivado" / name / f"{name}.xpr" for name in ["CFO_SYNC", "CFO_COORD", "CFO_PHASE74", "CFO_FFT256",
                                                                        "CFO_BACKEND74", "CFO_FFT2048", "CFO_FRONT2048", "CFO_LINK010"]]
    old = {str(path): Q.info(path) for path in old_paths}
    checks = {
        "compat_source_lock": lock_result["all_checks"],
        "compat_static_checker": source_static.get("exit_code") == 0 and source_static.get("parsed", {}).get("native_started") is False,
        "compat_tb_sha": COMPAT_TB.exists() and file_sha(COMPAT_TB) == COMPAT_TB_SHA,
        "reused_xpr_sha": base_xpr_info.get("sha256") == BASE_XPR_SHA,
        "admission": admission.get("all_checks") is True,
        "planned_free_memory": admission.get("memory", {}).get("available_physical_bytes", 0) >= 6 * 1024 ** 3,
        "old_projects_present": all(item.get("exists") for item in old.values()),
        "simulate_only": True,
    }
    freeze = {"schema": "link010r1_compat1_execution_freeze_v1", "job_id": AUTHORIZED_JOB, "utc": Q.utc(),
              "attempt": str(attempt), "controller": Q.info(Path(__file__)), "admission_helper": Q.info(HELPER),
              "frozen_admission_helper": Q.info(frozen_helper), "source_lock": lock_result,
              "project": {"part": lock["part"], "hardware_top": lock["hardware_top"], "simulation_top": lock["simulation_top"]},
              "reused_created_project": {"xpr": str(BASE_XPR), "pre_simulate": base_xpr_info, "expected_sha256": BASE_XPR_SHA,
                                          "compat1_replacement_expected": True},
              "old_projects": old, "compat_checker": Q.info(CHECKER), "compat_tcl": Q.info(TCL),
              "compat_tb": Q.info(COMPAT_TB), "commands": {"simulate": command(attempt)},
              "hard_timeout_seconds": {"simulate": HARD_TIMEOUT}, "zero_grace_seconds": 5,
              "memory": {"expected_gib": [1.5, 3.0], "warning_gib": 4, "preflight_free_gib": 6,
                          "immediate_severe_free_gib": .25, "sustained_severe_free_gib": .5, "sustained_seconds": 30},
              "parallel": {"general": 8, "synth": 8, "xelab": 16, "native_groups": 1, "matlab": 0},
              "checks": checks}
    freeze_sha = Q.wjson(attempt / "EXECUTION_FREEZE.json", freeze)
    Q.event(events, "execution_freeze_written", sha256=freeze_sha, checks=checks)
    completion = {"schema": "link010r1_compat1_completion_v1", "attempt": str(attempt),
                  "execution_freeze_sha256": freeze_sha, "status": "BLOCKED_PREFLIGHT", "stages": {},
                  "checks": checks, "native_started": False,
                  "scope": "Only the compat1 sim_1 TB alias repair; no create, no algorithm change, no synthesis, no implementation, no full CFO chain."}
    if not all(checks.values()):
        ch, mh = artifact_manifest(attempt, completion)
        print(json.dumps({"status": completion["status"], "attempt": str(attempt), "completion_sha256": ch, "manifest_sha256": mh}))
        return 1

    Q.event(events, "simulate_stage_begin")
    result = Q.stage(ROOT, attempt, "simulate", command(attempt), HARD_TIMEOUT, events)
    completion["native_started"] = True
    result["verify"] = numeric_verify(attempt)
    result["compat_verify"] = checker(attempt)
    _, post_lock = lock_check()
    result["source_check"] = post_lock
    result["xpr"] = Q.info(BASE_XPR)
    result["status"] = "PASS" if passed(result, result["verify"], result["compat_verify"], attempt) and post_lock["all_checks"] else "FAIL"
    Q.wjson(attempt / "simulate_result.json", result)
    completion["stages"]["simulate"] = result
    if result["status"] != "PASS":
        completion["status"] = "BLOCKED_AFTER_SIMULATE"
        completion["post_native_inventory"] = H.post_snapshot(admission, Q=Q)
        completion["reused_xpr_post"] = Q.info(BASE_XPR)
        completion["old_project_bytes_unchanged"] = all(Q.info(Path(path)).get("sha256") == item.get("sha256") for path, item in old.items())
        completion["controller_bytes_unchanged"] = file_sha(frozen_runner) == file_sha(Path(__file__))
        ch, mh = artifact_manifest(attempt, completion)
        print(json.dumps({"status": completion["status"], "attempt": str(attempt), "completion_sha256": ch, "manifest_sha256": mh}))
        return 1

    post = H.post_snapshot(admission, Q=Q)
    completion.update(status="PASS" if post.get("all_checks") else "FAIL", post_native_inventory=post,
                      reused_xpr_post=Q.info(BASE_XPR),
                      old_project_bytes_unchanged=all(Q.info(Path(path)).get("sha256") == item.get("sha256") for path, item in old.items()),
                      controller_bytes_unchanged=file_sha(frozen_runner) == file_sha(Path(__file__)),
                      t10_not_operated=True, no_matlab=True, no_create=True, no_synthesis_or_implementation=True)
    ch, mh = artifact_manifest(attempt, completion)
    print(json.dumps({"status": completion["status"], "attempt": str(attempt), "completion_sha256": ch, "manifest_sha256": mh}))
    return 0 if completion["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
