#!/usr/bin/env python3
"""Apply iOS-only runtime safety patches to the packaged agent."""
from __future__ import annotations

import sys
import re
from pathlib import Path


def patch_usage_pricing(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    anchor = '''    bundled_entry = _lookup_official_docs_pricing(route)\n    if bundled_entry:\n        return bundled_entry\n    if route.base_url:\n'''
    replacement = '''    bundled_entry = _lookup_official_docs_pricing(route)\n    if bundled_entry:\n        return bundled_entry\n    # iOS static builds must not perform the optional pricing metadata probe.\n    # That background requests/SSLContext path can abort the process in the\n    # statically linked OpenSSL runtime after an otherwise successful turn.\n    return None\n    if route.base_url:\n'''
    if "iOS static builds must not perform the optional pricing metadata probe." in text:
        return
    if anchor not in text:
        raise SystemExit(f"usage pricing patch anchor not found: {path}")
    path.write_text(text.replace(anchor, replacement, 1), encoding="utf-8", newline="\n")


def patch_process_title(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    anchor = "    import ctypes\n    import platform\n"
    replacement = "    try:\n        import ctypes\n    except ImportError:\n        return\n    import platform\n"
    if "except ImportError:\n        return\n    import platform" in text:
        return
    if anchor not in text:
        raise SystemExit(f"process title patch anchor not found: {path}")
    path.write_text(text.replace(anchor, replacement, 1), encoding="utf-8", newline="\n")


def patch_ios_terminal(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    old = "    if not sys.stdin.isatty():\n"
    new = "    if not sys.stdin.isatty() and os.environ.get(\"HERMES_IOS_TERMINAL\") != \"1\":\n"
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"interactive terminal guard not found: {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def patch_ios_shell(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    marker = re.compile(
        r"(?P<head>    def _run_bash\(self, cmd_string: str, \*, login: bool = False, timeout: int = 120,\n"
        r"                  stdin_data: str \| None = None\) -> subprocess\.Popen:\n)"
        r"        bash = _find_bash\(\)\n"
    )
    replacement = (
        "\\g<head>"
        "        if os.environ.get(\"HERMES_IOS_TERMINAL\") == \"1\":\n"
        "            from hermes.ios_shell import IOSProcess\n"
        "            return IOSProcess(cmd_string, cwd=self.cwd, stdin_data=stdin_data)\n"
        "        bash = _find_bash()\n"
    )
    if "from hermes.ios_shell import IOSProcess" in text:
        return
    if not marker.search(text):
        raise SystemExit(f"local shell runner anchor not found: {path}")
    path.write_text(marker.sub(replacement, text, count=1), encoding="utf-8", newline="\n")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-ios-stability.py <staging-hermes-root>")
    root = Path(sys.argv[1])
    patch_usage_pricing(root / "agent" / "usage_pricing.py")
    patch_process_title(root / "hermes_cli" / "main.py")
    patch_ios_terminal(root / "hermes_cli" / "main.py")
    patch_ios_shell(root / "tools" / "environments" / "local.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
