#!/usr/bin/env python3
"""Verify a parsable Repomix export against local source and add byte identities.

Use a separate output path. This never edits source files or contacts a provider.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import xml.etree.ElementTree as ET


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_path(root: Path, name: str) -> Path:
    rel = PurePosixPath(name)
    if not name or not rel.parts or str(rel) != name or rel.is_absolute() or ".." in rel.parts:
        raise ValueError(f"Unsafe source path: {name!r}")
    if "\\" in name or "\x00" in name or ":" in rel.parts[0] or rel.parts[0] == ".git":
        raise ValueError(f"Unsafe source path: {name!r}")
    current = root
    for part in rel.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"Symlink source: {name}")
    if not current.is_file():
        raise ValueError(f"Missing source file: {name}")
    return current


def git_identity(root: Path) -> dict:
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    status = subprocess.check_output(
        ["git", "-C", str(root), "status", "--porcelain", "--", "."], text=True
    )
    return {"git_commit": commit, "working_tree_clean": not bool(status.strip())}


def seal(root: Path, packed: bytes, identity: dict, reviewed_files=()) -> tuple[bytes, dict]:
    root = root.resolve(strict=True)
    document = ET.fromstring(packed)
    if document.tag != "repomix" or document.find("snapshot_index") is not None:
        raise ValueError("Expected an unsealed, parsable Repomix XML document")
    files = document.findall("./files/file")
    if not files:
        raise ValueError("Snapshot has no source files")
    included = {element.attrib.get("path", "") for element in files}
    for name in reviewed_files:
        if name in included:
            raise ValueError(f"Reviewed file already included: {name}")
        original = source_path(root, name).read_bytes().decode("utf-8")
        element = ET.SubElement(document.find("files"), "file", path=name)
        element.text = original.replace("\r\n", "\n").replace("\r", "\n")
        files.append(element)
        included.add(name)
    entries = {}
    for element in files:
        name = element.attrib.get("path", "")
        if name in entries:
            raise ValueError(f"Duplicate source path: {name}")
        path = source_path(root, name)
        raw = path.read_bytes()
        original = raw.decode("utf-8")
        body = element.text or ""
        # Repomix may trim file edges; XML parsers normalize CRLF. No other
        # difference is accepted. Restore exact source text after comparison.
        normalized = original.replace("\r\n", "\n").replace("\r", "\n")
        if body.strip() != normalized.strip():
            raise ValueError(f"Snapshot differs from source: {name}")
        element.text = original
        entries[name] = {
            "sha256": sha256(raw),
            "bytes": len(raw),
            "mode": 493 if os.access(path, os.X_OK) else 420,
        }
    index = {
        "source_name": root.name,
        **identity,
        "reviewed_security_exclusions_included": list(reviewed_files),
        "files": dict(sorted(entries.items())),
    }
    metadata = ET.Element("snapshot_index")
    metadata.text = json.dumps(index, indent=2, ensure_ascii=False)
    document.insert(0, metadata)
    result = ET.tostring(document, encoding="utf-8", xml_declaration=True)
    # XML character references preserve CR bytes when parsed again.
    result = result.replace(b"\r", b"&#13;")
    reparsed = ET.fromstring(result)
    for element in reparsed.findall("./files/file"):
        restored = (element.text or "").encode("utf-8")
        if sha256(restored) != entries[element.attrib["path"]]["sha256"]:
            raise ValueError(f"Roundtrip mismatch: {element.attrib['path']}")
    return result, index


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--include-reviewed", action="append", default=[],
                        help="Explicitly include an omitted file only after human/agent secret review")
    args = parser.parse_args()
    try:
        root = args.root.expanduser().resolve(strict=True)
        result, index = seal(root, args.input.read_bytes(), git_identity(root), args.include_reviewed)
        # Exclusive create prevents replacing a previous packet accidentally.
        with args.output.open("xb") as destination:
            destination.write(result)
        print(json.dumps({
            "output": str(args.output),
            "files": len(index["files"]),
            "sha256": sha256(result),
            "git_commit": index["git_commit"],
            "working_tree_clean": index["working_tree_clean"],
        }, indent=2))
        return 0
    except (OSError, ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"Snapshot refused: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
