#!/usr/bin/env python3
"""CFO-FRONTDATA007: read-only HDF5 chunk extraction and integer checks."""
from __future__ import annotations
import argparse, csv, ctypes, datetime as dt, gc, hashlib, json, math, os
from pathlib import Path
import struct, subprocess, sys, time, traceback, zlib
from typing import Any

ROOT = Path(r"D:\008_MA_Dev\T11_CFO")
LOCK_PATH = ROOT / "docs" / "FRONTDATA007_SOURCE_LOCK.json"
HDF5_PATH = Path(r"C:\Program Files\National Instruments\Shared\UsiCore\Bin\hdf5.dll")
CSV_PATH = ROOT / "matlab" / "waveform" / "payload_pilot_cells.csv"
DATASETS = {
    "pilot_fft_codes": "/ba/front/pilot_fft_codes",
    "pilot_coeff_codes": "/ba/front/pilot_coeff_codes",
    "pilot_product_codes": "/ba/front/pilot_product_codes",
    "front_z_codes": "/ba/front/z_codes",
    "estimator_z_codes": "/ba/estimator/z_codes",
}
DATASET_COUNT = 5
H5T_INTEGER, H5T_FLOAT, H5T_STRING, H5T_COMPOUND = 0, 1, 3, 6
H5T_ORDER_LE, H5T_ORDER_BE, H5T_SGN_TWO = 0, 1, 1
H5P_DEFAULT, H5F_ACC_RDONLY, H5D_CHUNKED, H5Z_DEFLATE = 0, 0, 2, 1


class ControlledStop(RuntimeError):
    pass


class HardTimeout(ControlledStop):
    pass


class MemoryProtection(ControlledStop):
    pass


def utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def sha256_path(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while block := f.read(1024 * 1024):
            h.update(block)
    return h.hexdigest().upper()


def file_info(path: Path) -> dict[str, Any]:
    try:
        p = path.resolve()
        return {
            "path": str(p),
            "exists": p.is_file(),
            "bytes": p.stat().st_size if p.is_file() else None,
            "sha256": sha256_path(p) if p.is_file() else None,
        }
    except Exception as exc:
        return {"path": str(path), "exists": False, "bytes": None, "sha256": None, "error": repr(exc)}


def write_json(path: Path, value: Any, indent: int | None = None) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(
        value, ensure_ascii=False, allow_nan=False, indent=indent,
        separators=None if indent is not None else (",", ":"),
    ) + "\n"
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    os.replace(tmp, path)
    return sha256_bytes(text.encode("utf-8"))


def strict_int(value: Any, label: str) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{label}: boolean code")
    if isinstance(value, int):
        return value
    if isinstance(value, float) and math.isfinite(value) and value.is_integer():
        return int(value)
    raise ValueError(f"{label}: non-integral stored value {value!r}")


def rne_pow2(n: int, shift: int) -> int:
    d = 1 << shift
    q, r = divmod(n, d)
    if r * 2 > d or (r * 2 == d and q & 1):
        q += 1
    return q


def clamp(value: int, bits: int) -> int:
    return max(-(1 << (bits - 1)), min((1 << (bits - 1)) - 1, value))


def checked_signed(value: int, bits: int, label: str) -> None:
    if not (-(1 << (bits - 1)) <= value <= (1 << (bits - 1)) - 1):
        raise ValueError(f"{label}: outside S{bits}: {value}")


def pair_sha256(values: list[tuple[int, int]]) -> str:
    return sha256_bytes(b"".join(struct.pack("<qq", a, b) for a, b in values))


def pair_list(values: list[tuple[int, int]]) -> list[list[int]]:
    return [[a, b] for a, b in values]


def as_pairs(values: list[Any], meta: dict[str, Any], label: str) -> list[tuple[int, int]]:
    if meta.get("class_id") != H5T_COMPOUND:
        raise ValueError(f"{label}: expected compound datatype")
    names = {m["name"] for m in meta.get("members", [])}
    if not {"real", "imag"} <= names:
        raise ValueError(f"{label}: missing real/imag members")
    out = []
    for i, item in enumerate(values):
        if not isinstance(item, dict):
            raise ValueError(f"{label}[{i}]: not compound value")
        out.append((strict_int(item["real"], f"{label}[{i}].real"),
                    strict_int(item["imag"], f"{label}[{i}].imag")))
    return out


def nested_pairs(values: list[tuple[int, int]], shape: list[int]) -> Any:
    if len(shape) == 1:
        return pair_list(values)
    width = shape[-1]
    rows = math.prod(shape[:-1])
    if rows * width != len(values):
        raise ValueError(f"shape/value count mismatch {shape}/{len(values)}")
    return [pair_list(values[i * width:(i + 1) * width]) for i in range(rows)]


def nested_get(obj: Any, dotted: str) -> tuple[bool, Any]:
    cur = obj
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return False, None
        cur = cur[part]
    return True, cur


def selected_field(obj: Any, dotted: str) -> dict[str, Any]:
    present, value = nested_get(obj, dotted)
    return {"present": present, "value": value if present else None, "json_path": dotted}


def mat_header(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()[:128]
    text = raw[:116].decode("latin1", "replace").rstrip("\x00 ")
    return {
        "text": text,
        "version_bytes": raw[124:126].hex().upper() if len(raw) >= 126 else None,
        "endian_indicator": raw[126:128].decode("latin1", "replace") if len(raw) >= 128 else None,
        "format": "MATLAB 7.3 MAT-file / HDF5" if "MATLAB 7.3 MAT-file" in text else "unclassified",
        "first_128_sha256": sha256_bytes(raw),
    }


class Guard:
    class MemStatus(ctypes.Structure):
        _fields_ = [
            ("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
            ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
            ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
            ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
            ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
        ]

    class ProcCounters(ctypes.Structure):
        _fields_ = [
            ("cb", ctypes.c_ulong), ("PageFaultCount", ctypes.c_ulong),
            ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
            ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
            ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
            ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
        ]

    def __init__(self, timeout: float):
        self.start = time.monotonic()
        self.deadline = self.start + timeout
        self.low_since: float | None = None
        self.samples: list[dict[str, Any]] = []
        self.max_ws = 0
        self.max_peak_ws = 0
        self.k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self.psapi = ctypes.WinDLL("psapi", use_last_error=True)
        self.k32.GlobalMemoryStatusEx.argtypes = [ctypes.POINTER(self.MemStatus)]
        self.k32.GlobalMemoryStatusEx.restype = ctypes.c_int
        self.k32.GetCurrentProcess.argtypes = []
        self.k32.GetCurrentProcess.restype = ctypes.c_void_p
        self.psapi.GetProcessMemoryInfo.argtypes = [
            ctypes.c_void_p, ctypes.POINTER(self.ProcCounters), ctypes.c_ulong
        ]
        self.psapi.GetProcessMemoryInfo.restype = ctypes.c_int

    def snapshot(self, stage: str) -> dict[str, Any]:
        sm = self.MemStatus()
        sm.dwLength = ctypes.sizeof(sm)
        system: dict[str, Any] = {}
        if self.k32.GlobalMemoryStatusEx(ctypes.byref(sm)):
            system = {
                "memory_load_percent": int(sm.dwMemoryLoad),
                "total_physical_bytes": int(sm.ullTotalPhys),
                "available_physical_bytes": int(sm.ullAvailPhys),
                "available_physical_gib": int(sm.ullAvailPhys) / 1024**3,
            }
        pm = self.ProcCounters()
        pm.cb = ctypes.sizeof(pm)
        process: dict[str, Any] = {}
        if self.psapi.GetProcessMemoryInfo(self.k32.GetCurrentProcess(), ctypes.byref(pm), pm.cb):
            process = {
                "working_set_bytes": int(pm.WorkingSetSize),
                "working_set_gib": int(pm.WorkingSetSize) / 1024**3,
                "peak_working_set_bytes": int(pm.PeakWorkingSetSize),
                "peak_working_set_gib": int(pm.PeakWorkingSetSize) / 1024**3,
                "pagefile_usage_bytes": int(pm.PagefileUsage),
            }
            self.max_ws = max(self.max_ws, int(pm.WorkingSetSize))
            self.max_peak_ws = max(self.max_peak_ws, int(pm.PeakWorkingSetSize))
        item = {
            "utc": utc(), "stage": stage,
            "elapsed_seconds": round(time.monotonic() - self.start, 3),
            "system": system, "process": process,
        }
        self.samples.append(item)
        return item

    def tick(self, stage: str) -> dict[str, Any]:
        now = time.monotonic()
        if now > self.deadline:
            raise HardTimeout(f"hard timeout at {stage}")
        item = self.snapshot(stage)
        available = item.get("system", {}).get("available_physical_bytes")
        if available is not None:
            if available < int(.25 * 1024**3):
                raise MemoryProtection(f"available physical <0.25 GiB at {stage}")
            if available < int(.5 * 1024**3):
# FRONTDATA_CHUNK_1_END
                self.low_since = self.low_since or now
                if now - self.low_since >= 30:
                    raise MemoryProtection(f"available physical <0.5 GiB for 30 seconds at {stage}")
            else:
                self.low_since = None
        return item

    def report(self) -> dict[str, Any]:
        return {
            "elapsed_seconds": round(time.monotonic() - self.start, 3),
            "sample_count": len(self.samples),
            "max_process_working_set_bytes": self.max_ws,
            "max_process_peak_working_set_bytes": self.max_peak_ws,
            "warning_line_bytes": 1024**3,
            "warning_line_crossed": self.max_peak_ws >= 1024**3,
            "last_sample": self.snapshot("final"),
            "samples": self.samples,
        }


def process_inventory() -> list[dict[str, Any]]:
    k = ctypes.WinDLL("kernel32", use_last_error=True)
    snap = k.CreateToolhelp32Snapshot
    snap.argtypes = [ctypes.c_ulong, ctypes.c_ulong]
    snap.restype = ctypes.c_void_p
    close = k.CloseHandle
    close.argtypes = [ctypes.c_void_p]
    first = k.Process32FirstW
    first.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    first.restype = ctypes.c_int
    nxt = k.Process32NextW
    nxt.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    nxt.restype = ctypes.c_int

    class Entry(ctypes.Structure):
        _fields_ = [
            ("dwSize", ctypes.c_ulong), ("cntUsage", ctypes.c_ulong),
            ("pid", ctypes.c_ulong), ("heap", ctypes.c_void_p),
            ("module", ctypes.c_ulong), ("threads", ctypes.c_ulong),
            ("parent", ctypes.c_ulong), ("priority", ctypes.c_long),
            ("flags", ctypes.c_ulong), ("exe", ctypes.c_wchar * 260),
        ]

    names = {"matlab.exe", "vivado.exe", "xsim.exe", "xsimk.exe",
             "xelab.exe", "xvlog.exe", "xvhdl.exe", "python.exe"}
    handle = snap(0x2, 0)
    invalid = ctypes.c_void_p(-1).value
    if handle in (None, invalid):
        return [{"error": f"CreateToolhelp32Snapshot:{ctypes.get_last_error()}"}]
    rows = []
    try:
        entry = Entry()
        entry.dwSize = ctypes.sizeof(entry)
        if not first(handle, ctypes.byref(entry)):
            return []
        while True:
            if entry.exe.lower() in names:
                rows.append({"pid": int(entry.pid), "name": entry.exe})
            entry = Entry()
            entry.dwSize = ctypes.sizeof(entry)
            if not nxt(handle, ctypes.byref(entry)):
                break
    finally:
        close(handle)
    return sorted(rows, key=lambda row: (row["name"].lower(), row["pid"]))


class H5:
    hid = ctypes.c_longlong
    hsize = ctypes.c_ulonglong

    def __init__(self, path: Path):
        self.path = path
        self.dll = ctypes.WinDLL(str(path))
        self.declare()
        if self.dll.H5open() < 0:
            raise RuntimeError("H5open failed")
        a, b, c = ctypes.c_uint(), ctypes.c_uint(), ctypes.c_uint()
        self.dll.H5get_libversion(ctypes.byref(a), ctypes.byref(b), ctypes.byref(c))
        self.version = {"major": int(a.value), "minor": int(b.value), "release": int(c.value)}

    def declare(self) -> None:
        h = self.dll
        defs = [
            ("H5open", [], ctypes.c_int), ("H5close", [], ctypes.c_int),
            ("H5get_libversion", [ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)], ctypes.c_int),
            ("H5Fopen", [ctypes.c_char_p, ctypes.c_uint, self.hid], self.hid),
            ("H5Fclose", [self.hid], ctypes.c_int),
            ("H5Dopen2", [self.hid, ctypes.c_char_p, self.hid], self.hid),
            ("H5Dclose", [self.hid], ctypes.c_int),
            ("H5Dget_space", [self.hid], self.hid), ("H5Dget_type", [self.hid], self.hid),
            ("H5Dread", [self.hid, self.hid, self.hid, self.hid, self.hid, ctypes.c_void_p], ctypes.c_int),
            ("H5Dget_create_plist", [self.hid], self.hid),
            ("H5Pget_layout", [self.hid], ctypes.c_int),
            ("H5Dget_chunk_storage_size", [self.hid, ctypes.POINTER(self.hsize)], self.hsize),
            ("H5Dread_chunk", [self.hid, self.hid, ctypes.POINTER(self.hsize), ctypes.POINTER(ctypes.c_uint), ctypes.c_void_p], ctypes.c_int),
            ("H5Sclose", [self.hid], ctypes.c_int),
            ("H5Sget_simple_extent_ndims", [self.hid], ctypes.c_int),
            ("H5Sget_simple_extent_dims", [self.hid, ctypes.POINTER(self.hsize), ctypes.POINTER(self.hsize)], ctypes.c_int),
            ("H5Tclose", [self.hid], ctypes.c_int),
            ("H5Tget_class", [self.hid], ctypes.c_int), ("H5Tget_size", [self.hid], ctypes.c_size_t),
            ("H5Tget_order", [self.hid], ctypes.c_int), ("H5Tget_sign", [self.hid], ctypes.c_int),
            ("H5Tget_nmembers", [self.hid], ctypes.c_int),
            ("H5Tget_member_name", [self.hid, ctypes.c_uint], ctypes.c_void_p),
            ("H5Tget_member_offset", [self.hid, ctypes.c_uint], ctypes.c_size_t),
            ("H5Tget_member_type", [self.hid, ctypes.c_uint], self.hid),
            ("H5free_memory", [ctypes.c_void_p], ctypes.c_int),
            ("H5Pclose", [self.hid], ctypes.c_int),
            ("H5Pget_chunk", [self.hid, ctypes.c_int, ctypes.POINTER(self.hsize)], ctypes.c_int),
            ("H5Pget_nfilters", [self.hid], ctypes.c_int),
            ("H5Pget_filter2", [self.hid, ctypes.c_uint, ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_size_t), ctypes.POINTER(ctypes.c_uint), ctypes.c_size_t, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint)], ctypes.c_uint),
        ]
        for name, args, result in defs:
            fn = getattr(h, name)
            fn.argtypes, fn.restype = args, result

    def open(self, path: Path) -> "H5File":
        handle = self.dll.H5Fopen(str(path).encode(), H5F_ACC_RDONLY, H5P_DEFAULT)
        if handle < 0:
            raise RuntimeError(f"H5Fopen failed: {path}")
        return H5File(self, handle)


class H5File:
    def __init__(self, api: H5, handle: int):
        self.api, self.handle = api, handle

    def __enter__(self) -> "H5File":
        return self

    def __exit__(self, *_: Any) -> None:
        if self.handle is not None:
            self.api.dll.H5Fclose(self.handle)
            self.handle = None

    def type_meta(self, type_id: int) -> dict[str, Any]:
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
                name = ctypes.string_at(name_ptr).decode("utf-8", "replace")
                h.H5free_memory(name_ptr)
                member = h.H5Tget_member_type(type_id, index)
                try:
                    child = self.type_meta(member)
                finally:
                    h.H5Tclose(member)
                members.append({
                    "name": name,
                    "offset_bytes": int(h.H5Tget_member_offset(type_id, index)),
                    **child,
                })
            meta["members"] = members
        return meta

    @staticmethod
    def fmt_int(size: int, signed: bool, order: int) -> str:
        prefix = "<" if order == H5T_ORDER_LE else ">" if order == H5T_ORDER_BE else None
        table = {(1, True): "b", (2, True): "h", (4, True): "i", (8, True): "q",
                 (1, False): "B", (2, False): "H", (4, False): "I", (8, False): "Q"}
        if prefix is None or (size, signed) not in table:
            raise ValueError(f"unsupported integer type {size}/{signed}/{order}")
        return prefix + table[(size, signed)]

    @staticmethod
    def fmt_float(size: int, order: int) -> str:
        prefix = "<" if order == H5T_ORDER_LE else ">" if order == H5T_ORDER_BE else None
        if prefix is None or size not in (4, 8):
            raise ValueError(f"unsupported float type {size}/{order}")
        return prefix + ("f" if size == 4 else "d")

    def decode(self, raw: bytes, type_id: int, count: int, meta: dict[str, Any]) -> list[Any]:
        h = self.api.dll
        cls, size = meta["class_id"], meta["size_bytes"]
        if cls == H5T_INTEGER:
            fmt = self.fmt_int(size, h.H5Tget_sign(type_id) == H5T_SGN_TWO, meta["order_id"])
            width = struct.calcsize(fmt)
            return [struct.unpack_from(fmt, raw, i * width)[0] for i in range(count)]
        if cls == H5T_FLOAT:
            fmt = self.fmt_float(size, meta["order_id"])
            width = struct.calcsize(fmt)
            return [struct.unpack_from(fmt, raw, i * width)[0] for i in range(count)]
        if cls == H5T_COMPOUND:
            members = {m["name"]: m for m in meta["members"]}
            real, imag = members["real"], members["imag"]
            rf = self.fmt_float(real["size_bytes"], real["order_id"])
            imf = self.fmt_float(imag["size_bytes"], imag["order_id"])
            return [
                {
                    "real": struct.unpack_from(rf, raw, i * size + real["offset_bytes"])[0],
                    "imag": struct.unpack_from(imf, raw, i * size + imag["offset_bytes"])[0],
                }
                for i in range(count)
            ]
        if cls == H5T_STRING:
# FRONTDATA_CHUNK_2_END
            return [raw[i * size:(i + 1) * size].rstrip(b"\0").decode("utf-8", "replace") for i in range(count)]
        raise ValueError(f"unsupported HDF5 class {cls}")

    def filters(self, plist: int) -> list[dict[str, Any]]:
        h = self.api.dll
        count = int(h.H5Pget_nfilters(plist))
        if count < 0:
            raise RuntimeError("H5Pget_nfilters failed")
        out = []
        for index in range(count):
            flags, ncd, config = ctypes.c_uint(), ctypes.c_size_t(32), ctypes.c_uint()
            cd = (ctypes.c_uint * 32)()
            name = ctypes.create_string_buffer(256)
            fid = int(h.H5Pget_filter2(
                plist, index, ctypes.byref(flags), ctypes.byref(ncd), cd,
                ctypes.sizeof(name), ctypes.cast(name, ctypes.c_void_p), ctypes.byref(config)
            ))
            out.append({
                "index": index, "id": fid, "name": name.value.decode("utf-8", "replace"),
                "flags": int(flags.value), "cd_values": [int(cd[i]) for i in range(min(int(ncd.value), 32))],
                "filter_config": int(config.value),
            })
        return out

    def raw_front(self, dset: int, shape: list[int], meta: dict[str, Any],
                   chunks: list[int], filters: list[dict[str, Any]],
                   guard: Guard, label: str) -> tuple[list[Any], dict[str, Any]]:
        if shape != [74, 820] or len(chunks) != 2 or chunks[0] != 74:
            raise ValueError(f"{label}: unexpected shape/chunks {shape}/{chunks}")
        if len(filters) != 1 or filters[0]["id"] != H5Z_DEFLATE:
            raise ValueError(f"{label}: unsupported filter pipeline {filters!r}")
        h = self.api.dll
        cwidth, full_count = chunks[1], chunks[0] * chunks[1]
        expected_bytes = full_count * meta["size_bytes"]
        result: list[Any] = [None] * (74 * 820)
        chunk_records = []
        for col in range(0, 820, cwidth):
            guard.tick(f"{label}:chunk_{col}")
            off = (self.api.hsize * 2)(0, col)
            stored = int(h.H5Dget_chunk_storage_size(dset, off))
            if stored <= 0:
                raise RuntimeError(f"{label}: empty chunk at {col}")
            buf = ctypes.create_string_buffer(stored)
            mask = ctypes.c_uint()
            if h.H5Dread_chunk(dset, H5P_DEFAULT, off, ctypes.byref(mask), buf) < 0:
                raise RuntimeError(f"{label}: H5Dread_chunk failed at {col}")
            raw = buf.raw[:stored]
            if mask.value & ~1:
                raise ValueError(f"{label}: unsupported filter mask 0x{mask.value:X}")
            decoded = raw if mask.value & 1 else zlib.decompress(raw)
            if len(decoded) != expected_bytes:
                raise ValueError(f"{label}: chunk bytes {len(decoded)} != {expected_bytes}")
            chunk_values = self.decode(decoded, 0, full_count, meta)
            width = min(cwidth, 820 - col)
            for row in range(74):
                for local in range(width):
                    result[row * 820 + col + local] = chunk_values[row * cwidth + local]
            chunk_records.append({
                "offset": [0, col], "valid_shape": [74, width], "chunk_shape": chunks,
                "stored_bytes": stored, "decoded_bytes": len(decoded), "filter_mask": int(mask.value),
                "decode_method": "raw_chunk_filter_mask_bit0_set" if mask.value & 1 else "zlib_deflate",
                "raw_sha256": sha256_bytes(raw), "decoded_sha256": sha256_bytes(decoded),
            })
        if any(value is None for value in result):
            raise RuntimeError(f"{label}: incomplete chunk coverage")
        return result, {
            "read_method": "H5Dread_chunk", "chunk_records": chunk_records,
            "valid_elements_decoded": len(result), "full_chunk_elements": full_count,
        }

    def read(self, path: str, guard: Guard, raw: bool, label: str) -> dict[str, Any]:
        h = self.api.dll
        dset = h.H5Dopen2(self.handle, path.encode(), H5P_DEFAULT)
        if dset < 0:
            raise KeyError(path)
        space, typ, plist = h.H5Dget_space(dset), h.H5Dget_type(dset), -1
        try:
            if space < 0 or typ < 0:
                raise RuntimeError(f"metadata query failed: {path}")
            ndim = int(h.H5Sget_simple_extent_ndims(space))
            dims = (self.api.hsize * ndim)() if ndim else None
            if ndim and h.H5Sget_simple_extent_dims(space, dims, None) < 0:
                raise RuntimeError(f"H5Sget_simple_extent_dims failed: {path}")
            shape = [int(dims[i]) for i in range(ndim)] if ndim else []
            count = math.prod(shape) if shape else 1
            meta = self.type_meta(typ)
            plist = h.H5Dget_create_plist(dset)
            if plist < 0:
                raise RuntimeError(f"H5Dget_create_plist failed: {path}")
            layout = int(h.H5Pget_layout(plist))
            filters = self.filters(plist)
            chunks: list[int] = []
            if layout == H5D_CHUNKED:
                cdims = (self.api.hsize * max(1, ndim))()
                if h.H5Pget_chunk(plist, max(1, ndim), cdims) < 0:
                    raise RuntimeError(f"H5Pget_chunk failed: {path}")
                chunks = [int(cdims[i]) for i in range(ndim)]
            if raw:
                values, storage = self.raw_front(dset, shape, meta, chunks, filters, guard, label)
            else:
                buf = ctypes.create_string_buffer(max(1, count * meta["size_bytes"]))
                if h.H5Dread(dset, typ, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT, buf) < 0:
                    raise RuntimeError(f"H5Dread failed: {path}")
                values = self.decode(buf.raw, typ, count, meta)
                storage = {"read_method": "H5Dread", "valid_elements_decoded": len(values)}
            return {
                "path": path, "shape": shape, "count": count, "datatype": meta,
                "layout_id": layout, "chunk_shape": chunks, "filters": filters,
                "storage": storage, "values": values,
            }
        finally:
            if plist >= 0:
                h.H5Pclose(plist)
            if typ >= 0:
                h.H5Tclose(typ)
            if space >= 0:
                h.H5Sclose(space)
            h.H5Dclose(dset)


def verify_lock(path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    lock_info = file_info(path)
    lock = json.loads(path.read_text(encoding="utf-8-sig"))
    if lock.get("schema") != "frontdata007_source_lock_v1" or lock.get("matlab_allowed") or lock.get("vivado_allowed"):
        raise ValueError("source lock schema or MATLAB/Vivado freeze invalid")
    records, bad = [], []
    for expected in lock["files"]:
        actual = file_info(ROOT / expected["path"])
        record = {
            "path": expected["path"], "expected_bytes": expected["bytes"],
            "expected_sha256": expected["sha256"].upper(),
            "actual_bytes": actual["bytes"], "actual_sha256": actual["sha256"],
            "matches": actual["exists"] and actual["bytes"] == expected["bytes"] and actual["sha256"] == expected["sha256"].upper(),
        }
        records.append(record)
        if not record["matches"]:
            bad.append(record)
    if bad:
        raise RuntimeError(f"source lock mismatch count={len(bad)} first={bad[0]}")
    return lock, {"lock_file": lock_info, "file_count": len(records), "files": records, "all_match": True}


def csv_report(guard: Guard) -> dict[str, Any]:
    source = file_info(CSV_PATH)
    counts: dict[int, int] = {}
    orders: dict[int, tuple[list[int], list[int], list[int]]] = {}
    total = 0
    with CSV_PATH.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        header = ["payloadSymbolZeroBased", "activeRowZeroBased", "rtlBinZeroBased", "signedSubcarrierK",
                  "realValue", "imagValue", "quantizedI", "quantizedQ"]
        if reader.fieldnames != header:
            raise ValueError(f"CSV header mismatch: {reader.fieldnames}")
        for row in reader:
            total += 1
            symbol = int(row["payloadSymbolZeroBased"])
            counts[symbol] = counts.get(symbol, 0) + 1
            if symbol not in orders:
                orders[symbol] = ([], [], [])
            orders[symbol][0].append(int(row["signedSubcarrierK"]))
            orders[symbol][1].append(int(row["activeRowZeroBased"]))
            orders[symbol][2].append(int(row["rtlBinZeroBased"]))
            if total % 10000 == 0:
                guard.tick(f"CSV row {total}")
    symbols = sorted(counts)
    if len(symbols) != 74 or total != 60680 or set(counts.values()) != {820}:
        raise ValueError(f"CSV count mismatch rows={total}, symbols={len(symbols)}, counts={set(counts.values())}")
    ref = orders[symbols[0]]
    if any(orders[symbol] != ref for symbol in symbols):
        raise ValueError("CSV order differs among the 74 symbols")
    return {
        "source": source, "header": header, "row_count": total,
        "unique_payload_symbol_count": len(symbols), "payload_symbol_ids": symbols,
        "per_symbol_counts": {str(symbol): counts[symbol] for symbol in symbols},
        "actual_order": {
            "signedSubcarrierK": ref[0], "activeRowZeroBased": ref[1], "rtlBinZeroBased": ref[2],
            "signedSubcarrierK_order_sha256": sha256_bytes(json.dumps(ref[0], separators=(",", ":")).encode()),
        },
        "same_order_for_all_74_symbols": True,
    }


# FRONTDATA_CHUNK_3_END
def phase_z(path: Path) -> tuple[list[tuple[int, int]], list[int]]:
    obj = json.loads(path.read_text(encoding="utf-8-sig"))
    dataset = obj["mat_datasets"]["z_codes"]
    if dataset["shape"] != [1, 74] or len(dataset["values"]) != 74:
        raise ValueError(f"phase z shape/count invalid: {dataset['shape']}/{len(dataset['values'])}")
    values = [(strict_int(x["real"], "phase.z.real"), strict_int(x["imag"], "phase.z.imag")) for x in dataset["values"]]
    return values, dataset["shape"]


def context(result: dict[str, Any]) -> dict[str, Any]:
    paths = ["case_id", "group_id", "label", "profile", "scope", "seeds", "waveform", "injected",
             "coarse", "ideal_residual", "descriptor", "tx_file", "tx_sha256", "input_saturation",
             "formal_pass", "quality_screen_pass", "bittrue.valid", "bittrue.mode",
             "bittrue.coarse_parameters", "bittrue.front", "bittrue.estimate",
             "bittrue.final_rotation", "residual"]
    top = {}
    for key, value in result.items():
        low = key.lower()
        if any(word in low for word in ("frame", "condition", "snr", "channel", "seed", "descriptor", "waveform", "profile", "residual")):
            top[key] = value
    return {"selected_fields": {path: selected_field(result, path) for path in paths},
            "frame_condition_top_level_fields": top}


def raw_windows(src: Path, dst: Path, guard: Guard) -> dict[str, Any]:
    source = file_info(src)
    records = []
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    with src.open("rb") as inp, tmp.open("wb") as out:
        for index in range(74):
            guard.tick(f"raw_window_{dst.parent.name}_{index}")
            first = 25984 + index * 17920
            offset = first * 4
            inp.seek(offset)
            block = inp.read(2048 * 4)
            if len(block) != 8192:
                raise ValueError(f"raw window {index} short read: {len(block)}")
            out.write(block)
            records.append({
                "window_index": index, "global_first_sample": first,
                "global_last_sample": first + 2047, "source_byte_offset": offset,
                "bytes": len(block), "sha256": sha256_bytes(block),
            })
    os.replace(tmp, dst)
    output = file_info(dst)
    if output["bytes"] != 606208:
        raise ValueError(f"raw output length {output['bytes']}")
    return {
        "label": "uncorrected input_i16.bin; little-endian I16 then Q16; not FFT input and not corrected",
        "source": source, "output": output, "window_count": 74,
        "samples_per_window": 2048, "window_start0": 25984, "window_spacing": 17920,
        "bytes_per_complex": 4, "output_bytes": 606208, "segments": records,
    }


def ds_output(ds: dict[str, Any], pairs: list[tuple[int, int]], logical_shape: list[int]) -> dict[str, Any]:
    return {
        "path": ds["path"], "hdf5_shape": ds["shape"], "count": ds["count"],
        "datatype": ds["datatype"], "layout_id": ds["layout_id"],
        "chunk_shape": ds["chunk_shape"], "filters": ds["filters"], "storage": ds["storage"],
        "value_encoding": "nested HDF5 row-major I/Q pairs; component order real,imag",
        "flatten_order": "HDF5 C-order row-major", "logical_matlab_shape": logical_shape,
        "values": nested_pairs(pairs, ds["shape"]),
    }


def case_payload(api: H5, lock: dict[str, Any], case: dict[str, Any], phase: tuple[list[tuple[int, int]], list[int]],
                 csv_info: dict[str, Any], guard: Guard, decoder: dict[str, Any], raw_dir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    family, cid = case["family"], int(case["case_id"])
    mat = ROOT / case["mat"]
    result_path = ROOT / case["json"]
    phase_path = ROOT / case["verified_phase"]
    result_obj = json.loads(result_path.read_text(encoding="utf-8-sig"))
    phase_pairs, phase_shape = phase
    with api.open(mat) as hdf:
        fft = hdf.read(DATASETS["pilot_fft_codes"], guard, True, f"{family}_{cid}:fft")
        coeff = hdf.read(DATASETS["pilot_coeff_codes"], guard, True, f"{family}_{cid}:coeff")
        product = hdf.read(DATASETS["pilot_product_codes"], guard, True, f"{family}_{cid}:product")
        front_z = hdf.read(DATASETS["front_z_codes"], guard, False, f"{family}_{cid}:front_z")
        estimator_z = hdf.read(DATASETS["estimator_z_codes"], guard, False, f"{family}_{cid}:estimator_z")
    for ds, shape, label in ((fft, [74, 820], "fft"), (coeff, [74, 820], "coeff"), (product, [74, 820], "product"),
                             (front_z, [1, 74], "front_z"), (estimator_z, [1, 74], "estimator_z")):
        if ds["shape"] != shape or ds["count"] != math.prod(shape):
            raise ValueError(f"{family}_{cid}:{label} shape/count {ds['shape']}/{ds['count']}")
    fft_p = as_pairs(fft["values"], fft["datatype"], "fft")
    coeff_p = as_pairs(coeff["values"], coeff["datatype"], "coeff")
    product_p = as_pairs(product["values"], product["datatype"], "product")
    front_z_p = as_pairs(front_z["values"], front_z["datatype"], "front_z")
    estimator_z_p = as_pairs(estimator_z["values"], estimator_z["datatype"], "estimator_z")
    for i, (a, b) in enumerate(fft_p):
        checked_signed(a, 26, f"fft[{i}].real"); checked_signed(b, 26, f"fft[{i}].imag")
    for i, (a, b) in enumerate(coeff_p):
        checked_signed(a, 18, f"coeff[{i}].real"); checked_signed(b, 18, f"coeff[{i}].imag")
    for i, (a, b) in enumerate(product_p):
        checked_signed(a, 28, f"product[{i}].real"); checked_signed(b, 28, f"product[{i}].imag")
    for i, (a, b) in enumerate(front_z_p + estimator_z_p):
        if abs(a) >= 1 << 37 or abs(b) >= 1 << 37:
            raise ValueError(f"z[{i}] outside abs<2^37")
    mismatches = []
    for i, ((fr, fi), (cr, ci), actual) in enumerate(zip(fft_p, coeff_p, product_p)):
        expected = (clamp(rne_pow2(fr * cr - fi * ci, 17), 28),
                    clamp(rne_pow2(fr * ci + fi * cr, 17), 28))
        if expected != actual and len(mismatches) < 5:
            mismatches.append({"flat_index": i, "expected": list(expected), "actual": list(actual)})
    if mismatches:
        raise ValueError(f"H exact mismatch: {mismatches}")
    z_bad = []
    for window in range(74):
        lo, hi = window * 820, (window + 1) * 820
        summed = (sum(x[0] for x in product_p[lo:hi]), sum(x[1] for x in product_p[lo:hi]))
        for label, actual in (("front_z", front_z_p[window]), ("estimator_z", estimator_z_p[window]), ("phase", phase_pairs[window])):
            if summed != actual and len(z_bad) < 5:
                z_bad.append({"window": window, "source": label, "expected": list(summed), "actual": list(actual)})
    if z_bad:
        raise ValueError(f"window z mismatch: {z_bad}")
    raw = None
    if family == "rcfo004" and cid in {1, 3, 81}:
        raw_spec = next(item for item in lock["raw_window_sources"] if int(item["case_id"]) == cid)
        raw = raw_windows(ROOT / raw_spec["path"], raw_dir / f"rcfo004_case_{cid:03d}" / "raw_windows_i16.bin", guard)
        if raw["output"]["bytes"] != raw_spec["output_bytes"]:
            raise ValueError(f"raw length mismatch case {cid}")
    coeff_set = sorted(set(coeff_p))
    digest = pair_sha256(coeff_p)
    payload = {
        "schema": "cfo_frontdata007_case_v1", "status": "PASS", "generated_utc": utc(),
        "family": family, "case_id": cid,
        "source_inputs": {
            "mat": {**file_info(mat), "header": mat_header(mat)},
            "result_json": file_info(result_path), "verified_phase_case": file_info(phase_path),
        },
        "decoder": decoder, "source_result_json": result_obj, "selected_context": context(result_obj),
        "csv_index_evidence": {
            "source_sha256": csv_info["source"]["sha256"],
            "unique_payload_symbol_count": csv_info["unique_payload_symbol_count"],
            "items_per_symbol": 820,
            "actual_signedSubcarrierK_order": csv_info["actual_order"]["signedSubcarrierK"],
        },
        "hdf5_mapping": {
            "observed_front_shape": [74, 820], "logical_matlab_shape": [820, 74],
            "mapping": "HDF5 row r maps to MATLAB logical column r; row contents retain the 820-item pilot order.",
            "flatten_order": "HDF5 C-order row-major; window sums use each row's contiguous 820 items.",
            "mapping_verified_by": ["60680 exact H products", "74 front.z points", "74 estimator.z points", "74 phase points"],
        },
        "datasets": {
            "pilot_fft_codes": ds_output(fft, fft_p, [820, 74]),
            "pilot_coeff_codes": ds_output(coeff, coeff_p, [820, 74]),
            "pilot_product_codes": ds_output(product, product_p, [820, 74]),
            "front_z_codes": ds_output(front_z, front_z_p, [74]),
            "estimator_z_codes": ds_output(estimator_z, estimator_z_p, [74]),
        },
        "checks": {
            "required_dataset_count": DATASET_COUNT, "required_dataset_count_pass": True,
            "stored_values_strict_integer": True,
            "bit_ranges": {
                "pilot_fft_codes": {"format": "S26", "min": min(min(x) for x in fft_p), "max": max(max(x) for x in fft_p), "pass": True},
                "pilot_coeff_codes": {"format": "S18/F17", "min": min(min(x) for x in coeff_p), "max": max(max(x) for x in coeff_p), "pass": True},
                "pilot_product_codes": {"format": "S28/F21", "min": min(min(x) for x in product_p), "max": max(max(x) for x in product_p), "pass": True},
# FRONTDATA_CHUNK_4_END
                "z_codes": {"format": "absolute <2^37", "pass": True},
            },
            "H": {
                "formula": "RNE((Fr*cr-Fi*ci)/2^17), RNE((Fr*ci+Fi*cr)/2^17), clamp S28",
                "rounding": "nearest-even", "total_points": 60680, "exact_matches": 60680,
                "mismatch_count": 0, "pass": True,
            },
            "window_sums": {
                "window_count": 74, "items_per_window": 820,
                "front_z_exact_matches": 74, "estimator_z_exact_matches": 74,
                "phase74_exact_matches": 74, "mismatch_count": 0, "pass": True,
            },
            "coefficients": {"unique_pair_count": len(coeff_set), "exact_pairs": pair_list(coeff_set), "matrix_sha256": digest},
        },
        "raw_windows": raw,
    }
    return payload, {
        "family": family, "case_id": cid, "status": "PASS", "H_exact_matches": 60680,
        "window_exact_matches": 74, "coefficient_pair_count": len(coeff_set),
        "coefficient_matrix_sha256": digest, "raw_windows": raw["output"] if raw else None,
        "_coefficient_pairs": pair_list(coeff_set),
    }


def published_files(published: Path) -> list[dict[str, Any]]:
    out = []
    for path in sorted(published.rglob("*")):
        if path.is_file() and path.name not in {"FINAL_MANIFEST.json", "DATA_PREP_COMPLETION.json"}:
            out.append({"path": str(path), "relative_path": str(path.relative_to(published)),
                        "bytes": path.stat().st_size, "sha256": sha256_path(path)})
    return out


def make_manifest(status: str, attempt: Path, published: Path, lock_audit: Any, csv_info: Any,
                  summaries: list[dict[str, Any]], decoder: dict[str, Any], resource: Any,
                  failure: Any) -> dict[str, Any]:
    hashes = [x["coefficient_matrix_sha256"] for x in summaries if x.get("coefficient_matrix_sha256")]
    pairs = sorted({tuple(pair) for x in summaries for pair in x.get("_coefficient_pairs", [])})
    identical = bool(hashes) and len(hashes) == len(summaries) and len(set(hashes)) == 1
    return {
        "schema": "cfo_frontdata007_final_manifest_v1", "status": status, "generated_utc": utc(),
        "attempt_directory": str(attempt), "published_directory": str(published),
        "scope": "Read/verify published compressed frontend arrays and copy exact raw windows; no rotate/FFT execution or regenerated reference",
        "matlab_started": False, "vivado_started": False, "old_runner_started": False,
        "new_algorithm_or_signal_generated": False, "source_lock": lock_audit, "csv_index_evidence": csv_info,
        "selected_case_count": len(summaries), "expected_case_count": 19,
        "required_dataset_fields_per_case": DATASET_COUNT,
        "required_dataset_field_count": len(summaries) * DATASET_COUNT,
        "summaries": [{k: v for k, v in x.items() if not k.startswith("_")} for x in summaries],
        "coefficient_summary": {
            "matrix_hashes": hashes, "all_case_matrices_identical": identical,
            "unique_pair_count_if_available": len(pairs) if pairs else None,
            "three_bit_index_possible": bool(identical and len(pairs) == 8),
            "note": "3-bit indexing is reported only for identical matrices with exactly eight exact pairs.",
        },
        "decoder": decoder, "resource": resource, "published_data_files": published_files(published),
        "failure": failure,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--attempt", type=Path, required=True)
    parser.add_argument("--hard-timeout", type=float, default=300.0)
    args = parser.parse_args()
    attempt = args.attempt.resolve()
    work_root = (ROOT / "work" / "CFO_FRONTDATA007").resolve()
    try:
        attempt.relative_to(work_root)
    except ValueError:
        raise SystemExit(f"attempt outside approved work root: {attempt}")
    published, cases_dir, raw_dir = attempt / "published", attempt / "published" / "cases", attempt / "published" / "raw_windows"
    for directory in (published, cases_dir, raw_dir):
        directory.mkdir(parents=True, exist_ok=True)
    guard = Guard(args.hard_timeout)
    tool = Path(__file__).resolve()
    decoder: dict[str, Any] = {
        "tool_path": str(tool), "tool_sha256": sha256_path(tool),
        "python_executable": sys.executable, "python_version": sys.version,
        "command": subprocess.list2cmdline([sys.executable, *sys.argv]),
        "hdf5_library": file_info(HDF5_PATH), "hdf5_version": None,
        "method": "ctypes HDF5 C API; H5Dread_chunk + verified deflate/zlib; H5Dread for z_codes",
        "matlab_started": False, "vivado_started": False, "global_package_install": False,
        "recomputed_fields": False,
    }
    lock = None
    lock_audit = None
    csv_info = None
    summaries: list[dict[str, Any]] = []
    failure = None
    status = "INCOMPLETE"
    api = None
    try:
        guard.tick("startup")
        lock, lock_audit = verify_lock(LOCK_PATH)
        decoder["source_lock_sha256"] = lock_audit["lock_file"]["sha256"]
        decoder["protected_processes_at_start"] = process_inventory()
        csv_info = csv_report(guard)
        decoder["freeze_utc"] = utc()
        decoder["resource_at_freeze"] = guard.snapshot("freeze")
        decoder["protected_processes_after_freeze"] = process_inventory()
        write_json(attempt / "EXECUTION_FREEZE.json", {
            "schema": "cfo_frontdata007_execution_freeze_v1", "freeze_utc": decoder["freeze_utc"],
            "attempt_directory": str(attempt), "command": decoder["command"],
            "tool": {"path": decoder["tool_path"], "sha256": decoder["tool_sha256"]},
            "source_lock": lock_audit, "csv": csv_info["source"], "hdf5_library": decoder["hdf5_library"],
            "hdf5_version_expected": "1.12.0",
            "protected_processes": decoder["protected_processes_after_freeze"],
            "resource": decoder["resource_at_freeze"], "hard_timeout_seconds": args.hard_timeout,
            "matlab_allowed": False, "vivado_allowed": False,
            "output_policy": "new independent attempt; no existing output overwrite",
        }, indent=2)
        api = H5(HDF5_PATH)
        decoder["hdf5_version"] = api.version
        if api.version != {"major": 1, "minor": 12, "release": 0}:
            raise RuntimeError(f"unexpected HDF5 version {api.version}")
        phase_cache = {case["verified_phase"]: phase_z(ROOT / case["verified_phase"]) for case in lock["cases"]}
        for index, case in enumerate(lock["cases"], 1):
            guard.tick(f"before_case_{index}")
            payload, summary = case_payload(
                api, lock, case, phase_cache[case["verified_phase"]], csv_info,
                guard, decoder, raw_dir,
            )
            target = cases_dir / f"{case['family']}_case_{int(case['case_id']):03d}.json"
            if target.exists():
                raise FileExistsError(f"refusing to overwrite {target}")
            write_json(target, payload)
            summaries.append(summary)
            write_json(attempt / "RUN_PROGRESS.json", {
                "schema": "cfo_frontdata007_progress_v1", "updated_utc": utc(), "status": "RUNNING",
                "completed_case_count": len(summaries), "expected_case_count": len(lock["cases"]),
                "last_case": {k: v for k, v in summary.items() if not k.startswith("_")},
                "resource": guard.snapshot(f"after_case_{index}"),
            }, indent=2)
            del payload
            gc.collect()
        status = "COMPLETE"
    except Exception as exc:
        failure = {"type": type(exc).__name__, "message": str(exc),
                   "traceback": traceback.format_exc(limit=20)}
    finally:
        if api is not None:
            try:
                api.dll.H5close()
            except Exception:
                pass
        decoder["resource"] = guard.report()
        decoder["protected_processes_at_end"] = process_inventory()
        try:
            manifest = make_manifest(status, attempt, published, lock_audit, csv_info, summaries,
                                     decoder, decoder["resource"], failure)
            manifest_sha = write_json(published / "FINAL_MANIFEST.json", manifest, indent=2)
            completion = {
                "schema": "cfo_frontdata007_completion_v1", "status": status, "completed_utc": utc(),
                "attempt_directory": str(attempt), "selected_case_count": len(summaries),
                "expected_case_count": 19, "matlab_started": False, "vivado_started": False,
                "final_manifest": {"path": str(published / "FINAL_MANIFEST.json"),
                                   "bytes": (published / "FINAL_MANIFEST.json").stat().st_size,
                                   "sha256": manifest_sha},
                "resource": decoder["resource"], "failure": failure,
            }
            completion_sha = write_json(attempt / "DATA_PREP_COMPLETION.json", completion, indent=2)
            print(json.dumps({
                "schema": "cfo_frontdata007_completion_v1", "status": status,
                "attempt": str(attempt), "case_count": len(summaries),
                "manifest": str(published / "FINAL_MANIFEST.json"),
                "manifest_sha256": manifest_sha, "completion_sha256": completion_sha,
                "failure_type": failure["type"] if failure else None,
            }, ensure_ascii=False))
        except Exception as final_exc:
# FRONTDATA_CHUNK_5_END
            print(json.dumps({"schema": "cfo_frontdata007_completion_v1", "status": "FINALIZATION_FAILED",
                              "attempt": str(attempt), "case_count": len(summaries),
                              "error": repr(final_exc), "original_failure": failure}, ensure_ascii=False))
            status = "INCOMPLETE"
    return 0 if status == "COMPLETE" else 1


if __name__ == "__main__":
    raise SystemExit(main())

# FRONTDATA_CHUNK_6_END
