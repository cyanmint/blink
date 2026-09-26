import importlib.util
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "build" / "generate-native-module-registry.py"
SPEC = importlib.util.spec_from_file_location("native_module_registry", SCRIPT_PATH)
registry = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(registry)

CONFIG_PATH = Path(__file__).resolve().parents[1] / "build" / "configure_native_modules.py"
CONFIG_SPEC = importlib.util.spec_from_file_location("native_module_config", CONFIG_PATH)
module_config = importlib.util.module_from_spec(CONFIG_SPEC)
CONFIG_SPEC.loader.exec_module(module_config)


class NativeModuleRegistryTests(unittest.TestCase):
    def test_discovers_only_defined_python_module_initializers(self):
        nm_output = """\
0000000000000000 T _PyInit__ssl
                 U _PyInit__asyncio
0000000000000010 T _PyInit_zlib
                 U PyInit_absent
"""

        self.assertEqual(registry.parse_defined_initializers(nm_output), ["_ssl", "zlib"])

    def test_emits_registry_only_for_discovered_initializers(self):
        source = registry.render_registry(["_ssl", "zlib"])

        self.assertIn("PyImport_AppendInittab(\"_ssl\", PyInit__ssl);", source)
        self.assertIn("PyImport_AppendInittab(\"zlib\", PyInit_zlib);", source)
        self.assertNotIn("PyInit__asyncio", source)

    def test_empty_initializer_set_still_emits_valid_function(self):
        source = registry.render_registry([])

        self.assertIn("int hermes_register_native_modules(void) {", source)
        self.assertIn("return 0;", source)

    def test_enables_ssl_extensions_when_configure_disables_them(self):
        setup_lines = ["*static*", "#_ssl _ssl.c", "#_hashlib _hashopenssl.c"]

        result = module_config.ensure_required_static_modules(setup_lines)

        self.assertEqual(result[-2:], ["_ssl _ssl.c", "_hashlib _hashopenssl.c"])

    def test_does_not_duplicate_ssl_extensions_already_enabled(self):
        setup_lines = ["*static*", "_ssl _ssl.c", "_hashlib _hashopenssl.c"]

        self.assertEqual(module_config.ensure_required_static_modules(setup_lines), setup_lines)


    def test_fails_build_validation_if_ssl_initializer_is_missing(self):
        with self.assertRaisesRegex(RuntimeError, "_ssl"):
            registry.require_native_modules(["_hashlib", "zlib"])

    def test_accepts_required_tls_initializers(self):
        registry.require_native_modules(["_ssl", "_hashlib"])


if __name__ == "__main__":
    unittest.main()
