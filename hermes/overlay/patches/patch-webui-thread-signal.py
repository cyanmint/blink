from __future__ import annotations

import sys
from pathlib import Path


path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "# HERMESLINK_THREAD_SAFE_SIGPIPE"
if marker not in text:
    original = '''def _ignore_sigpipe() -> None:
    """Keep broken client writes from terminating the server process."""
    if (sigpipe := getattr(signal, "SIGPIPE", None)) is not None:
        signal.signal(sigpipe, signal.SIG_IGN)
'''
    replacement = '''def _ignore_sigpipe() -> None:
    """Keep broken client writes from terminating the server process."""
    # HERMESLINK_THREAD_SAFE_SIGPIPE: ios_system runs app commands on workers.
    if threading.current_thread() is not threading.main_thread():
        return
    if (sigpipe := getattr(signal, "SIGPIPE", None)) is not None:
        try:
            signal.signal(sigpipe, signal.SIG_IGN)
        except (ValueError, OSError):
            return
'''
    if "import threading\n" not in text:
        raise SystemExit("threading import anchor not found in WebUI server")
    if original not in text:
        raise SystemExit("SIGPIPE handler anchor not found in WebUI server")
    text = text.replace(original, replacement, 1)

path.write_text(text, encoding="utf-8", newline="\n")
