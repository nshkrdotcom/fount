#!/usr/bin/env python3
"""Remove only empty ancestors of manifest-deleted files after overlay application.

Never removes a file, symlink, undeclared nonempty directory, or checkout content.
The original full-file applier deliberately leaves directories in place. This
post-apply step makes the physical package removal explicit and fail-closed.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from apply_overlay import OverlayError, target_path, validate_archive


def prune(root: Path, archive: Path) -> dict:
    root = root.resolve(strict=True)
    manifest, _blobs = validate_archive(archive, None)
    parents: set[Path] = set()
    for entry in manifest["files"]:
        if entry["action"] != "delete":
            continue
        target = target_path(root, entry["path"])
        if target.exists():
            raise OverlayError(f"Deletion has not been applied: {entry['path']}")
        parent = target.parent
        while parent != root:
            if parent.is_symlink():
                raise OverlayError(f"Refusing symlink ancestor: {parent}")
            parents.add(parent)
            parent = parent.parent
    removed = []
    for parent in sorted(parents, key=lambda p: (-len(p.parts), str(p))):
        try:
            parent.rmdir()  # Empty directory only. No unlink/rmtree or wildcard deletion.
        except FileNotFoundError:
            pass
        except OSError:
            continue
        else:
            removed.append(str(parent.relative_to(root)))
    return {"removed_empty_directories": removed,
            "remaining_ancestors": sorted(str(p.relative_to(root)) for p in parents if p.exists())}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = prune(args.root, args.archive)
        print(json.dumps(result, indent=2))
        return 0
    except (OverlayError, OSError, ValueError, KeyError) as error:
        print(f"Directory cleanup refused: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
