"""Initialize the pure-Python runtime for the static iOS build."""
from __future__ import annotations

import re
import socket
import sys
import time
import urllib.error
import urllib.request
import zipfile
import os


def _install_zip_metadata_fallbacks() -> None:
    """Make importlib.metadata find dist-info nested under the runtime ZIP."""
    try:
        from importlib import metadata
    except Exception:
        return
    original_version = metadata.version
    versions = {}
    for entry in sys.path:
        archive = entry.split(".zip", 1)[0] + ".zip" if ".zip/" in entry else None
        if not archive:
            continue
        try:
            with zipfile.ZipFile(archive) as bundle:
                for name in bundle.namelist():
                    if not name.endswith(".dist-info/METADATA"):
                        continue
                    text = bundle.read(name).decode("utf-8", "replace")
                    match = re.search(r"^Name: (.+)$", text, re.MULTILINE)
                    version = re.search(r"^Version: (.+)$", text, re.MULTILINE)
                    if match and version:
                        key = re.sub(r"[-_.]+", "-", match.group(1).strip().lower())
                        versions[key] = version.group(1).strip()
        except (OSError, zipfile.BadZipFile):
            continue

    def version(name):
        try:
            return original_version(name)
        except metadata.PackageNotFoundError:
            key = re.sub(r"[-_.]+", "-", name.strip().lower())
            if key in versions:
                return versions[key]
            raise

    metadata.version = version


def _install_hash_fallbacks() -> None:
    """Keep cache fingerprints working when optional BLAKE2 is unavailable."""
    try:
        import hashlib
    except Exception:
        return
    if hasattr(hashlib, "blake2b") and hasattr(hashlib, "blake2s"):
        return

    class _FallbackHash:
        def __init__(self, data=b"", digest_size=32):
            self._hash = hashlib.sha256(data)
            self._digest_size = digest_size

        def update(self, data):
            self._hash.update(data)

        def digest(self):
            return self._hash.copy().digest()[:self._digest_size]

        def hexdigest(self):
            return self.digest().hex()

        def copy(self):
            result = type(self)(digest_size=self._digest_size)
            result._hash = self._hash.copy()
            return result

    hashlib.blake2b = lambda data=b"", digest_size=64, **_: _FallbackHash(data, digest_size)
    hashlib.blake2s = lambda data=b"", digest_size=32, **_: _FallbackHash(data, digest_size)


def _install_urlopen_fallbacks() -> None:
    """Retry transient iOS URL-open timeouts for every HTTP consumer.

    Several independent CLI features use urllib directly. Keeping this at the
    common boundary avoids provider-specific login patches and prevents a
    transient DNS/connect timeout from aborting an otherwise recoverable flow.
    """
    original_urlopen = urllib.request.urlopen
    if getattr(original_urlopen, "_hermes_ios_retry", False):
        return

    def urlopen_with_retries(url, data=None, timeout=socket._GLOBAL_DEFAULT_TIMEOUT, *args, **kwargs):
        effective_timeout = 60 if timeout is socket._GLOBAL_DEFAULT_TIMEOUT else max(float(timeout), 60.0)
        last_error = None
        for attempt in range(3):
            try:
                return original_urlopen(url, data=data, timeout=effective_timeout,
                                        *args, **kwargs)
            except (TimeoutError, socket.timeout, urllib.error.URLError) as exc:
                reason = getattr(exc, "reason", None)
                if not isinstance(exc, (TimeoutError, socket.timeout)) and not isinstance(reason, (TimeoutError, socket.timeout)):
                    raise
                last_error = exc
                if attempt < 2:
                    time.sleep(0.5 * (attempt + 1))
        raise last_error

    urlopen_with_retries._hermes_ios_retry = True
    urllib.request.urlopen = urlopen_with_retries


def _install_ios_system_bridge() -> None:
    """Route Python's shell entry point through Blink's ios_system registry."""
    if os.environ.get("HERMES_IOS_TERMINAL") != "1":
        return
    try:
        from hermes.ios_shell import _load_bridge
    except Exception:
        return
    if getattr(os.system, "_hermes_ios_bridge", False):
        return
    native_system = _load_bridge()

    def ios_system(command):
        if not isinstance(command, str):
            raise TypeError("system() argument must be str")
        return int(native_system(command.encode("utf-8")))

    ios_system._hermes_ios_bridge = True
    os.system = ios_system


_install_zip_metadata_fallbacks()
_install_hash_fallbacks()
_install_urlopen_fallbacks()
_install_ios_system_bridge()
