"""Regression checks for source-preserving handoff XML."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location(
    "seal_handoff_snapshot", Path(__file__).parents[1] / "seal_handoff_snapshot.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def xml_file(name, body):
    root = ET.Element("repomix")
    files = ET.SubElement(root, "files")
    ET.SubElement(files, "file", path=name).text = body
    return ET.tostring(root)


class SnapshotTests(unittest.TestCase):
    def test_restores_exact_bytes_and_records_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = "\r\n  café <tag> & text\r\n\r\n".encode()
            (root / "sample.ex").write_bytes(raw)
            result, index = MODULE.seal(
                root, xml_file("sample.ex", "café <tag> & text"),
                {"git_commit": "test", "working_tree_clean": True},
            )
            body = ET.fromstring(result).find("./files/file").text.encode()
            self.assertEqual(body, raw)
            self.assertEqual(index["files"]["sample.ex"]["sha256"], MODULE.sha256(raw))

    def test_changed_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample.ex").write_text("changed")
            with self.assertRaisesRegex(ValueError, "differs"):
                MODULE.seal(root, xml_file("sample.ex", "old"), {})

    def test_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ("../secret", ".", "", "/absolute", "C:/secret", "a//b"):
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Unsafe"):
                    MODULE.seal(Path(directory), xml_file(name, "x"), {})

    def test_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "real").write_text("x")
            (root / "link").symlink_to(root / "real")
            with self.assertRaisesRegex(ValueError, "Symlink"):
                MODULE.seal(root, xml_file("link", "x"), {})

    def test_duplicate_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample").write_text("x")
            tree = ET.fromstring(xml_file("sample", "x"))
            ET.SubElement(tree.find("files"), "file", path="sample").text = "x"
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                MODULE.seal(root, ET.tostring(tree), {})

    def test_empty_file_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "empty").write_bytes(b"")
            _, index = MODULE.seal(root, xml_file("empty", ""), {})
            self.assertEqual(index["files"]["empty"]["bytes"], 0)

    def test_reviewed_exclusion_is_explicit_and_preserves_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample").write_text("x")
            (root / "fixture").write_bytes(b"dummy\r\n")
            result, index = MODULE.seal(
                root, xml_file("sample", "x"), {}, ["fixture"]
            )
            self.assertEqual(index["reviewed_security_exclusions_included"], ["fixture"])
            restored = ET.fromstring(result).find("./files/file[@path='fixture']").text
            self.assertEqual(restored.encode(), b"dummy\r\n")

    def test_reviewed_file_cannot_duplicate_existing_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample").write_text("x")
            with self.assertRaisesRegex(ValueError, "already included"):
                MODULE.seal(root, xml_file("sample", "x"), {}, ["sample"])


if __name__ == "__main__":
    unittest.main()
