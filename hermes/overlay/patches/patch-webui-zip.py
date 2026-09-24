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
if "_runtime_zip_archives" not in text:
    old = '''def get_static_root() -> Path:
    return REPO_ROOT / "static"
'''
    new = '''_BUNDLED_STATIC_ROOT: Path | None = None


def _runtime_zip_archives():
    """Yield usable runtime archives without resolving zipimport pseudo-paths."""
    origins = [str(getattr(sys.modules.get(__name__), "__file__", "")),
               *(str(entry) for entry in sys.path)]
    seen = set()
    for origin in origins:
        normalized = origin.replace("\\\\", "/")
        if ".zip/" in normalized:
            archive = Path(normalized.split(".zip/", 1)[0] + ".zip")
        elif normalized.endswith(".zip"):
            archive = Path(normalized)
        else:
            continue
        key = str(archive)
        if key in seen or not archive.is_file():
            continue
        seen.add(key)
        yield archive


def get_static_root() -> Path:
    """Return a filesystem root for static assets, including ZIP bundles."""
    global _BUNDLED_STATIC_ROOT
    direct = REPO_ROOT / "static"
    if direct.is_dir():
        return direct
    if _BUNDLED_STATIC_ROOT is not None:
        return _BUNDLED_STATIC_ROOT
    target = Path(os.getenv("HERMES_HOME", str(_DEFAULT_HERMES_HOME))).expanduser() / "webui"
    target_root = target.resolve()
    prefix = "hermes-webui/static/"
    for archive in _runtime_zip_archives():
        try:
            with zipfile.ZipFile(archive) as bundle:
                for name in bundle.namelist():
                    if not name.startswith(prefix) or name.endswith("/"):
                        continue
                    relative_parts = name[len(prefix):].replace("\\\\", "/").split("/")
                    if (not relative_parts
                            or any(part in ("", ".", "..") or ":" in part
                                   for part in relative_parts)):
                        continue
                    destination = target_root.joinpath(*relative_parts)
                    try:
                        destination = destination.resolve()
                        destination.relative_to(target_root)
                    except (OSError, ValueError):
                        continue
                    contents = bundle.read(name)
                    if destination.is_file() and destination.read_bytes() == contents:
                        continue
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(contents)
            if (target / "index.html").is_file():
                _BUNDLED_STATIC_ROOT = target
                return target
        except (OSError, KeyError, zipfile.BadZipFile):
            continue
    return direct
'''
    if old in text:
        text = text.replace(old, new, 1)
    else:
        previous_start = text.find("_BUNDLED_STATIC_ROOT: Path | None = None")
        if previous_start < 0:
            raise SystemExit("get_static_root patch anchor not found")
        next_function = text.find("\ndef ", previous_start)
        if next_function < 0:
            raise SystemExit("end of existing get_static_root patch not found")
        text = text[:previous_start] + new + text[next_function + 1:]

# Inject at the start of the discovery function, before filesystem candidates.
anchor = 'def _discover_agent_dir() -> Path:\n'
injection = '''def _discover_agent_dir() -> Path:
    # WebUI discovery requires a real source directory, not the runtime ZIP.
    _explicit = os.getenv("HERMES_WEBUI_AGENT_DIR")
    if _explicit:
        _explicit_path = Path(_explicit).expanduser().resolve()
        if _explicit_path.exists() and _looks_like_agent_source_root(_explicit_path):
            return _explicit_path
    _target = Path(os.getenv("HERMES_HOME", str(_DEFAULT_HERMES_HOME))).expanduser() / "hermes-agent"
    _target_root = _target.resolve()
    for _archive in _runtime_zip_archives():
        _prefix = "hermes/"
        try:
            with zipfile.ZipFile(_archive) as _bundle:
                _names = [name for name in _bundle.namelist()
                          if name.startswith(_prefix) and not name.endswith("/")]
                if ("hermes/run_agent.py" not in _names
                        or "hermes/hermes_cli/main.py" not in _names):
                    raise KeyError("bundled Hermes Agent entrypoint is missing")
                for _name in _names:
                    _relative_parts = _name[len(_prefix):].replace("\\\\", "/").split("/")
                    if (not _relative_parts
                            or any(_part in ("", ".", "..") or ":" in _part
                                   for _part in _relative_parts)):
                        continue
                    _destination = _target_root.joinpath(*_relative_parts)
                    try:
                        _destination = _destination.resolve()
                        _destination.relative_to(_target_root)
                    except (OSError, ValueError):
                        continue
                    _destination.parent.mkdir(parents=True, exist_ok=True)
                    with _bundle.open(_name) as _source, _destination.open("wb") as _sink:
                        _sink.write(_source.read())
            _entrypoints = (
                _target_root / "run_agent.py",
                _target_root / "hermes_cli" / "main.py",
            )
            if all(
                    _entrypoint.is_file()
                    and _entrypoint.resolve().is_relative_to(_target_root)
                    for _entrypoint in _entrypoints):
                return _target_root
        except (OSError, KeyError, zipfile.BadZipFile):
            continue
'''
if '    _explicit = os.getenv("HERMES_WEBUI_AGENT_DIR")' not in text:
    function_start = text.find(anchor)
    if function_start < 0:
        raise SystemExit("agent discovery anchor not found")
    body_start = function_start + len(anchor)
    docstring_start = text.find('    """', body_start)
    if docstring_start > body_start:
        text = text[:function_start] + injection + text[docstring_start:]
    else:
        text = text.replace(anchor, injection, 1)

path.write_text(text, encoding="utf-8", newline="\n")
