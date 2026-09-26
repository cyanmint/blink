#!/usr/bin/env python3
"""Generate CPython's built-in module registry from compiled initializer symbols."""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


INITIALIZER_RE = re.compile(r"^_?PyInit_([A-Za-z_][A-Za-z0-9_]*)$")


def parse_defined_initializers(nm_output: str) -> list[str]:
    """Return module names for defined PyInit symbols in `nm -gU` output."""
    modules = set()
    for line in nm_output.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        symbol = fields[-1]
        if fields[-2].upper() == "U":
            continue
        match = INITIALIZER_RE.fullmatch(symbol)
        if match:
            modules.add(match.group(1))
    return sorted(modules)


def render_registry(modules: list[str]) -> str:
    """Render a C registry with declarations only for compiled module initializers."""
    lines = ["#include <Python.h>"]
    lines.extend(f"PyMODINIT_FUNC PyInit_{name}(void);" for name in modules)
    lines.extend(["", "int hermes_register_native_modules(void) {"])
    lines.extend(f'    PyImport_AppendInittab("{name}", PyInit_{name});' for name in modules)
    lines.extend(["    return 0;", "}", ""])
    return "\n".join(lines)


def discover_modules(objects: list[Path], nm: str = "nm") -> list[str]:
    """Inspect compiled objects and return their defined CPython module initializers."""
    modules = set()
    for obj in objects:
        result = subprocess.run(
            [nm, "-gU", str(obj)], check=True, capture_output=True, text=True
        )
        modules.update(parse_defined_initializers(result.stdout))
    return sorted(modules)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("object_list", type=Path)
    parser.add_argument("object_root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--nm", default="nm")
    args = parser.parse_args()
    objects = [
        args.object_root / line.strip()
        for line in args.object_list.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    missing = [str(obj) for obj in objects if not obj.is_file()]
    if missing:
        raise SystemExit("missing native module object(s): " + ", ".join(missing))
    modules = discover_modules(objects, nm=args.nm)
    if not modules:
        raise SystemExit("no CPython module initializers found in compiled objects")
    args.output.write_text(render_registry(modules), encoding="utf-8", newline="\n")
    print(f"Generated native module registry for {len(modules)} compiled module(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
