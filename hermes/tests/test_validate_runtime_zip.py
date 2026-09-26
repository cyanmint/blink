import importlib.util
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "hermes" / "build" / "validate-runtime-zip.py"
SPEC = importlib.util.spec_from_file_location("validate_runtime_zip_test", MODULE_PATH)
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class RuntimeZipValidationTests(unittest.TestCase):
    def _archive(self, extra_files=(), omit=()):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        archive_path = Path(temporary.name) / "hermesrt.zip"
        entries = {
            "hermes/hermes_cli/main.py": "# Hermes entry point\n",
            "python/encodings/__init__.py": "# stdlib\n",
            "python/site-packages/openai/__init__.py": "from .lib import azure\n",
            "python/site-packages/openai/lib/__init__.py": "# OpenAI SDK lib package\n",
            "python/site-packages/openai/lib/azure.py": "MODULE = True\n",
        }
        for name in omit:
            entries.pop(name, None)
        with zipfile.ZipFile(archive_path, "w") as archive:
            for name, content in entries.items():
                archive.writestr(name, content)
            for name, content in extra_files:
                archive.writestr(name, content)
        return archive_path

    def test_accepts_archive_with_required_python_entrypoints(self):
        archive_path = self._archive()

        validator.validate_archive(archive_path)

    def test_rejects_archive_without_zip_importable_openai_lib_package(self):
        archive_path = self._archive(omit=["python/site-packages/openai/lib/__init__.py"])

        with self.assertRaisesRegex(ValueError, "openai/lib/__init__\\.py"):
            validator.validate_archive(archive_path)

    def test_rejects_archive_without_openai_lib_module(self):
        archive_path = self._archive(omit=["python/site-packages/openai/lib/azure.py"])

        with self.assertRaisesRegex(ValueError, "openai/lib/azure\\.py"):
            validator.validate_archive(archive_path)

    def test_imports_openai_lib_submodule_from_zip(self):
        archive_path = self._archive()
        code = (
            "import sys; "
            "sys.path.insert(0, sys.argv[1] + '/python/site-packages'); "
            "import openai.lib.azure; "
            "assert openai.lib.azure.MODULE"
        )

        subprocess.run(
            [sys.executable, "-S", "-c", code, str(archive_path)],
            check=True,
            capture_output=True,
            text=True,
        )

    def test_rejects_native_extension_files(self):
        archive_path = self._archive([("python/site-packages/example.so", b"not actually ELF")])

        with self.assertRaisesRegex(ValueError, "native"):
            validator.validate_archive(archive_path)

    def test_rejects_native_binary_hidden_under_data_extension(self):
        archive_path = self._archive([("hermes/data/runtime.dat", b"\x7fELF\x02\x01")])

        with self.assertRaisesRegex(ValueError, "native"):
            validator.validate_archive(archive_path)


if __name__ == "__main__":
    unittest.main()
