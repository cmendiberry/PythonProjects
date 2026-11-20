#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PythonPortableBuilder - build-time inspection helper.

Subcommands (all print/write JSON):
  probe                      Interpreter facts (version, architecture, paths).
  inventory --path DIR       Installed distributions in a --target directory or venv site-packages:
                             names, versions, top-level modules, wheel tags, licenses, native files, .pth files.
  pe-imports --root DIR      Imported DLLs of every .pyd/.dll/.exe below DIR, classified as
                             bundled / system / missing (external prerequisite).
  resolve --names a,b        importlib.util.find_spec() for each name in THIS interpreter, after
                             optional --launcher DIR environment setup (embedded distributions).

Compatible with Python 3.8+. Standard library only. Never imports project code
(resolve uses find_spec, which locates but does not execute top-level modules).
"""

import argparse
import json
import os
import re
import struct
import sys

MACHINE_NAMES = {0x14C: "win32", 0x8664: "amd64", 0xAA64: "arm64", 0x1C4: "arm"}


def emit(data, output):
    text = json.dumps(data, indent=2, sort_keys=False)
    if output:
        with open(output, "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text + "\n")


# --------------------------------------------------------------------------------------
def cmd_probe(args):
    import platform
    import sysconfig
    bits = struct.calcsize("P") * 8
    machine = platform.machine().lower()
    arch = {"amd64": "amd64", "x86_64": "amd64", "arm64": "arm64", "aarch64": "arm64"}.get(machine, machine)
    if bits == 32:
        arch = "win32"
    # On ARM64 Windows an x64 interpreter reports ARM64 machine; trust the pointer size + sysconfig platform.
    plat = sysconfig.get_platform()
    if plat == "win-amd64":
        arch = "amd64"
    elif plat == "win32":
        arch = "win32"
    elif plat == "win-arm64":
        arch = "arm64"
    data = {
        "version": "%d.%d.%d" % sys.version_info[:3],
        "versionInfo": list(sys.version_info[:5]),
        "majorMinor": "%d.%d" % sys.version_info[:2],
        "implementation": sys.implementation.name,
        "architecture": arch,
        "bits": bits,
        "platform": plat,
        "executable": sys.executable,
        "baseExecutable": getattr(sys, "_base_executable", sys.executable),
        "prefix": sys.prefix,
        "basePrefix": sys.base_prefix,
        "isVirtualEnv": sys.prefix != sys.base_prefix,
        "path": sys.path,
        "flags": {"noSite": sys.flags.no_site, "isolated": sys.flags.isolated,
                  "ignoreEnvironment": sys.flags.ignore_environment},
        "abiTag": "cp%d%d" % sys.version_info[:2],
        "hasVenv": _has_module("venv"),
        "hasEnsurepip": _has_module("ensurepip"),
        "hasTkinter": _has_module("tkinter") and _has_module("_tkinter"),
    }
    emit(data, args.output)
    return 0


def _has_module(name):
    import importlib.util
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


# --------------------------------------------------------------------------------------
def _read_metadata_file(path):
    from email.parser import HeaderParser
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return HeaderParser().parse(fh)


def _license_of(meta):
    lic = meta.get("License-Expression") or ""
    if not lic:
        raw = (meta.get("License") or "").strip()
        if raw and len(raw) < 120 and "\n" not in raw:
            lic = raw
        elif raw:
            lic = raw.splitlines()[0][:120] + " (truncated)"
    classifiers = [c.split("::")[-1].strip() for c in meta.get_all("Classifier") or [] if c.startswith("License")]
    if not lic and classifiers:
        lic = "; ".join(classifiers)
    return lic or "UNKNOWN"


def cmd_inventory(args):
    root = os.path.abspath(args.path)
    target_abi = args.abi  # e.g. cp310
    target_plat = args.platform  # e.g. win_amd64
    dists = []
    record_owned = set()
    for entry in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        if not entry.endswith(".dist-info"):
            continue
        info_dir = os.path.join(root, entry)
        meta_path = os.path.join(info_dir, "METADATA")
        if not os.path.isfile(meta_path):
            continue
        meta = _read_metadata_file(meta_path)
        name = meta.get("Name") or entry.split("-")[0]
        version = meta.get("Version") or "?"
        top_level = []
        tl = os.path.join(info_dir, "top_level.txt")
        files = []
        rec = os.path.join(info_dir, "RECORD")
        if os.path.isfile(rec):
            with open(rec, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    p = line.split(",")[0].strip()
                    if p:
                        files.append(p)
                        record_owned.add(p.replace("\\", "/").split("/")[0])
        if os.path.isfile(tl):
            with open(tl, "r", encoding="utf-8", errors="replace") as fh:
                top_level = [l.strip() for l in fh if l.strip()]
        if not top_level:
            tops = set()
            for p in files:
                parts = p.replace("\\", "/").split("/")
                first = parts[0]
                if first.endswith((".dist-info", ".data")) or first in ("..", "bin", "Scripts"):
                    continue
                if len(parts) == 1:
                    if first.endswith(".py"):
                        tops.add(first[:-3])
                    elif first.endswith(".pyd"):
                        tops.add(first.split(".")[0])
                else:
                    tops.add(first)
            top_level = sorted(tops)
        tags = []
        wheel = os.path.join(info_dir, "WHEEL")
        if os.path.isfile(wheel):
            wm = _read_metadata_file(wheel)
            tags = wm.get_all("Tag") or []
        native = [p for p in files if p.lower().endswith((".pyd", ".dll", ".exe"))
                  and not p.lower().replace("\\", "/").startswith(("bin/", "../"))]
        compatible, reason = _tags_compatible(tags, target_abi, target_plat)
        direct_url = os.path.isfile(os.path.join(info_dir, "direct_url.json"))
        requires = meta.get_all("Requires-Dist") or []
        dists.append({
            "name": name,
            "version": version,
            "topLevel": top_level,
            "importNames": [t for t in top_level if re.match(r"^[A-Za-z_]\w*$", t) and not t.startswith("_")],
            "wheelTags": tags,
            "binaryCompatible": compatible,
            "compatibilityNote": reason,
            "nativeFiles": native[:200],
            "hasNative": bool(native),
            "license": _license_of(meta),
            "installedFromDirectUrl": direct_url,
            "requires": requires,
        })
    pth = sorted(f for f in os.listdir(root) if f.endswith(".pth")) if os.path.isdir(root) else []
    pth_details = []
    for f in pth:
        try:
            with open(os.path.join(root, f), "r", encoding="utf-8", errors="replace") as fh:
                lines = [l.strip() for l in fh if l.strip() and not l.startswith("#")]
        except OSError:
            lines = []
        pth_details.append({"file": f, "executesCode": any(l.startswith(("import ", "import\t")) for l in lines),
                            "addsPaths": [l for l in lines if not l.startswith("import")][:20]})
    emit({"path": root, "distributions": dists, "pthFiles": pth_details}, args.output)
    return 0


def _tags_compatible(tags, abi, plat):
    if not tags or not abi:
        return True, "no wheel tags (sdist build or unknown)" if not tags else ""
    ok_abis = {abi, "abi3", "none"}
    py_major_minor = abi[2:]
    for tag in tags:
        parts = tag.split("-")
        if len(parts) != 3:
            continue
        interp, tabi, tplat = parts
        if tplat != "any" and plat and tplat != plat:
            continue
        if tabi not in ok_abis:
            continue
        if tabi == "abi3":
            m = re.match(r"cp(\d)(\d+)", interp)
            if m and int(m.group(2)) > int(py_major_minor[1:]):
                continue
        elif tabi == abi or tabi == "none":
            if interp.startswith("cp") and interp != abi and tabi != "none":
                continue
        return True, tag
    return False, "wheel tags %s do not match %s/%s" % (",".join(tags), abi, plat)


# --------------------------------------------------------------------------------------
def pe_info(path):
    """Returns (machine, subsystem, [imported dll names]) for a PE file, or raises ValueError."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:2] != b"MZ":
        raise ValueError("not a PE file")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("invalid PE signature")
    machine, nsections = struct.unpack_from("<HH", data, pe + 4)
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    subsystem = struct.unpack_from("<H", data, opt + 68)[0]
    dd = opt + (96 if magic == 0x10B else 112)
    imp_rva, imp_size = struct.unpack_from("<II", data, dd + 8)
    sections = []
    sec = opt + opt_size
    for i in range(nsections):
        vsize, va, rsize, rptr = struct.unpack_from("<IIII", data, sec + i * 40 + 8)
        sections.append((va, max(vsize, rsize), rptr))

    def rva2off(rva):
        for va, size, ptr in sections:
            if va <= rva < va + size:
                return rva - va + ptr
        return None

    names = []
    off = rva2off(imp_rva) if imp_rva else None
    while off is not None and off + 20 <= len(data):
        orig, _ts, _fw, name_rva, first = struct.unpack_from("<IIIII", data, off)
        if not (orig or name_rva or first):
            break
        noff = rva2off(name_rva)
        if noff is not None:
            end = data.index(b"\0", noff)
            names.append(data[noff:end].decode("ascii", "replace"))
        off += 20
    return MACHINE_NAMES.get(machine, hex(machine)), subsystem, names


def cmd_pe_imports(args):
    root = os.path.abspath(args.root)
    extra = [os.path.abspath(p) for p in (args.search or [])]
    system_dirs = [os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32")]
    bundled = {}
    files = []
    for dirpath, _dirs, filenames in os.walk(root):
        for f in filenames:
            low = f.lower()
            if low.endswith((".dll", ".pyd")):
                bundled.setdefault(low, os.path.join(dirpath, f))
            if low.endswith((".dll", ".pyd", ".exe")):
                files.append(os.path.join(dirpath, f))
    for d in extra:
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.lower().endswith(".dll"):
                    bundled.setdefault(f.lower(), os.path.join(d, f))
    results = []
    missing = {}
    system_used = set()
    machines = {}
    for path in files:
        relp = os.path.relpath(path, root).replace("\\", "/")
        try:
            machine, subsystem, imports = pe_info(path)
        except (ValueError, struct.error, OSError) as exc:
            results.append({"file": relp, "error": str(exc)})
            continue
        machines.setdefault(machine, []).append(relp)
        for dll in imports:
            low = dll.lower()
            if low in bundled:
                continue
            if low.startswith(("api-ms-win-", "ext-ms-")):
                system_used.add(low)
                continue
            if any(os.path.isfile(os.path.join(s, dll)) for s in system_dirs):
                system_used.add(low)
                continue
            missing.setdefault(dll, []).append(relp)
        results.append({"file": relp, "machine": machine, "subsystem": subsystem, "imports": imports})
    emit({
        "root": root,
        "files": len(results),
        "machines": {k: len(v) for k, v in machines.items()},
        "machineFiles": {k: v[:20] for k, v in machines.items()},
        "missing": [{"dll": k, "requiredBy": v[:10]} for k, v in sorted(missing.items())],
        "systemDlls": sorted(system_used),
        "details": results if args.details else [],
    }, args.output)
    return 0


# --------------------------------------------------------------------------------------
def cmd_resolve(args):
    import importlib.util
    if args.launcher:
        sys.path.insert(0, os.path.abspath(args.launcher))
        import ppb_launch  # noqa: generated launcher of the embedded distribution
        ppb_launch.setup_environment()
        sys.path.pop(0) if sys.path and sys.path[0] == os.path.abspath(args.launcher) else None
    for p in args.path or []:
        sys.path.insert(0, os.path.abspath(p))
    names = [n.strip() for n in (args.names or "").split(",") if n.strip()]
    result = {}
    for n in names:
        try:
            spec = importlib.util.find_spec(n)
            result[n] = {"found": spec is not None,
                         "origin": getattr(spec, "origin", None) if spec else None}
        except (ImportError, ValueError, AttributeError) as exc:
            result[n] = {"found": False, "error": "%s: %s" % (type(exc).__name__, exc)}
    emit({"python": "%d.%d.%d" % sys.version_info[:3], "sysPath": sys.path, "modules": result}, args.output)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="PythonPortableBuilder inspection helper")
    ap.add_argument("--output")
    sub = ap.add_subparsers(dest="command")
    sub.add_parser("probe")
    p = sub.add_parser("inventory")
    p.add_argument("--path", required=True)
    p.add_argument("--abi")
    p.add_argument("--platform")
    p = sub.add_parser("pe-imports")
    p.add_argument("--root", required=True)
    p.add_argument("--search", action="append")
    p.add_argument("--details", action="store_true")
    p = sub.add_parser("resolve")
    p.add_argument("--names", required=True)
    p.add_argument("--launcher")
    p.add_argument("--path", action="append")
    args = ap.parse_args(argv)
    handlers = {"probe": cmd_probe, "inventory": cmd_inventory, "pe-imports": cmd_pe_imports, "resolve": cmd_resolve}
    if args.command not in handlers:
        ap.print_help()
        return 2
    return handlers[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
