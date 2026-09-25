#!/usr/bin/env python3
"""Inspect and apply a full-file Fount overlay without overwriting local edits.

Dry-run is the default. No Git commands or database commands are executed.
The archive manifest is metadata and is not installed as a self-hashed file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tempfile
import uuid
import zipfile


class OverlayError(Exception):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def relative_path(value: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        raise OverlayError(f"Invalid path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or "." in path.parts:
        raise OverlayError(f"Unsafe path: {value!r}")
    if str(path) != value or value.endswith("/") or ":" in path.parts[0]:
        raise OverlayError(f"Noncanonical path: {value!r}")
    if path.parts[0] in (".git", ".fount-overlay-backups") or path.parts[0].startswith(".fount-overlay-stage-"):
        raise OverlayError(f"Reserved destination: {value!r}")
    return path


def target_path(root: Path, relative: str) -> Path:
    rel = relative_path(relative)
    current = root
    for part in rel.parts:
        current = current / part
        if current.is_symlink():
            raise OverlayError(f"Refusing symlink: {relative}")
        if current.exists() and current != root.joinpath(*rel.parts) and not current.is_dir():
            raise OverlayError(f"Non-directory ancestor: {relative}")
    return root.joinpath(*rel.parts)


def read_regular(path: Path) -> bytes | None:
    try:
        st = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(st.st_mode):
        raise OverlayError(f"Not a regular file: {path}")
    return path.read_bytes()


def validate_archive(archive: Path, manifest_path: Path | None):
    with zipfile.ZipFile(archive) as zipped:
        names = zipped.namelist()
        if len(names) != len(set(names)):
            raise OverlayError("Duplicate archive entries")
        for info in zipped.infolist():
            relative_path(info.filename)
            file_type = stat.S_IFMT(info.external_attr >> 16)
            if info.is_dir() or file_type not in (0, stat.S_IFREG):
                raise OverlayError(f"Archive member is not a normal file: {info.filename}")
        manifest_name = "handoff/fount-overlay.manifest.json"
        if manifest_name not in names:
            raise OverlayError("Archive manifest missing")
        embedded = zipped.read(manifest_name)
        if manifest_path is not None and manifest_path.read_bytes() != embedded:
            raise OverlayError("External and embedded manifests differ")
        manifest = json.loads(embedded)
        if manifest.get("format_version") != 1:
            raise OverlayError("Unsupported manifest version")
        entries = manifest.get("files")
        if not isinstance(entries, list):
            raise OverlayError("Invalid manifest file list")
        entries_by_path = {}
        blobs = {}
        for entry in entries:
            if not isinstance(entry, dict):
                raise OverlayError("Invalid file entry")
            name = entry.get("path")
            relative_path(name)
            if name == manifest_name or name in entries_by_path:
                raise OverlayError(f"Duplicate/self-hashed manifest entry: {name}")
            action = entry.get("action")
            if action not in ("add", "modify", "delete"):
                raise OverlayError(f"Invalid action for {name}")
            for key in ("original_sha256", "original_terminal_lf_sha256", "result_sha256"):
                value = entry.get(key)
                if value is not None and (
                    not isinstance(value, str) or len(value) != 64
                    or any(c not in "0123456789abcdef" for c in value)
                ):
                    raise OverlayError(f"Invalid {key} for {name}")
            mode = entry.get("mode")
            if not isinstance(mode, int) or mode not in (0o644, 0o755):
                raise OverlayError(f"Invalid file mode for {name}")
            if action == "delete":
                if entry.get("result_sha256") is not None or name in names:
                    raise OverlayError(f"Deletion has a result payload: {name}")
                if entry.get("original_sha256") is None:
                    raise OverlayError(f"Deletion without known preimage: {name}")
            else:
                if name not in names:
                    raise OverlayError(f"Missing archive payload: {name}")
                data = zipped.read(name)
                if digest(data) != entry.get("result_sha256"):
                    raise OverlayError(f"Payload checksum mismatch: {name}")
                blobs[name] = data
                if action == "add" and entry.get("original_sha256") is not None:
                    raise OverlayError(f"Addition has an original hash: {name}")
                if action == "modify" and entry.get("original_sha256") is None:
                    raise OverlayError(f"Modification needs manual preimage review: {name}")
            entries_by_path[name] = entry
        declared_deletions = manifest.get("deletions")
        actual_deletions = sorted(name for name, entry in entries_by_path.items() if entry["action"] == "delete")
        if declared_deletions != actual_deletions:
            raise OverlayError("Explicit deletion list differs from manifest operations")
        admitted = set(blobs) | {manifest_name}
        if set(names) != admitted:
            raise OverlayError(f"Unlisted archive entries: {sorted(set(names) - admitted)}")
        return manifest, blobs


def preflight(root: Path, entries: list[dict], allow_terminal_newline: bool = False):
    conflicts = []
    plan = []
    for entry in entries:
        name = entry["path"]
        try:
            destination = target_path(root, name)
            existing = read_regular(destination)
            current_hash = digest(existing) if existing is not None else None
            original = entry.get("original_sha256")
            accepted_preimages = {original}
            if allow_terminal_newline and entry.get("original_terminal_lf_sha256"):
                accepted_preimages.add(entry["original_terminal_lf_sha256"])
            result = entry.get("result_sha256")
            if entry["action"] == "delete":
                if existing is None:
                    operation = "unchanged"
                elif current_hash in accepted_preimages:
                    operation = "delete"
                else:
                    raise OverlayError("locally changed deletion target")
            elif existing is not None and current_hash == result:
                actual_mode = stat.S_IMODE(destination.stat().st_mode)
                operation = "unchanged" if actual_mode == entry["mode"] else "chmod"
            elif entry["action"] == "add":
                if existing is not None:
                    raise OverlayError("new-file collision")
                operation = "write"
            elif current_hash in accepted_preimages:
                operation = "write"
            else:
                raise OverlayError("missing or locally changed preimage")
            plan.append({
                "path": name, "operation": operation,
                "observed_sha256": current_hash, "entry": entry,
            })
        except (OverlayError, OSError) as error:
            conflicts.append({"path": name, "reason": str(error)})
    if conflicts:
        raise OverlayError(json.dumps({"conflicts": conflicts}, indent=2))
    return plan


def apply_plan(root: Path, plan: list[dict], blobs: dict[str, bytes]):
    changes = [item for item in plan if item["operation"] != "unchanged"]
    if not changes:
        return {"changed": 0, "backup_directory": None}

    transaction = uuid.uuid4().hex
    backups_parent = root / ".fount-overlay-backups"
    if backups_parent.is_symlink():
        raise OverlayError("Backup directory is a symlink")
    backups_parent.mkdir(exist_ok=True)
    backup = backups_parent / transaction
    backup.mkdir()
    stage = Path(tempfile.mkdtemp(prefix=".fount-overlay-stage-", dir=root))
    completed = []
    created_directories = []
    journal_path = backup / "journal.json"

    def journal(status: str):
        journal_path.write_text(json.dumps({
            "status": status, "root": str(root),
            "operations": changes, "completed": completed,
            "created_directories": [str(p.relative_to(root)) for p in created_directories],
        }, indent=2), encoding="utf-8")

    try:
        # Take all backups before changing any tracked path.
        for item in changes:
            name = item["path"]
            destination = target_path(root, name)
            existing = read_regular(destination)
            observed = digest(existing) if existing is not None else None
            if observed != item["observed_sha256"]:
                raise OverlayError(f"File changed after preflight: {name}")
            if existing is not None:
                saved = backup / "originals" / name
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(destination, saved)
            if item["operation"] == "write":
                staged = stage / name
                staged.parent.mkdir(parents=True, exist_ok=True)
                staged.write_bytes(blobs[name])
                if digest(staged.read_bytes()) != item["entry"]["result_sha256"]:
                    raise OverlayError(f"Staged checksum mismatch: {name}")
                staged.chmod(item["entry"]["mode"])
        journal("prepared")

        # Full-file additions/replacements precede the explicit deletions.
        ordered = sorted(changes, key=lambda item: item["operation"] == "delete")
        for item in ordered:
            name = item["path"]
            destination = target_path(root, name)
            existing = read_regular(destination)
            observed = digest(existing) if existing is not None else None
            if observed != item["observed_sha256"]:
                raise OverlayError(f"File changed during application: {name}")

            missing_parents = []
            parent = destination.parent
            while parent != root and not parent.exists():
                missing_parents.append(parent)
                parent = parent.parent
            for directory in reversed(missing_parents):
                directory.mkdir()
                created_directories.append(directory)

            if item["operation"] == "write":
                os.replace(stage / name, destination)
            elif item["operation"] == "delete":
                destination.unlink()
            elif item["operation"] == "chmod":
                destination.chmod(item["entry"]["mode"])
            completed.append(name)
            journal("applying")

        for item in changes:
            destination = target_path(root, item["path"])
            actual = read_regular(destination)
            expected = item["entry"]["result_sha256"]
            if (digest(actual) if actual is not None else None) != expected:
                raise OverlayError(f"Post-application verification failed: {item['path']}")
        journal("complete")
        return {"changed": len(changes), "backup_directory": str(backup)}

    except BaseException:
        rollback_conflicts = []
        by_path = {item["path"]: item for item in changes}
        for name in reversed(completed):
            item = by_path[name]
            destination = target_path(root, name)
            actual = read_regular(destination)
            actual_hash = digest(actual) if actual is not None else None
            installed_hash = item["entry"]["result_sha256"]
            # Preserve a file changed by somebody else after this installer
            # wrote it. Its original remains available in the backup.
            if actual_hash != installed_hash:
                rollback_conflicts.append(name)
                continue
            saved = backup / "originals" / name
            if saved.exists():
                shutil.copy2(saved, destination)
            elif destination.exists():
                destination.unlink()
        for directory in reversed(created_directories):
            try:
                directory.rmdir()
            except OSError:
                pass
        journal("rollback_conflicts" if rollback_conflicts else "rolled_back")
        if rollback_conflicts:
            print(json.dumps({
                "rollback_conflicts": rollback_conflicts,
                "backup_directory": str(backup),
            }), file=sys.stderr)
        raise
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--allow-terminal-newline", action="store_true",
                        help="after review, also accept the computed XML body plus one terminal LF; no other normalization")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="preflight only (default)")
    mode.add_argument("--apply", action="store_true", help="apply after successful preflight")
    args = parser.parse_args(argv)

    try:
        root = args.root.expanduser().resolve(strict=True)
        if not root.is_dir():
            raise OverlayError("Target root is not a directory")
        manifest, blobs = validate_archive(args.archive, args.manifest)
        plan = preflight(root, manifest["files"], args.allow_terminal_newline)
        output = {
            "mode": "apply" if args.apply else "dry_run",
            "root": str(root),
            "files": [{"path": item["path"], "operation": item["operation"]} for item in plan],
        }
        if args.apply:
            output["result"] = apply_plan(root, plan, blobs)
        print(json.dumps(output, indent=2))
        return 0
    except (OverlayError, OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(f"Overlay refused: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())