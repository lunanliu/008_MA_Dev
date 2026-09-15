#!/usr/bin/env python3
"""Migrate published phase-OLS/CORDIC audit fields from MATLAB 7.3 MAT files.

This tool is intentionally read-only with respect to source MAT/JSON inputs.
It uses the pre-existing NI HDF5 C DLL through ctypes; it never starts MATLAB,
Vivado, or a MATLAB engine, and it does not recompute or synthesize fields.
"""
from __future__ import annotations
import argparse
import ctypes
import datetime as dt
import hashlib
import json
import os
import struct
import sys
from pathlib import Path
from typing import Any

ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
DEFAULT_OUT = ROOT / "sim/vectors/phase74_published"
HDF5_CANDIDATES = (
    Path(r"C:\Program Files\National Instruments\Shared\UsiCore\Bin\hdf5.dll"),
)
CASES = {
    "rcfo004": {
        "case_ids": (1, 3, 11, 21, 31, 41, 51, 61, 71, 81),
        "mat_name": "bit_audit.mat",
        "json_name": "result.json",
    },
    "rcfo003": {
        "case_ids": (1, 2, 3, 4, 5, 6, 7, 8, 9),
        "mat_name": "bit_NCO32_ROM10_C16F14_audit.mat",
        "json_name": "bit_NCO32_ROM10_C16F14.json",
    },
}
MAT_DATASETS = {
    "z_codes": "/ba/estimator/z_codes",
    "angle_turn_q31": "/ba/estimator/angle_turn_q31",
    "unwrapped_turn_q31": "/ba/estimator/unwrapped_turn_q31",
    "weighted_sum": "/ba/estimator/weighted_sum",
    "predicted_turn_q31": "/ba/estimator/predicted_turn_q31",
    "centered_residual_times74": "/ba/estimator/centered_residual_times74",
    "cordic.atan_turn_q31": "/ba/estimator/cordic/atan_turn_q31",
    "cordic.iterations": "/ba/estimator/cordic/iterations",
    "cordic.saturation": "/ba/estimator/cordic/saturation",
}
JSON_PHASE_FIELDS = (
    "bittrue.estimate.phase_q16",
    "bittrue.estimate.phase_linear",
    "bittrue.estimate.phase_fft_consistent",
    "bittrue.estimate.frequency_q16",
    "bittrue.estimate.fft_q16",
    "bittrue.estimate.spectrum_valid",
    "bittrue.estimate.coherence_grid",
    "bittrue.estimate.secondary_power_ratio",
)
JSON_CONTEXT_FIELDS = (
    "case_id",
    "profile",
    "bittrue.valid",
    "bittrue.mode",
    "formal_pass",
    "quality_screen_pass",
)
JSON_OPTIONAL_CONTEXT_FIELDS = ("label", "scope")
H5T_INTEGER = 0
H5T_FLOAT = 1
H5T_STRING = 3
H5T_COMPOUND = 6
H5T_ORDER_LE = 0
H5T_ORDER_BE = 1
H5T_SGN_NONE = 0
H5T_SGN_TWO = 1
H5G_DATASET = 1
H5P_DEFAULT = 0
H5F_ACC_RDONLY = 0


def utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def file_info(path: Path) -> dict[str, Any]:
    try:
        data = path.read_bytes()
    except Exception as exc:
        return {"path": str(path), "exists": False, "error": repr(exc)}
    return {"path": str(path), "exists": True, "bytes": len(data), "sha256": sha256_bytes(data)}


def atomic_json(path: Path, value: Any) -> str:
    text = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    os.replace(tmp, path)
    return sha256_bytes(text.encode("utf-8"))


def nested_get(obj: Any, dotted: str) -> tuple[bool, Any]:
    current = obj
    for part in dotted.split("."):
        if not isinstance(current, dict) or part not in current:
            return False, None
        current = current[part]
    return True, current


def nested_field(obj: Any, dotted: str) -> dict[str, Any]:
    present, value = nested_get(obj, dotted)
    return {"present": present, "value": value if present else None, "json_path": dotted}


def mat_header(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()[:128]
    text = raw[:116].decode("latin1", "replace").rstrip("\x00 ")
    version = raw[124:126].hex().upper() if len(raw) >= 126 else None
    endian = raw[126:128].decode("latin1", "replace") if len(raw) >= 128 else None
    return {
        "text": text,
        "version_bytes": version,
        "endian_indicator": endian,
        "format": "MATLAB 7.3 MAT-file / HDF5" if "MATLAB 7.3 MAT-file" in text else "unclassified",
        "first_128_sha256": sha256_bytes(raw),
    }


class Hdf5:
    """Small ctypes binding for the HDF5 APIs needed by MATLAB 7.3 datasets."""

    def __init__(self, dll_path: Path):
        self.path = dll_path
        self.dll = ctypes.WinDLL(str(dll_path))
        self.hid = ctypes.c_longlong
        self.hsize = ctypes.c_ulonglong
        self._declare()
        self.dll.H5open()
        self.version = self._version()

    def _declare(self) -> None:
        h = self.dll
        hid = self.hid
        hsize = self.hsize
        declarations = [
            ("H5open", [], ctypes.c_int),
            ("H5get_libversion", [ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)], ctypes.c_int),
            ("H5Fopen", [ctypes.c_char_p, ctypes.c_uint, hid], hid),
            ("H5Fclose", [hid], ctypes.c_int),
            ("H5Dopen2", [hid, ctypes.c_char_p, hid], hid),
            ("H5Dclose", [hid], ctypes.c_int),
            ("H5Dget_space", [hid], hid),
            ("H5Dget_type", [hid], hid),
            ("H5Dread", [hid, hid, hid, hid, hid, ctypes.c_void_p], ctypes.c_int),
            ("H5Sclose", [hid], ctypes.c_int),
            ("H5Sget_simple_extent_ndims", [hid], ctypes.c_int),
            ("H5Sget_simple_extent_dims", [hid, ctypes.POINTER(hsize), ctypes.POINTER(hsize)], ctypes.c_int),
            ("H5Tclose", [hid], ctypes.c_int),
            ("H5Tget_class", [hid], ctypes.c_int),
            ("H5Tget_size", [hid], ctypes.c_size_t),
            ("H5Tget_order", [hid], ctypes.c_int),
            ("H5Tget_sign", [hid], ctypes.c_int),
            ("H5Tget_nmembers", [hid], ctypes.c_int),
            ("H5Tget_member_name", [hid, ctypes.c_uint], ctypes.c_void_p),
            ("H5Tget_member_offset", [hid, ctypes.c_uint], ctypes.c_size_t),
            ("H5Tget_member_type", [hid, ctypes.c_uint], hid),
            ("H5free_memory", [ctypes.c_void_p], ctypes.c_int),
        ]
        for name, argtypes, restype in declarations:
            function = getattr(h, name)
            function.argtypes = argtypes
            function.restype = restype

    def _version(self) -> dict[str, int] | None:
        major, minor, release = ctypes.c_uint(), ctypes.c_uint(), ctypes.c_uint()
        if self.dll.H5get_libversion(ctypes.byref(major), ctypes.byref(minor), ctypes.byref(release)) != 0:
            return None
        return {"major": int(major.value), "minor": int(minor.value), "release": int(release.value)}

    def open(self, path: Path) -> "Hdf5File":
        handle = self.dll.H5Fopen(str(path).encode("utf-8"), H5F_ACC_RDONLY, H5P_DEFAULT)
        if handle < 0:
            raise RuntimeError(f"H5Fopen failed: {path}")
        return Hdf5File(self, handle)


class Hdf5File:
    def __init__(self, api: Hdf5, handle: int):
        self.api = api
        self.h = handle

    def close(self) -> None:
        if self.h is not None:
            self.api.dll.H5Fclose(self.h)
            self.h = None

    def __enter__(self) -> "Hdf5File":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _type_meta(self, type_id: int) -> dict[str, Any]:
        h = self.api.dll
        meta = {
            "class_id": int(h.H5Tget_class(type_id)),
            "size_bytes": int(h.H5Tget_size(type_id)),
            "order_id": int(h.H5Tget_order(type_id)),
            "sign_id": int(h.H5Tget_sign(type_id)),
        }
        if meta["class_id"] == H5T_COMPOUND:
            members = []
            for index in range(int(h.H5Tget_nmembers(type_id))):
                name_ptr = h.H5Tget_member_name(type_id, index)
                name = ctypes.string_at(name_ptr).decode("utf-8", "replace") if name_ptr else f"member_{index}"
                if name_ptr:
                    h.H5free_memory(name_ptr)
                member_type = h.H5Tget_member_type(type_id, index)
                try:
                    member_meta = self._type_meta(member_type)
                finally:
                    h.H5Tclose(member_type)
                members.append({"name": name, "offset_bytes": int(h.H5Tget_member_offset(type_id, index)), **member_meta})
            meta["members"] = members
        return meta

    @staticmethod
    def _format_for_integer(size: int, signed: bool, order_id: int) -> str:
        prefix = "<" if order_id == H5T_ORDER_LE else ">"
        table = {(1, True): "b", (2, True): "h", (4, True): "i", (8, True): "q",
                 (1, False): "B", (2, False): "H", (4, False): "I", (8, False): "Q"}
        if (size, signed) not in table:
            raise ValueError(f"unsupported integer type size={size} signed={signed}")
        return prefix + table[(size, signed)]

    @staticmethod
    def _format_for_float(size: int, order_id: int) -> str:
        prefix = "<" if order_id == H5T_ORDER_LE else ">"
        table = {4: "f", 8: "d"}
        if size not in table:
            raise ValueError(f"unsupported float type size={size}")
        return prefix + table[size]

    def _decode_values(self, raw: bytes, type_id: int, count: int, type_meta: dict[str, Any]) -> Any:
        class_id = type_meta["class_id"]
        size = type_meta["size_bytes"]
        order_id = type_meta["order_id"]
        h = self.api.dll
        if class_id == H5T_INTEGER:
            fmt = self._format_for_integer(size, h.H5Tget_sign(type_id) == H5T_SGN_TWO, order_id)
            width = struct.calcsize(fmt)
            return [struct.unpack_from(fmt, raw, index * width)[0] for index in range(count)]
        if class_id == H5T_FLOAT:
            fmt = self._format_for_float(size, order_id)
            width = struct.calcsize(fmt)
            return [struct.unpack_from(fmt, raw, index * width)[0] for index in range(count)]
        if class_id == H5T_COMPOUND:
            members = {member["name"]: member for member in type_meta.get("members", [])}
            if "real" not in members or "imag" not in members:
                raise ValueError(f"compound dataset lacks real/imag members: {sorted(members)}")
            real = members["real"]
            imag = members["imag"]
            real_fmt = self._format_for_float(real["size_bytes"], real["order_id"])
            imag_fmt = self._format_for_float(imag["size_bytes"], imag["order_id"])
            values = []
            for index in range(count):
                base = index * size
                values.append({
                    "real": struct.unpack_from(real_fmt, raw, base + real["offset_bytes"])[0],
                    "imag": struct.unpack_from(imag_fmt, raw, base + imag["offset_bytes"])[0],
                })
            return values
        if class_id == H5T_STRING:
            return [raw[index * size:(index + 1) * size].rstrip(b"\x00").decode("utf-8", "replace") for index in range(count)]
        raise ValueError(f"unsupported HDF5 datatype class={class_id}")

    def read_dataset(self, dataset_path: str) -> dict[str, Any]:
        h = self.api.dll
        dataset = h.H5Dopen2(self.h, dataset_path.encode("utf-8"), H5P_DEFAULT)
        if dataset < 0:
            raise KeyError(dataset_path)
        space = h.H5Dget_space(dataset)
        type_id = h.H5Dget_type(dataset)
        if space < 0 or type_id < 0:
            if type_id >= 0:
                h.H5Tclose(type_id)
            if space >= 0:
                h.H5Sclose(space)
            h.H5Dclose(dataset)
            raise RuntimeError(f"HDF5 metadata query failed: {dataset_path}")
        try:
            ndim = int(h.H5Sget_simple_extent_ndims(space))
            dimensions = (self.api.hsize * ndim)() if ndim else None
            if ndim and h.H5Sget_simple_extent_dims(space, dimensions, None) < 0:
                raise RuntimeError(f"H5Sget_simple_extent_dims failed: {dataset_path}")
            shape = [int(dimensions[index]) for index in range(ndim)] if ndim else []
            count = 1
            for dimension in shape:
                count *= dimension
            if not shape:
                count = 1
            type_meta = self._type_meta(type_id)
            total_bytes = max(1, count * type_meta["size_bytes"])
            buffer = ctypes.create_string_buffer(total_bytes)
            if h.H5Dread(dataset, type_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT, buffer) < 0:
                raise RuntimeError(f"H5Dread failed: {dataset_path}")
            values = self._decode_values(buffer.raw, type_id, count, type_meta)
            return {"path": dataset_path, "shape": shape, "count": count, "datatype": type_meta, "values": values}
        finally:
            h.H5Tclose(type_id)
            h.H5Sclose(space)
            h.H5Dclose(dataset)


def scalar_or_values(dataset: dict[str, Any]) -> dict[str, Any]:
    values = dataset["values"]
    out = {"dataset": dataset}
    if len(values) == 1:
        out["value"] = values[0]
    return out


def select_json_context(source_json: dict[str, Any]) -> dict[str, Any]:
    return {field: nested_field(source_json, field) for field in JSON_CONTEXT_FIELDS}


def select_phase_fields(source_json: dict[str, Any]) -> dict[str, Any]:
    return {field: nested_field(source_json, field) for field in JSON_PHASE_FIELDS}


def source_case(root: Path, family: str, case_id: int) -> tuple[Path, Path]:
    spec = CASES[family]
    directory = root / "sim/reference" / family / "results" / f"case_{case_id:03d}"
    return directory / spec["mat_name"], directory / spec["json_name"]


def case_payload(root: Path, api: Hdf5, tool_path: Path, family: str, case_id: int) -> dict[str, Any]:
    mat_path, json_path = source_case(root, family, case_id)
    mat_obj = json.loads(json_path.read_text(encoding="utf-8-sig"))
    missing: list[str] = []
    datasets: dict[str, Any] = {}
    with api.open(mat_path) as hdf:
        for field, dataset_path in MAT_DATASETS.items():
            try:
                dataset = hdf.read_dataset(dataset_path)
            except KeyError:
                missing.append(f"mat.{field}")
                continue
            except Exception as exc:
                missing.append(f"mat.{field}:decode_error:{exc}")
                continue
            datasets[field] = scalar_or_values(dataset) if dataset["count"] == 1 else dataset
    context = select_json_context(mat_obj)
    optional_context = {field: nested_field(mat_obj, field) for field in JSON_OPTIONAL_CONTEXT_FIELDS}
    phase_fields = select_phase_fields(mat_obj)
    missing = []
    optional_missing = []
    for field, item in phase_fields.items():
        if not item["present"]:
            missing.append(f"json.{field}")
    for field, item in context.items():
        if not item["present"]:
            missing.append(f"json.{field}")
    for field, item in optional_context.items():
        if not item["present"]:
            optional_missing.append(f"json.{field}")
    expected_lengths = {
        "z_codes": 74,
        "angle_turn_q31": 74,
        "unwrapped_turn_q31": 74,
        "weighted_sum": 1,
        "predicted_turn_q31": 74,
        "centered_residual_times74": 74,
        "cordic.atan_turn_q31": 24,
        "cordic.iterations": 1,
        "cordic.saturation": 1,
    }
    length_checks = {}
    for field, expected in expected_lengths.items():
        if field not in datasets:
            length_checks[field] = {"expected": expected, "actual": None, "matches": False}
            continue
        actual = int(datasets[field]["dataset"]["count"] if "dataset" in datasets[field] else datasets[field]["count"])
        length_checks[field] = {"expected": expected, "actual": actual, "matches": actual == expected}
        if actual != expected:
            missing.append(f"mat.{field}:length={actual},expected={expected}")
    status = "PASS" if not missing else "PARTIAL_MISSING_FIELDS"
    return {
        "schema": "phase74_published_case_v1",
        "generated_utc": utc(),
        "family": family,
        "case_id": case_id,
        "status": status,
        "source_inputs": {
            "mat": {**file_info(mat_path), "header": mat_header(mat_path)},
            "json": file_info(json_path),
        },
        "decoder": {
            "tool_path": str(tool_path),
            "tool_sha256": sha256_bytes(tool_path.read_bytes()),
            "python_executable": sys.executable,
            "python_version": sys.version,
            "hdf5_library": file_info(api.path),
            "hdf5_version": api.version,
            "method": "ctypes HDF5 C API; MATLAB 7.3 MAT-file read-only",
            "matlab_started": False,
            "vivado_started": False,
            "recomputed_fields": False,
        },
        "json_context": context,
        "json_optional_context": optional_context,
        "phase_fields": phase_fields,
        "optional_missing_fields": optional_missing,
        "cordic_json_context": {
            "bittrue.coarse_rotation": nested_field(mat_obj, "bittrue.coarse_rotation"),
            "bittrue.final_rotation": nested_field(mat_obj, "bittrue.final_rotation"),
            "bittrue.front": nested_field(mat_obj, "bittrue.front"),
        },
        "mat_datasets": datasets,
        "length_checks": length_checks,
        "missing_fields": missing,
    }


def normalize_existing(output: Path, tool_path: Path) -> int:
    rows = []
    for target in sorted(output.glob("*.json")):
        if target.name == "phase74_published_manifest.json":
            continue
        payload = json.loads(target.read_text(encoding="utf-8"))
        optional_missing = list(payload.get("optional_missing_fields", []))
        missing = []
        for field in payload.get("missing_fields", []):
            if field in {"json.label", "json.scope"}:
                optional_missing.append(field)
            else:
                missing.append(field)
        z_values = payload.get("mat_datasets", {}).get("z_codes", {}).get("values", [])
        converted = 0
        for item in z_values:
            if not isinstance(item, dict):
                continue
            for component in ("real", "imag"):
                value = item.get(component)
                if isinstance(value, float) and value.is_integer():
                    item[component] = int(value)
                    converted += 1
        payload["missing_fields"] = sorted(set(missing))
        payload["optional_missing_fields"] = sorted(set(optional_missing))
        payload["status"] = "PASS" if not payload["missing_fields"] else "PARTIAL_MISSING_FIELDS"
        payload["normalization"] = {
            "performed_utc": utc(),
            "source_redecoded": False,
            "z_codes_integral_iq_components_converted": converted,
            "reason": "Context-only missing label/scope is optional for rcfo004; preserve estimator field names and expose exact I/Q components as integers.",
        }
        digest = atomic_json(target, payload)
        rows.append({"path": str(target), "bytes": target.stat().st_size, "sha256": digest})
    if not rows:
        raise SystemExit(f"No case JSON files found for normalization: {output}")
    summaries = []
    for row in rows:
        payload = json.loads(Path(row["path"]).read_text(encoding="utf-8"))
        summaries.append({"family":payload.get("family"),"case_id":payload.get("case_id"),"status":payload.get("status"),"missing_fields":payload.get("missing_fields",[]),"optional_missing_fields":payload.get("optional_missing_fields",[])})
    first = json.loads(Path(rows[0]["path"]).read_text(encoding="utf-8"))
    manifest = {
        "schema":"phase74_published_manifest_v1",
        "generated_utc":utc(),
        "root":str(ROOT),
        "output_directory":str(output),
        "selected_cases":{family:list(spec["case_ids"]) for family,spec in CASES.items()},
        "source_file_count":len(rows)*2,
        "output_case_count":len(rows),
        "output_files":rows,
        "summary":summaries,
        "all_cases_pass":all(item["status"]=="PASS" for item in summaries),
        "decoder":{
            "tool_path":str(tool_path),
            "tool_sha256":sha256_bytes(tool_path.read_bytes()),
            "python_executable":sys.executable,
            "python_version":sys.version,
            "normalization_only":True,
            "source_redecoded":False,
            "matlab_started":False,
            "vivado_started":False,
            "global_package_install":False,
            "new_signal_generated":False,
            "original_hdf5_library":first.get("decoder",{}).get("hdf5_library"),
            "original_hdf5_version":first.get("decoder",{}).get("hdf5_version"),
        },
    }
    manifest_path=output/"phase74_published_manifest.json"
    manifest_sha=atomic_json(manifest_path,manifest)
    print(json.dumps({"schema":manifest["schema"],"status":"PASS" if manifest["all_cases_pass"] else "PARTIAL_MISSING_FIELDS","output_directory":str(output),"case_count":len(rows),"manifest":str(manifest_path),"manifest_sha256":manifest_sha,"normalization_only":True,"source_redecoded":False,"missing_case_count":sum(1 for item in summaries if item["status"]!="PASS")},ensure_ascii=False))
    return 0 if manifest["all_cases_pass"] else 2
def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--normalize-existing", action="store_true", help="Reclassify existing outputs without rereading source MAT/JSON.")
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output.resolve()
    tool_path = Path(__file__).resolve()
    if args.normalize_existing:
        return normalize_existing(output, tool_path)
    dll_path = next((candidate for candidate in HDF5_CANDIDATES if candidate.is_file()), None)
    if dll_path is None:
        raise SystemExit("No approved existing HDF5 DLL found; no MATLAB fallback is permitted.")
    output.mkdir(parents=True, exist_ok=True)
    api = Hdf5(dll_path)
    all_cases = [(family, case_id) for family, spec in CASES.items() for case_id in spec["case_ids"]]
    output_files = []
    summaries = []
    for family, case_id in all_cases:
        filename = f"{family}_case_{case_id:03d}.json"
        target = output / filename
        if target.exists() and not args.overwrite:
            raise SystemExit(f"Refusing to overwrite existing output: {target}")
        payload = case_payload(root, api, tool_path, family, case_id)
        digest = atomic_json(target, payload)
        output_files.append({"path": str(target), "bytes": target.stat().st_size, "sha256": digest})
        summaries.append({"family": family, "case_id": case_id, "status": payload["status"], "missing_fields": payload["missing_fields"]})
    manifest = {
        "schema": "phase74_published_manifest_v1",
        "generated_utc": utc(),
        "root": str(root),
        "output_directory": str(output),
        "selected_cases": {family: list(spec["case_ids"]) for family, spec in CASES.items()},
        "source_file_count": len(all_cases) * 2,
        "output_case_count": len(output_files),
        "output_files": output_files,
        "summary": summaries,
        "all_cases_pass": all(item["status"] == "PASS" for item in summaries),
        "decoder": {
            "tool_path": str(tool_path),
            "tool_sha256": sha256_bytes(tool_path.read_bytes()),
            "python_executable": sys.executable,
            "python_version": sys.version,
            "hdf5_library": file_info(api.path),
            "hdf5_version": api.version,
            "matlab_started": False,
            "vivado_started": False,
            "global_package_install": False,
            "new_signal_generated": False,
        },
    }
    manifest_path = output / "phase74_published_manifest.json"
    if manifest_path.exists() and not args.overwrite:
        raise SystemExit(f"Refusing to overwrite existing output: {manifest_path}")
    manifest_sha = atomic_json(manifest_path, manifest)
    print(json.dumps({
        "schema": manifest["schema"],
        "status": "PASS" if manifest["all_cases_pass"] else "PARTIAL_MISSING_FIELDS",
        "output_directory": str(output),
        "case_count": len(output_files),
        "manifest": str(manifest_path),
        "manifest_sha256": manifest_sha,
        "missing_case_count": sum(1 for item in summaries if item["status"] != "PASS"),
    }, ensure_ascii=False))
    return 0 if manifest["all_cases_pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
