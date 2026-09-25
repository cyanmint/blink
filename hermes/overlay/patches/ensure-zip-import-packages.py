#!/usr/bin/env python3
"""Make Hermes plugin namespace parents importable from a ZIP runtime."""
from __future__ import annotations

import sys
from pathlib import Path


def ensure_zip_importable_packages(hermes_root: Path) -> None:
    """Materialize implicit namespace parents that zipimport cannot resolve."""
    for relative in (Path("plugins"), Path("plugins") / "browser"):
        directory = hermes_root / relative
        marker = directory / "__init__.py"
        if directory.is_dir() and not marker.exists():
            marker.write_text("", encoding="utf-8", newline="\n")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} HERMES_PACKAGE_ROOT", file=sys.stderr)
        return 2
    ensure_zip_importable_packages(Path(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
