"""Inspect actual release data packages: python3 tests/export/test_packages.py."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN", "godot")


class ReleasePackages(unittest.TestCase):
    def test_release_contents(self):
        subprocess.run(
            [GODOT, "--headless", "--path", str(ROOT), "--editor", "--import", "--quit"],
            check=True, stdout=subprocess.DEVNULL, timeout=120,
        )
        presets = re.findall(r'^name="([^"]+)"$', (ROOT / "export_presets.cfg").read_text(), re.MULTILINE)
        self.assertEqual(set(presets), {"Web", "Windows Desktop", "Linux", "Android"})
        with tempfile.TemporaryDirectory(dir=ROOT / ".godot", prefix="export-test-") as output:
            for index, name in enumerate(presets):
                with self.subTest(preset=name):
                    archive = Path(output) / f"{index}.zip"
                    result = subprocess.run(
                        [GODOT, "--headless", "--path", str(ROOT), "--export-pack", name, str(archive)],
                        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout)
                    self.assertNotIn("SCRIPT ERROR:", result.stdout)
                    with ZipFile(archive) as package:
                        files = set(package.namelist())
                    for locale in ("en", "es"):
                        self.assertIn(f"src/localization/translations.{locale}.translation", files)
                    self.assertNotIn("assets/factions/PORTRAIT_PROMPTS.json", files)
                    self.assertNotIn("AudioPalette.gdc", files)
                    self.assertNotIn("UnitVisual.gdc", files)
                    for path in files:
                        self.assertFalse(path.startswith((
                            "tests/", "tools/", "artifacts/", "build/", "export/", "node_modules/",
                        )), path)
                        self.assertNotIn(Path(path).suffix, (".csv", ".md", ".py"), path)
                    print(f"{name}: {len(files)} runtime files; both catalogs present; development files excluded")


if __name__ == "__main__":
    unittest.main()
