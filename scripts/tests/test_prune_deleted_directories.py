import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

HANDOFF = Path(__file__).resolve().parents[2] / "handoff"
sys.path.insert(0, str(HANDOFF))
import prune_deleted_directories as cleanup
from apply_overlay import OverlayError


class EmptyDirectoryCleanupTests(unittest.TestCase):
    def archive(self, directory):
        archive = directory / "overlay.zip"
        entry = {"path": "packages/removed/lib/a.ex", "action": "delete",
                 "original_sha256": hashlib.sha256(b"source").hexdigest(),
                 "result_sha256": None, "mode": 0o644}
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.writestr("handoff/fount-overlay.manifest.json", json.dumps({
                "format_version": 1, "files": [entry], "deletions": [entry["path"]]}))
        return archive

    def test_removes_only_empty_declared_ancestors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "packages/removed/lib").mkdir(parents=True)
            (root / "packages/keep").mkdir()
            (root / "packages/keep/stay.ex").write_text("keep")
            result = cleanup.prune(root, self.archive(root))
            self.assertFalse((root / "packages/removed").exists())
            self.assertEqual((root / "packages/keep/stay.ex").read_text(), "keep")
            self.assertIn("packages/removed", result["removed_empty_directories"])

    def test_preserves_unseen_files_and_reports_remaining_ancestors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "packages/removed/lib").mkdir(parents=True)
            asset = root / "packages/removed/private.svg"
            asset.write_text("unseen")
            result = cleanup.prune(root, self.archive(root))
            self.assertEqual(asset.read_text(), "unseen")
            self.assertIn("packages/removed", result["remaining_ancestors"])

    def test_refuses_unapplied_deletion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "packages/removed/lib/a.ex"
            target.parent.mkdir(parents=True)
            target.write_text("source")
            with self.assertRaises(OverlayError):
                cleanup.prune(root, self.archive(root))
            self.assertEqual(target.read_text(), "source")

    def test_refuses_symlink_ancestor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "packages").mkdir()
            (root / "outside/lib").mkdir(parents=True)
            (root / "packages/removed").symlink_to(root / "outside", target_is_directory=True)
            with self.assertRaises(OverlayError):
                cleanup.prune(root, self.archive(root))
            self.assertTrue((root / "outside/lib").exists())


if __name__ == "__main__":
    unittest.main()
