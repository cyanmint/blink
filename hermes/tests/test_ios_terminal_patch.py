import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
PATCH_PATH = ROOT / "hermes" / "overlay" / "patches" / "patch-ios-stability.py"
SPEC = importlib.util.spec_from_file_location("ios_stability_patch_test", PATCH_PATH)
patcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(patcher)


class IosTerminalPatchTests(unittest.TestCase):
    def _terminal_module(self, directory: str) -> Path:
        path = Path(directory) / "terminal_tool.py"
        path.write_text(
            "import os, sys\n"
            "def _error_json(error, **extra):\n"
            "    return {'error': error, **extra}\n"
            "def _acquire_env(plan, task_id):\n"
            "    return 'environment-acquired'\n"
            "def terminal_tool(plan, task_id=None):\n"
            "        env = _acquire_env(plan, task_id)\n"
            "        return env\n",
            encoding="utf-8",
            newline="\n",
        )
        return path

    def test_patches_ios_local_backend_and_leaves_api_backend_dispatch_available(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self._terminal_module(directory)
            patcher.patch_ios_local_terminal(path)
            source = path.read_text(encoding="utf-8")
            namespace = {}
            exec(compile(source, str(path), "exec"), namespace)

            with patch.dict(os.environ, {"HERMES_IOS_TERMINAL": "1"}):
                local = namespace["terminal_tool"](SimpleNamespace(env_type="local"))
                remote = namespace["terminal_tool"](SimpleNamespace(env_type="modal"))

            self.assertEqual(local["status"], "unsupported")
            self.assertEqual(local["exit_code"], 126)
            self.assertIn("CPython disables subprocess creation on iOS", local["error"])
            self.assertIn("TERMINAL_MODAL_MODE='managed'", local["error"])
            self.assertIn("The command was not run and no process was created", local["error"])
            self.assertEqual(remote, "environment-acquired")

    def test_ios_platform_without_marker_rejects_local_backend(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self._terminal_module(directory)
            patcher.patch_ios_local_terminal(path)
            namespace = {}
            exec(compile(path.read_text(encoding="utf-8"), str(path), "exec"), namespace)

            with patch.object(sys, "platform", "ios"), patch.dict(os.environ, {}, clear=True):
                result = namespace["terminal_tool"](SimpleNamespace(env_type="local"))

            self.assertEqual(result["status"], "unsupported")
            self.assertIn("local terminal backend cannot run", result["error"])

    def test_patch_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self._terminal_module(directory)
            patcher.patch_ios_local_terminal(path)
            first = path.read_text(encoding="utf-8")
            patcher.patch_ios_local_terminal(path)
            self.assertEqual(path.read_text(encoding="utf-8"), first)

    def test_missing_anchor_fails_build(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "terminal_tool.py"
            path.write_text("def terminal_tool():\n    pass\n", encoding="utf-8", newline="\n")
            with self.assertRaisesRegex(SystemExit, "environment acquisition anchor not found"):
                patcher.patch_ios_local_terminal(path)


if __name__ == "__main__":
    unittest.main()
