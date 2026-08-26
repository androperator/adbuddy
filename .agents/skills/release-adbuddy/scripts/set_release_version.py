#!/usr/bin/env python3
"""Synchronize ADBuddy's tracked release-version surfaces."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


SEMVER_PATTERN = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


@dataclass(frozen=True)
class VersionSurface:
    relative_path: str
    pattern: re.Pattern[str]


VERSION_SURFACES = (
    VersionSurface(
        "Sources/ADBuddyMCP/ADBuddyMCPServer.swift",
        re.compile(
            r'(?P<prefix>"serverInfo": \["name": "adbuddy", "version": ")'
            r'(?P<version>[^"]+)(?P<suffix>"\],)'
        ),
    ),
    VersionSurface(
        "docs/release.md",
        re.compile(
            r"(?P<prefix>ADBuddy-macos-universal-)"
            r"(?P<version>[0-9][0-9A-Za-z.+-]*)(?P<suffix>\.zip)"
        ),
    ),
    VersionSurface(
        "docs/release.md",
        re.compile(
            r"(?P<prefix>The current version is\n`)(?P<version>[^`]+)(?P<suffix>`\.)"
        ),
    ),
    VersionSurface(
        "docs/release.md",
        re.compile(r'(?P<prefix>^  version ")(?P<version>[^"]+)(?P<suffix>"$)', re.MULTILINE),
    ),
    VersionSurface(
        "scripts/package_release.sh",
        re.compile(
            r"(?P<prefix>release version in \$VERSION_FILE must look like )"
            r'(?P<version>[0-9][0-9A-Za-z.+-]*)(?P<suffix>")'
        ),
    ),
)


def fail(message: str) -> None:
    print(f"set_release_version: {message}", file=sys.stderr)
    raise SystemExit(1)


def repository_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "not inside a Git repository"
        fail(detail)
    return Path(result.stdout.strip())


def read_current_version(root: Path) -> str:
    version_path = root / "VERSION"
    try:
        version = version_path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        fail(f"missing version source: {version_path}")

    if not SEMVER_PATTERN.fullmatch(version):
        fail(f"VERSION must contain a semantic version, found {version!r}")
    return version


def synchronized_content(surface: VersionSurface, root: Path, current_version: str) -> str:
    path = root / surface.relative_path
    try:
        content = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"missing version surface: {surface.relative_path}")

    matches = list(surface.pattern.finditer(content))
    if len(matches) != 1:
        fail(
            f"expected exactly one version surface in {surface.relative_path}, "
            f"found {len(matches)}"
        )

    found_version = matches[0].group("version")
    if found_version != current_version:
        fail(
            f"{surface.relative_path} contains {found_version!r}, but VERSION is "
            f"{current_version!r}; synchronize it before bumping"
        )
    return content


def update_surface(
    surface: VersionSurface,
    root: Path,
    current_version: str,
    new_version: str,
) -> bool:
    content = synchronized_content(surface, root, current_version)
    updated_content, replacements = surface.pattern.subn(
        lambda match: f"{match.group('prefix')}{new_version}{match.group('suffix')}",
        content,
        count=1,
    )
    if replacements != 1:
        fail(f"could not update {surface.relative_path}")

    if updated_content == content:
        return False

    (root / surface.relative_path).write_text(updated_content, encoding="utf-8")
    return True


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Synchronize ADBuddy's tracked release-version surfaces."
    )
    parser.add_argument("new_version", help="Semantic version without a v prefix")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify that every tracked surface already matches new_version.",
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    new_version = arguments.new_version
    if not SEMVER_PATTERN.fullmatch(new_version):
        fail(f"new version must be semantic version such as 0.1.2, found {new_version!r}")

    root = repository_root()
    current_version = read_current_version(root)

    if arguments.check:
        if current_version != new_version:
            fail(f"VERSION is {current_version}, expected {new_version}")
        for surface in VERSION_SURFACES:
            synchronized_content(surface, root, current_version)
        print(f"ADBuddy release version is synchronized at {new_version}")
        return

    if new_version == current_version:
        fail(f"VERSION is already {new_version}; use --check to validate it")

    for surface in VERSION_SURFACES:
        synchronized_content(surface, root, current_version)

    (root / "VERSION").write_text(f"{new_version}\n", encoding="utf-8")
    changed_paths = ["VERSION"]
    for surface in VERSION_SURFACES:
        if update_surface(surface, root, current_version, new_version):
            if surface.relative_path not in changed_paths:
                changed_paths.append(surface.relative_path)

    print(f"Bumped ADBuddy release version from {current_version} to {new_version}")
    for relative_path in changed_paths:
        print(f"updated {relative_path}")


if __name__ == "__main__":
    main()
