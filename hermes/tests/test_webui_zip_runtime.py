from __future__ import annotations

import importlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


PATCHER = Path(__file__).parents[1] / "overlay" / "patches" / "patch-webui-zip.py"


class WebUIZipRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.archive = self.root / "hermes.zip"
        stage = self.root / "stage" / "hermes-webui" / "api"
        stage.mkdir(parents=True)
        self.config_path = stage / "config.py"
        self.config_path.write_text(
            """import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.resolve()
_DEFAULT_HERMES_HOME = Path.home() / ".hermes"
HOST = os.getenv("HERMES_WEBUI_HOST", "127.0.0.1")
PORT = int(os.getenv("HERMES_WEBUI_PORT", "8787"))

def get_static_root() -> Path:
    return REPO_ROOT / "static"

def _discover_agent_dir() -> Path:
    return None

def _looks_like_agent_source_root(path: Path) -> bool:
    return (path / "run_agent.py").is_file()
""",
            encoding="utf-8",
            newline="\n",
        )
        subprocess.run(
            [sys.executable, str(PATCHER), str(self.config_path)],
            check=True,
            capture_output=True,
            text=True,
        )
        self._write_runtime_archive("<main>bundled UI</main>")
        self.import_path = f"{self.archive}/hermes-webui"
        sys.path.insert(0, self.import_path)
        self.addCleanup(self._remove_imported_modules)
        self.addCleanup(sys.path.remove, self.import_path)
        self.original_home = os.environ.get("HERMES_HOME")
        os.environ["HERMES_HOME"] = str(self.root / "home")
        self.addCleanup(self._restore_home)
        self.original_agent_dir = os.environ.pop("HERMES_WEBUI_AGENT_DIR", None)
        self.addCleanup(self._restore_agent_dir)
        self.config = importlib.import_module("api.config")

    def _remove_imported_modules(self) -> None:
        for name in list(sys.modules):
            if name == "api" or name.startswith("api."):
                sys.modules.pop(name, None)

    def _restore_home(self) -> None:
        if self.original_home is None:
            os.environ.pop("HERMES_HOME", None)
        else:
            os.environ["HERMES_HOME"] = self.original_home

    def _restore_agent_dir(self) -> None:
        if self.original_agent_dir is None:
            os.environ.pop("HERMES_WEBUI_AGENT_DIR", None)
        else:
            os.environ["HERMES_WEBUI_AGENT_DIR"] = self.original_agent_dir

    def _write_runtime_archive(self, static_html: str, extra_entries=()) -> None:
        with zipfile.ZipFile(self.archive, "w") as bundle:
            bundle.write(self.config_path, "hermes-webui/api/config.py")
            bundle.writestr("hermes-webui/api/__init__.py", "")
            bundle.writestr("hermes-webui/static/index.html", static_html)
            bundle.writestr("hermes/run_agent.py", "# agent entrypoint\n")
            bundle.writestr("hermes/hermes_cli/main.py", "# agent CLI entrypoint\n")
            for name, contents in extra_entries:
                bundle.writestr(name, contents)

    def test_discovers_agent_and_extracts_static_assets_from_runtime_zip(self) -> None:
        agent_dir = self.config._discover_agent_dir()
        static_root = self.config.get_static_root()

        self.assertEqual(agent_dir, (self.root / "home" / "hermes-agent").resolve())
        self.assertTrue((agent_dir / "run_agent.py").is_file())
        self.assertTrue((agent_dir / "hermes_cli" / "main.py").is_file())
        self.assertEqual(
            (static_root / "index.html").read_text(encoding="utf-8"),
            "<main>bundled UI</main>",
        )

    def test_skips_unusable_zip_origin_and_uses_valid_runtime_path(self) -> None:
        self.config.__file__ = str(
            self.root / "missing-runtime.zip" / "hermes-webui" / "api" / "config.py"
        )

        agent_dir = self.config._discover_agent_dir()
        static_root = self.config.get_static_root()

        self.assertTrue((agent_dir / "run_agent.py").is_file())
        self.assertEqual(
            (static_root / "index.html").read_text(encoding="utf-8"),
            "<main>bundled UI</main>",
        )

    def test_explicit_agent_dir_override_keeps_priority(self) -> None:
        override = self.root / "external-agent"
        override.mkdir()
        (override / "run_agent.py").write_text("# explicit agent\n", encoding="utf-8")
        os.environ["HERMES_WEBUI_AGENT_DIR"] = str(override)

        self.assertEqual(self.config._discover_agent_dir(), override.resolve())

    def test_refreshes_same_size_static_asset_after_runtime_upgrade(self) -> None:
        static_root = self.config.get_static_root()
        before = (static_root / "index.html").read_text(encoding="utf-8")
        updated = "<main>updated UI</main>"
        self.assertEqual(len(before), len(updated))
        self._write_runtime_archive(updated)

        self.config._BUNDLED_STATIC_ROOT = None
        refreshed_root = self.config.get_static_root()

        self.assertEqual(
            (refreshed_root / "index.html").read_text(encoding="utf-8"),
            updated,
        )

    def test_rejects_static_asset_path_traversal_from_runtime_zip(self) -> None:
        self._write_runtime_archive(
            "<main>bundled UI</main>",
            [("hermes-webui/static/../../escaped.txt", "outside target")],
        )
        self.config._BUNDLED_STATIC_ROOT = None

        self.config.get_static_root()

        self.assertFalse((self.root / "escaped.txt").exists())

    def test_uses_platform_default_home_when_home_override_is_unset(self) -> None:
        default_home = self.root / "platform-home"
        self.config._DEFAULT_HERMES_HOME = default_home
        os.environ.pop("HERMES_HOME", None)

        agent_dir = self.config._discover_agent_dir()
        static_root = self.config.get_static_root()

        self.assertEqual(agent_dir, (default_home / "hermes-agent").resolve())
        self.assertEqual(static_root, default_home / "webui")

    def test_rejects_agent_archive_path_traversal(self) -> None:
        self._write_runtime_archive(
            "<main>bundled UI</main>",
            [("hermes/../../escaped-agent.txt", "outside target")],
        )

        self.config._discover_agent_dir()

        self.assertFalse((self.root / "escaped-agent.txt").exists())

    def test_agent_extraction_rejects_existing_symlink_escape(self) -> None:
        agent_root = self.root / "home" / "hermes-agent"
        agent_root.mkdir(parents=True)
        outside = self.root / "outside-agent.py"
        outside.write_text("outside stays untouched\n", encoding="utf-8")
        try:
            (agent_root / "run_agent.py").symlink_to(outside)
        except (OSError, NotImplementedError) as exc:
            self.skipTest(f"symlink creation unavailable: {exc}")

        discovered = self.config._discover_agent_dir()

        self.assertIsNone(discovered)
        self.assertEqual(outside.read_text(encoding="utf-8"), "outside stays untouched\n")

    def test_updates_existing_discovery_injection_during_runtime_upgrade(self) -> None:
        legacy_config = self.root / "legacy-config.py"
        legacy_config.write_text(
            '''import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.resolve()
def get_static_root() -> Path:
    return REPO_ROOT / "static"
def _discover_agent_dir() -> Path:
    # WebUI discovery requires a real source directory, not the runtime ZIP.
    _origins = []
    """Original upstream agent discovery docstring."""
    return None
''',
            encoding="utf-8",
            newline="\n",
        )

        subprocess.run(
            [sys.executable, str(PATCHER), str(legacy_config)],
            check=True,
            capture_output=True,
            text=True,
        )
        patched = legacy_config.read_text(encoding="utf-8")

        self.assertEqual(patched.count("def _discover_agent_dir() -> Path:"), 1)
        self.assertIn("for _archive in _runtime_zip_archives():", patched)
        self.assertNotIn("    _origins = []", patched)
        compile(patched, str(legacy_config), "exec")


if __name__ == "__main__":
    unittest.main()
