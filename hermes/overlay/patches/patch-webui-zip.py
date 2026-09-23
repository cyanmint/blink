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
    origin = str(Path(__file__).resolve())
    marker = ".zip/"
    if marker not in origin:
        return direct
    archive_name, inside = origin.split(marker, 1)
    archive = Path(archive_name + ".zip")
    if not archive.is_file():
        return direct
    prefix = inside.split("api/", 1)[0] + "static/"
    target = Path(os.getenv("HERMES_HOME", str(archive.parent))) / ".hermes-webui-static"
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

agent_marker = "# iOS ZIP runtime: the agent is importable from the outer archive.\n"
agent_block = '''# iOS ZIP runtime: the agent is importable from the outer archive.
if "_discover_agent_dir" in text:
    pass
'''
# Inject at the start of the discovery function, before filesystem candidates.
anchor = 'def _discover_agent_dir() -> Path:\n'
injection = '''def _discover_agent_dir() -> Path:
    # The bundled Agent lives inside hermesrt.zip.  Extract it to the writable
    # HERMES_HOME so filesystem-based config/discovery code can use it on iOS.
    _origin = str(Path(__file__).resolve())
    if ".zip/" in _origin:
        _archive = Path(_origin.split(".zip/", 1)[0] + ".zip")
        _target = Path(os.getenv("HERMES_HOME", str(Path.home()))) / ".hermes-agent"
        try:
            with zipfile.ZipFile(_archive) as _bundle:
                _prefix = "hermes/"
                for _name in _bundle.namelist():
                    if not _name.startswith(_prefix) or _name.endswith("/"):
                        continue
                    _destination = _target / _name[len(_prefix):]
                    _destination.parent.mkdir(parents=True, exist_ok=True)
                    _data = _bundle.read(_name)
                    if not _destination.exists() or _destination.read_bytes() != _data:
                        _destination.write_bytes(_data)
            return _target
        except (OSError, KeyError, zipfile.BadZipFile):
            pass
'''
if 'The bundled Agent lives at hermesrt.zip/hermes.' not in text:
    if anchor not in text:
        raise SystemExit("agent discovery anchor not found")
    text = text.replace(anchor, injection, 1)

path.write_text(text, encoding="utf-8", newline="\n")
