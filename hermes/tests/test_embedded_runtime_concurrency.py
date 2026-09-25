from __future__ import annotations

import plistlib
import os
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).parents[2]
RUNTIME_SOURCE = ROOT / "hermes" / "overlay" / "cpython" / "Programs" / "hermes_main.c"
COMMAND_SOURCE = ROOT / "Blink" / "Commands" / "hermes.m"
APP_DELEGATE_SOURCE = ROOT / "Blink" / "AppDelegate.m"
COMMANDS_PLIST = ROOT / "Resources" / "blinkCommandsDictionary.plist"
PACKAGE_SCRIPT = ROOT / "hermes" / "build" / "package-native-ios.sh"
PYTHON_OVERLAY = ROOT / "hermes" / "overlay" / "python"


class EmbeddedRuntimeConcurrencyTests(unittest.TestCase):
    def test_python_commands_use_independent_subinterpreters(self) -> None:
        source = RUNTIME_SOURCE.read_text(encoding="utf-8")

        self.assertIn("pthread_once(&runtime_init_once, initialize_runtime_once)", source)
        self.assertIn("PyThreadState_GetUnchecked()", source)
        self.assertIn("PyThreadState_New(runtime_main_interpreter)", source)
        self.assertIn("PyEval_AcquireThread(parent_state)", source)
        self.assertIn("PyThreadState_Swap(parent_state)", source)
        self.assertIn("Py_NewInterpreterFromConfig(&command_state, &command_config)", source)
        self.assertIn(".allow_daemon_threads = 0", source)
        self.assertNotIn("wait_for_command_threads", source)
        self.assertNotIn('setenv("HERMES_WEBUI_HOST"', source)
        self.assertNotIn('setenv("HERMES_WEBUI_PORT"', source)
        self.assertIn("Py_EndInterpreter(command_state)", source)
        self.assertNotIn("Py_FinalizeEx", source)
        self.assertNotIn("HERMES_PYTHON_MODE", source)

        package_script = PACKAGE_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("-Wl,-exported_symbol,_hermes_python_main", package_script)
        self.assertIn("int hermes_python_main(int argc, char **argv);", package_script)

    def test_python_dispatch_mode_is_not_process_global(self) -> None:
        source = COMMAND_SOURCE.read_text(encoding="utf-8")

        self.assertIn("return hermes_python_main(argc, argv);", source)
        self.assertNotIn("HERMES_PYTHON_MODE", source)

    def test_python_exit_is_handled_without_simple_run_helpers(self) -> None:
        source = RUNTIME_SOURCE.read_text(encoding="utf-8")

        self.assertIn("PyRun_StringFlags(", source)
        self.assertIn("PyRun_FileExFlags(", source)
        self.assertIn("handle_system_exit()", source)
        self.assertNotIn("PyRun_SimpleString(", source)
        self.assertNotIn("PyRun_SimpleFileExFlags(", source)

    def test_low_level_threads_are_joined_during_interpreter_shutdown(self) -> None:
        program = """\
import _thread
import concurrent.futures
import threading

started = threading.Event()
release = threading.Event()
ident = _thread.start_new_thread(lambda: (started.set(), release.wait()), ())
assert started.wait(2)
worker = next(thread for thread in threading.enumerate() if thread.ident == ident)
assert not worker.daemon
release.set()
worker.join(2)
assert not worker.is_alive()
pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
assert pool.submit(lambda: 42).result(timeout=2) == 42
print("managed low-level and executor threads passed")
"""
        env = os.environ.copy()
        existing_pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = os.pathsep.join(
            part for part in (str(PYTHON_OVERLAY), existing_pythonpath) if part
        )
        completed = subprocess.run(
            [sys.executable, "-c", program],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        self.assertIn("managed low-level and executor threads passed", completed.stdout)

    def test_sh_and_dash_entrypoints_are_registered_and_reasserted(self) -> None:
        with COMMANDS_PLIST.open("rb") as stream:
            commands = plistlib.load(stream)
        self.assertEqual(commands["sh"][:2], ["MAIN", "sh_main"])
        self.assertEqual(commands["dash"][:2], ["MAIN", "sh_main"])

        source = APP_DELEGATE_SOURCE.read_text(encoding="utf-8")
        self.assertIn('replaceCommand(@"sh", @"sh_main", false);', source)
        self.assertIn('replaceCommand(@"dash", @"sh_main", false);', source)

    def test_sh_supports_command_script_and_interactive_modes(self) -> None:
        source = COMMAND_SOURCE.read_text(encoding="utf-8")
        sh_entry = source.split("int sh_main(", 1)[1]

        self.assertIn("case 'c':", sh_entry)
        self.assertIn("return run_shell_command(command);", sh_entry)
        self.assertIn("run_shell_script", sh_entry)
        self.assertIn("run_shell_interactive", sh_entry)
        self.assertNotIn("sh: usage: sh -c command", sh_entry)

    def test_sh_c_preserves_conditional_command_chaining(self) -> None:
        source = COMMAND_SOURCE.read_text(encoding="utf-8")

        self.assertIn("run_shell_command(command)", source)
        self.assertIn("SHELL_CHAIN_AND", source)
        self.assertIn("SHELL_CHAIN_OR", source)

    def test_limited_script_mode_is_disclosed_at_invocation(self) -> None:
        source = COMMAND_SOURCE.read_text(encoding="utf-8")

        self.assertIn("line-based ios_system compatibility mode", source)


if __name__ == "__main__":
    unittest.main()
