"""LINK010R1 execution wrapper using the project-switch-aware admission repair."""
from pathlib import Path
import hashlib
import shutil
import sys
import types


ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
V1_PATH = ROOT / "tools/cfo_link010r1_guard_v1.py"
ADMISSION_PATH = ROOT / "tools/link010r1_admission_v2_repair.py"
V1_SHA = "9654C5B8B9ED5D252C9CA4F3008A08590CF972D332678FE876F70F097D887E84"
ADMISSION_SHA = "CE1D6B786FE9DD495616A9F5B79155BA2D6653B5B4320DFC897500679060ABD3"


def file_sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def load_exact(name, path, approved_sha):
    observed = file_sha(path)
    if observed != approved_sha:
        raise RuntimeError(f"dependency SHA mismatch before load: {path} {observed} != {approved_sha}")
    source = Path(path).read_bytes()
    module = types.ModuleType(name)
    module.__file__ = str(path)
    exec(compile(source, str(path), "exec"), module.__dict__)
    after = file_sha(path)
    if after != approved_sha:
        raise RuntimeError(f"dependency SHA changed during load: {path} {after} != {approved_sha}")
    return module


V = load_exact("link010r1_guard_v1_frozen", V1_PATH, V1_SHA)
A2 = load_exact("link010r1_admission_v2_repair", ADMISSION_PATH, ADMISSION_SHA)
V.A = A2
V.__file__ = str(Path(__file__))

_copy2 = V.shutil.copy2
_wjson = V.wjson


def copy2_with_dependency(src, dst, *args, **kwargs):
    result = _copy2(src, dst, *args, **kwargs)
    if Path(dst).name == "cfo_link010r1_guard_v1_frozen.py":
        if file_sha(ADMISSION_PATH) != ADMISSION_SHA:
            raise RuntimeError("admission helper SHA changed before freezing")
        frozen = Path(dst).parent / "link010r1_admission_v2_repair_frozen.py"
        _copy2(ADMISSION_PATH, frozen)
        frozen_sha = file_sha(frozen)
        if frozen_sha != ADMISSION_SHA:
            raise RuntimeError(f"frozen admission helper SHA mismatch: {frozen_sha} != {ADMISSION_SHA}")
    return result


def wjson_with_dependency_freeze(path, data):
    p = Path(path)
    if p.name == "EXECUTION_FREEZE.json":
        frozen = p.parent / "link010r1_admission_v2_repair_frozen.py"
        loaded_sha = file_sha(ADMISSION_PATH)
        frozen_sha = file_sha(frozen) if frozen.exists() else None
        if loaded_sha != ADMISSION_SHA:
            raise RuntimeError(f"loaded admission helper SHA mismatch: {loaded_sha} != {ADMISSION_SHA}")
        if frozen_sha != loaded_sha:
            raise RuntimeError(f"frozen admission helper SHA mismatch: {frozen_sha} != {loaded_sha}")
        data = dict(data)
        data["execution_repair_dependencies"] = {
            "original_v1_guard": V.info(V1_PATH),
            "admission_helper": {
                "source_path": str(ADMISSION_PATH),
                "approved_sha256": ADMISSION_SHA,
                "loaded_sha256": loaded_sha,
                "frozen_path": str(frozen),
                "frozen_sha256": frozen_sha,
            },
        }
    return _wjson(path, data)


V.shutil.copy2 = copy2_with_dependency
V.wjson = wjson_with_dependency_freeze


if __name__ == "__main__":
    raise SystemExit(V.main())
