import importlib.util
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "build" / "generate-native-module-registry.py"
SPEC = importlib.util.spec_from_file_location("native_module_registry", SCRIPT_PATH)
registry = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(registry)


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


if __name__ == "__main__":
    unittest.main()
