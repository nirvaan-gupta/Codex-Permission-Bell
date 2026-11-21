"""Check that build credentials are generated privately and stay stable."""
import importlib.util
import re
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('prepare_build', Path(__file__).resolve().parents[1] / 'scripts/prepare_build.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class BuildTests(unittest.TestCase):
    def test_private_matching_token_and_unchanged_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module.ROOT = root
            (root / 'Sources').mkdir()
            (root / 'browser-extension').mkdir()
            swift = 'let bridgeToken = "__BRIDGE_TOKEN__"\n'
            js = "const TOKEN = '__BRIDGE_TOKEN__';\n"
            (root / 'Sources/main.swift').write_text(swift)
            (root / 'browser-extension/background.js').write_text(js)
            module.prepare(root / 'stage')
            token = (root / '.local/bridge-token').read_text().strip()
            self.assertRegex(token, r'^[0-9a-f]{64}$')
            self.assertEqual((root / '.local/bridge-token').stat().st_mode & 0o777, 0o600)
            self.assertEqual((root / 'Sources/main.swift').read_text(), swift)
            self.assertEqual((root / 'browser-extension/background.js').read_text(), js)
            self.assertIn(token, (root / 'stage/main.swift').read_text())
            self.assertIn(token, (root / 'dist/browser-extension/background.js').read_text())
            module.prepare(root / 'stage2')
            self.assertEqual((root / '.local/bridge-token').read_text().strip(), token)
            (root / '.local/bridge-token').write_text('invalid\n')
            with self.assertRaises(ValueError):
                module.prepare(root / 'stage3')

if __name__ == '__main__':
    unittest.main()
