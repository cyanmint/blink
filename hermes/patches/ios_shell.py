"""Run agent shell commands through Blink's ios_system command registry."""
from __future__ import annotations

import ctypes
import io
import os
import shlex
import subprocess
import threading

from typing import Optional


_bridge = None
_bridge_lock = threading.Lock()


def _load_bridge():
    global _bridge
    if _bridge is None:
        library = ctypes.CDLL(None)
        function = library.HermesLinkRunCommand
        function.argtypes = [ctypes.c_char_p]
        function.restype = ctypes.c_int
        _bridge = function
    return _bridge


def _run(command: str, cwd: Optional[str]) -> int:
    if cwd:
        command = f"cd {shlex.quote(cwd)} && {command}"
    read_fd, write_fd = os.pipe()
    saved_stdout = os.dup(1)
    saved_stderr = os.dup(2)
    try:
        os.dup2(write_fd, 1)
        os.dup2(write_fd, 2)
        return int(_load_bridge()(command.encode("utf-8")))
    finally:
        os.dup2(saved_stdout, 1)
        os.dup2(saved_stderr, 2)
        os.close(saved_stdout)
        os.close(saved_stderr)
        os.close(write_fd)
        os.close(read_fd)


class IOSProcess:
    """Small Popen-compatible handle for the local terminal backend."""

    def __init__(self, command: str, *, cwd=None, stdin_data=None):
        self.args = command
        self.pid = os.getpid()
        self.returncode = None
        read_fd, self._write_fd = os.pipe()
        self.stdout = io.TextIOWrapper(os.fdopen(read_fd, "rb", buffering=0), encoding="utf-8", errors="replace")
        self.stdin = None
        self._done = threading.Event()
        self._command = command
        self._cwd = cwd
        self._thread = threading.Thread(target=self._run_thread, daemon=True)
        self._thread.start()
        if stdin_data is not None:
            self.stdin = _ClosedInput()

    def _run_thread(self):
        try:
            self.returncode = _run_to_fd(self._command, self._cwd, self._write_fd)
        except Exception as exc:
            os.write(self._write_fd, f"hermes iOS shell bridge: {exc}\n".encode())
            self.returncode = 127
        finally:
            os.close(self._write_fd)
            self._done.set()

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        if not self._done.wait(timeout):
            raise subprocess.TimeoutExpired(self.args, timeout)
        return self.returncode

    def communicate(self, input=None, timeout=None):
        self.wait(timeout)
        output = self.stdout.read()
        return output, None

    def kill(self):
        # ios_system has no portable per-command cancellation API.
        return None

    terminate = kill


class _ClosedInput:
    def write(self, data):
        return len(data)

    def close(self):
        return None


def _run_to_fd(command: str, cwd: Optional[str], output_fd: int) -> int:
    if cwd:
        command = f"cd {shlex.quote(cwd)} && {command}"
    saved_stdout = os.dup(1)
    saved_stderr = os.dup(2)
    try:
        with _bridge_lock:
            os.dup2(output_fd, 1)
            os.dup2(output_fd, 2)
            return int(_load_bridge()(command.encode("utf-8")))
    finally:
        with _bridge_lock:
            os.dup2(saved_stdout, 1)
            os.dup2(saved_stderr, 2)
        os.close(saved_stdout)
        os.close(saved_stderr)