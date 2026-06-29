#!/usr/bin/env python3
"""Increment the +build number in mobile/pubspec.yaml (e.g. 1.0.0+3 -> 1.0.0+4)."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def bump(path: Path) -> tuple[str, int]:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    version_name = ""
    build_number = 0
    found = False

    for i, line in enumerate(lines):
        if not line.startswith("version:"):
            continue
        match = re.match(r"version:\s*(\S+)", line)
        if not match:
            raise SystemExit(f"Could not parse version line: {line!r}")
        raw = match.group(1)
        if "+" in raw:
            version_name, build_raw = raw.split("+", 1)
            build_number = int(build_raw)
        else:
            version_name, build_number = raw, 0
        build_number += 1
        lines[i] = f"version: {version_name}+{build_number}\n"
        found = True
        break

    if not found:
        raise SystemExit(f"No version: line in {path}")

    path.write_text("".join(lines), encoding="utf-8")
    return version_name, build_number


def main() -> None:
    pubspec = Path(sys.argv[1] if len(sys.argv) > 1 else "mobile/pubspec.yaml")
    if not pubspec.is_file():
        raise SystemExit(f"pubspec not found: {pubspec}")
    name, build = bump(pubspec)
    print(f"{name} {build}")


if __name__ == "__main__":
    main()
