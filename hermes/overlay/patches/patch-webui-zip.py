# HermesLink AI-generated glue code; created by cyanmint's coding agent.
# AI-generated content has no copyright holder and is not subject to copyright.
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "import zipfile\n" not in text:
    text = text.replace("import sys\n", "import sys\nimport zipfile\n", 1)
host_anchor = 'HOST = os.getenv("HERMES_WEBUI_HOST", "127.0.0.1")\nPORT = int(os.getenv("HERMES_WEBUI_PORT", "8787"))\n'
host_replacement = '''def _cli_override(name: str, default: str) -> str:
    try:
        index = sys.argv.index(name)
        return sys.argv[index + 1]
    except (ValueError, IndexError):
        return default


HOST = _cli_override("--host", os.getenv("HERMES_WEBUI_HOST", "127.0.0.1"))
PORT = int(_cli_override("--port", os.getenv("HERMES_WEBUI_PORT", "8787")))
'''
if host_anchor in text:
    text = text.replace(host_anchor, host_replacement, 1)
if "_BUNDLED_STATIC_ROOT" not in text:
    old = '''def get_static_root() -> Path:
    return REPO_ROOT / "static"
'''
    new = '''_BUNDLED_STATIC_ROOT: Path | None = None


def get_static_root() -> Path:
    """Return a filesystem root for static assets, including ZIP bundles."""
    global _BUNDLED_STATIC_ROOT
    direct = REPO_ROOT / "static"
    if direct.is_dir():
        return direct
    if _BUNDLED_STATIC_ROOT is not None:
        return _BUNDLED_STATIC_ROOT
    origins = [str(Path(__file__).resolve()), *(str(entry) for entry in sys.path)]
    marker = ".zip/"
    origin = next((entry for entry in origins if marker in entry or entry.endswith(".zip")), "")
    if not origin:
        return direct
    if marker in origin:
        archive_name, inside = origin.split(marker, 1)
        archive = Path(archive_name + ".zip")
    else:
        archive = Path(origin)
        inside = "hermes-webui/api/config.py"
    if not archive.is_file():
        return direct
    prefix = inside.split("api/", 1)[0] + "static/"
    target = Path(os.getenv("HERMES_HOME", str(archive.parent))) / "webui"
    import zipfile
    try:
        with zipfile.ZipFile(archive) as bundle:
            for name in bundle.namelist():
                if not name.startswith(prefix) or name.endswith("/"):
                    continue
                destination = target / name[len(prefix):]
                destination.parent.mkdir(parents=True, exist_ok=True)
                if not destination.exists() or destination.stat().st_size != bundle.getinfo(name).file_size:
                    destination.write_bytes(bundle.read(name))
    except (OSError, KeyError, zipfile.BadZipFile):
        return direct
    if (target / "index.html").is_file():
        _BUNDLED_STATIC_ROOT = target
        return target
    return direct
'''
    if old not in text:
        raise SystemExit("get_static_root patch anchor not found")
    text = text.replace(old, new, 1)

# Inject at the start of the discovery function, before filesystem candidates.
anchor = 'def _discover_agent_dir() -> Path:\n'
injection = '''def _discover_agent_dir() -> Path:
    # The bundled agent lives in the outer hermesrt.zip.  Keep it in the ZIP;
    # the native launcher already exposes the archive's hermes/ root on
    # sys.path.  Returning the archive lets the existing WebUI import path and
    # diagnostics recognize the bundled source without duplicating it on disk.
    _origins = [str(getattr(sys.modules.get(__name__), "__file__", "")),
                *(str(_entry) for _entry in sys.path)]
    _zip_marker = ".zip/"
    _origin = next((entry for entry in _origins
                    if _zip_marker in entry or entry.endswith(".zip")), "")
    if _origin:
        _archive = (Path(_origin.split(_zip_marker, 1)[0] + ".zip")
                    if _zip_marker in _origin else Path(_origin))
        _prefix = "hermes/"
        try:
            with zipfile.ZipFile(_archive) as _bundle:
                _names = set(_bundle.namelist())
            if "hermes/run_agent.py" in _names or "hermes/cron/jobs.py" in _names:
                return _archive.resolve()
        except (OSError, KeyError, zipfile.BadZipFile):
            pass
'''
if 'The bundled agent lives in the outer hermesrt.zip.' not in text:
    if anchor not in text:
        raise SystemExit("agent discovery anchor not found")
    text = text.replace(anchor, injection, 1)

path.write_text(text, encoding="utf-8", newline="\n")
