#!/usr/bin/env python3
"""Extract one authored release entry from an exact Git commit."""
import argparse
import re
import subprocess
import sys


def extract_entry(content: str, version: str) -> str:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("version must be a bare major.minor.patch number")
    headers = list(re.finditer(r"^## \[([^\]\n]+)\][^\n]*$", content, re.MULTILINE))
    matches = [index for index, header in enumerate(headers) if header.group(1) == version]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one CHANGELOG entry for {version}; found {len(matches)}")
    index = matches[0]
    header = headers[index]
    if not re.fullmatch(r"## \[" + re.escape(version) + r"\] - \d{4}-\d{2}-\d{2}", header.group()):
        raise ValueError("release entry must include a YYYY-MM-DD date")
    end = headers[index + 1].start() if index + 1 < len(headers) else len(content)
    entry = content[header.start():end].strip()
    body = content[header.end():end].strip()
    if not body or body == "Pull requests:\nNone found":
        raise ValueError("release entry has no authored summary")
    return entry + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("commit", help="release commit or ref containing CHANGELOG.md")
    args = parser.parse_args()
    try:
        commit = subprocess.check_output(
            ["git", "rev-parse", "--verify", "--end-of-options", args.commit + "^{commit}"], text=True
        ).strip()
        content = subprocess.check_output(["git", "show", commit + ":CHANGELOG.md"], text=True)
        sys.stdout.write(extract_entry(content, args.version))
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}. Author and commit release notes before tagging.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
