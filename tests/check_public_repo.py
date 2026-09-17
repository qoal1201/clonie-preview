"""Failure cases for the public-document publication check."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("public_check", Path(__file__).resolve().parents[1] / "scripts/check-public-repo.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        for name in ["README", "INSTALL", "PRIVACY", "SECURITY", "RELEASE-NOTES", "CONTRIBUTING", "CHANGELOG"]:
            (self.root / (name + ".md")).write_text("# 시작하기\n")

    def errors(self):
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        return module.check(self.root)

    def test_public_links_and_localized_headings(self):
        (self.root / "README.md").write_text("[설치](INSTALL.md#시작하기)\n[외부](https://example.com)\n")
        self.assertEqual(self.errors(), [])

    def test_missing_image_blocks_publication(self):
        (self.root / "README.md").write_text("![화면](assets/missing.png)\n")
        self.assertTrue(any("missing relative link" in x for x in self.errors()))

    def test_private_path_and_internal_repo_block_publication(self):
        (self.root / "INSTALL.md").write_text("/Users/example/private\nclonie-desktop\n")
        self.assertEqual(sum("internal wording" in x for x in self.errors()), 2)

    def test_tracked_credentials_and_private_vault_are_rejected(self):
        (self.root / ".env.local").write_text("EXAMPLE=not-a-secret\n")
        (self.root / ".clonie").mkdir()
        (self.root / ".clonie/record.json").write_text("{}")
        self.assertEqual(sum("must not be tracked" in x for x in self.errors()), 2)

    def test_provenance_and_env_example_are_allowed(self):
        (self.root / "HISTORY.md").write_text("Historical development provenance: clonie-desktop\n")
        (self.root / ".env.example").write_text("EXAMPLE=\n")
        self.assertEqual(self.errors(), [])


if __name__ == "__main__":
    unittest.main()
