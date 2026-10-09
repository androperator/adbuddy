#!/usr/bin/env python3
"""Offline integration checks using temporary Git history and a fake GitHub CLI."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

SCRIPTS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("extract", SCRIPTS / "extract_release_notes.py")
extract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extract)


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release-test@example.com")
        self.git("config", "commit.gpgsign", "false")
        self.commit("baseline", "README.md")
        self.git("tag", "v0.1.0")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True).strip()

    def commit(self, subject, path, text="fixture\n"):
        file = self.repo / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)
        self.git("add", path)
        self.git("commit", "-qm", subject)
        return self.git("rev-parse", "HEAD")

    def gather(self, script="gather_commits.sh", start="v0.1.0", end="HEAD", env=None, success=True):
        result = subprocess.run(["bash", str(SCRIPTS / script), start, end], cwd=self.repo,
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result.stdout

    def test_classification_and_deleted_source(self):
        cases = [
            ("feat: app (#1)", "Sources/ADBuddy/Views/View.swift", "keep", "app"),
            ("fix: shared", "Sources/ADBuddyCore/Device.swift", "keep", "app mcp"),
            ("feat: tool", "Sources/ADBuddyMCP/Server.swift", "keep", "mcp"),
            ("docs: usage", "docs/mcp.md", "keep", "docs"),
            ("chore: helper", "vendor/emulator/manifest.json", "keep", "app"),
            ("test: fixture", "Tests/ADBuddyTests/Test.swift", "drop:infra", None),
            ("chore: scripts", "scripts/tool.sh", "drop:infra", None),
            ("chore: config", "Package.swift", "drop:no-src", "app"),
            ("chore(release): bump version to 0.2.0", "Sources/ADBuddyMCP/Server.swift", "drop:infra", "mcp"),
        ]
        for subject, path, classification, surface in cases:
            self.commit(subject, path, subject)
            self.git("tag", "end")
            output = self.gather(end="end")
            block = output.split("=== COMMIT ")[-1]
            self.assertIn("CLASSIFICATION: " + classification, block)
            if surface:
                self.assertIn("SURFACES: " + surface + "\n", block)
            self.git("tag", "-d", "end")
        self.git("rm", "Sources/ADBuddy/Views/View.swift")
        self.git("commit", "-qm", "refactor: remove view")
        block = self.gather().split("=== COMMIT ")[-1]
        self.assertIn("CLASSIFICATION: keep", block)
        self.assertIn("[deleted][src]", block)

    def test_release_date_uses_tag_date_or_build_commit_date(self):
        commit = self.commit("feat: build", "Sources/ADBuddy/App.swift")
        env = dict(os.environ, GIT_COMMITTER_DATE="2026-09-15T12:00:00+0000")
        subprocess.check_call(["git", "tag", "-a", "release", "-m", "Release"], cwd=self.repo, env=env)
        self.assertEqual(self.gather(end="release").splitlines()[0], "RELEASE_DATE: 2026-09-15")
        date = self.git("log", "-1", "--format=%cs", commit)
        self.assertEqual(self.gather(end=commit).splitlines()[0], "RELEASE_DATE: " + date)

    def test_invalid_and_reversed_ranges(self):
        self.commit("feat: update", "Sources/ADBuddy/App.swift")
        self.git("tag", "later")
        self.gather(start="missing", success=False)
        self.gather(end="missing", success=False)
        self.gather(start="later", end="v0.1.0", success=False)
        self.assertNotIn("=== COMMIT", self.gather(end="v0.1.0"))

    def test_pr_order_deduplication_and_empty_range(self):
        first = self.commit("feat: one", "Sources/ADBuddy/One.swift")
        second = self.commit("feat: two", "Sources/ADBuddy/Two.swift")
        third = self.commit("fix: follow-up", "Sources/ADBuddy/Three.swift")
        fake = self.repo / "bin"
        fake.mkdir()
        gh = fake / "gh"
        gh.write_text(f'''#!/usr/bin/env bash
set -eu
case "$1 $2" in
  "repo view") printf 'clawperator/adbuddy\\n' ;;
  "pr list") printf '{second}\\t7\\n{third}\\t42\\n{first}\\t42\\n' ;;
  "pr view") printf 'Title %s\\thttps://example.com/pull/%s\\n' "$3" "$3" ;;
  *) exit 1 ;;
esac
''')
        gh.chmod(0o755)
        env = dict(os.environ, PATH=str(fake) + os.pathsep + os.environ["PATH"])
        output = self.gather("gather_prs.sh", env=env)
        self.assertEqual(output, "Pull requests:\n- [Title 42](https://example.com/pull/42)\n- [Title 7](https://example.com/pull/7)\n")
        self.assertEqual(self.gather("gather_prs.sh", end="v0.1.0", env=env), "Pull requests:\nNone found\n")
        self.gather("gather_prs.sh", start="missing", env=env, success=False)

    def test_extract_one_block_and_reject_missing_duplicate_empty(self):
        entry = "## [0.2.0] - 2026-10-10\n\nAdded capture.\n\nPull requests:\nNone found\n"
        content = "# Changelog\n\n## [Unreleased]\n\nPending.\n\n" + entry + "\n## [0.1.0] - 2026-09-01\n\nOld.\n"
        self.assertEqual(extract.extract_entry(content, "0.2.0"), entry)
        for version, text in [("0.3.0", content), ("0.2.0", entry + entry),
                              ("v0.2.0", content), ("0.2.0", "## [0.2.0] - 2026-10-10\n")]:
            with self.assertRaises(ValueError):
                extract.extract_entry(text, version)
        commit = self.commit("docs: notes", "CHANGELOG.md", content)
        (self.repo / "CHANGELOG.md").write_text("uncommitted edits")
        result = subprocess.check_output(["python3", str(SCRIPTS / "extract_release_notes.py"), "0.2.0", commit], cwd=self.repo, text=True)
        self.assertEqual(result, entry)


if __name__ == "__main__":
    unittest.main()
