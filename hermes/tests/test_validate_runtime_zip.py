import importlib.util
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
    def _archive(self, extra_files=()):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        archive_path = Path(temporary.name) / "hermesrt.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            archive.writestr("hermes/hermes_cli/main.py", "# Hermes entry point\n")
            archive.writestr("python/encodings/__init__.py", "# stdlib\n")
            for name, content in extra_files:
                archive.writestr(name, content)
        return archive_path

    def test_accepts_archive_with_required_python_entrypoints(self):
        archive_path = self._archive()

        validator.validate_archive(archive_path)

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
