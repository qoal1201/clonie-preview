"""Installer regression checks. An optional local release archive enables installation.

CLONIE_TEST_ARCHIVE=/absolute/release.zip python3 scripts/test-install.py
The tests never launch the app and use disposable installation directories.
"""
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("install.sh")
NATIVE = platform.system() == "Darwin" and platform.machine() == "arm64"


class InstallerTests(unittest.TestCase):
    def run_installer(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *map(str, args)],
                              text=True, capture_output=True, timeout=120)

    def test_help_does_not_install(self):
        result = self.run_installer("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("never", result.stdout)

    def test_existing_apps_are_preserved_before_download(self):
        for app_name in ("Ghostbar.app", "Clonie.app"):
            with self.subTest(app_name=app_name), tempfile.TemporaryDirectory() as temp:
                app = Path(temp) / app_name
                app.mkdir()
                sentinel = app / "user-file"
                sentinel.write_text("preserve me")
                result = self.run_installer("--app-dir", temp)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Already exists", result.stderr)
                self.assertEqual(sentinel.read_text(), "preserve me")
                self.assertNotIn("Downloading", result.stdout)

    @unittest.skipUnless(NATIVE, "macOS Apple Silicon installer")
    def test_bad_archive_is_rejected_without_creating_target(self):
        with tempfile.TemporaryDirectory() as temp:
            bad = Path(temp) / "bad.zip"
            bad.write_bytes(b"not the release")
            dest = Path(temp) / "apps"
            result = self.run_installer("--app-dir", dest, "--archive", bad)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SHA-256 mismatch", result.stderr)
            self.assertFalse(dest.exists())

    @unittest.skipUnless(NATIVE and os.environ.get("CLONIE_TEST_ARCHIVE"),
                         "set CLONIE_TEST_ARCHIVE to the release ZIP")
    def test_verified_release_installs_without_launch(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / "Applications with spaces"
            result = self.run_installer("--app-dir", dest, "--archive",
                                        os.environ["CLONIE_TEST_ARCHIVE"])
            self.assertEqual(result.returncode, 0, result.stderr)
            app = dest / "Clonie.app"
            self.assertTrue((app / "Contents/MacOS/Clonie").is_file())
            self.assertTrue((app / "Contents/Resources/EmbeddingModel/manifest.json").is_file())
            self.assertEqual(list(dest.glob(".clonie-install.*")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
