---
name: release-adbuddy
description: Update ADBuddy's release version, or package and publish its signed macOS ZIP to a matching GitHub Release tag. Use for ADBuddy version bumps, release archives, tags, and binary uploads, not for general Swift package changes.
---

# ADBuddy releases

`VERSION` is the release version source of truth. The packaging scripts use it
for the app bundle metadata and archive name. The MCP server and current
release-document examples are intentionally versioned surfaces that must remain
in sync.

Use a bare semantic version such as `0.1.2`, never a `v`-prefixed tag name.

## Choose the scope

- For a request to bump the version, follow **Version bump** only. Do not
  package, notarize, tag, push, create a GitHub Release, or update the Homebrew
  tap.
- Follow **Package and publish** only when the user explicitly asks to create
  or publish a release, tag it, or upload the binary. A prior version-bump
  request does not authorize these external actions.

Read `docs/release.md` before packaging or publishing. It defines the signing,
notarization, and distribution requirements.

## Version bump

1. Inspect `git status --short` and preserve any unrelated worktree changes.
2. Run:

   ```bash
   python3 .agents/skills/release-adbuddy/scripts/set_release_version.py <new-version>
   ```

   The helper validates the current synchronized version and updates only:
   `VERSION`, the MCP `serverInfo` version, the versioned release-document
   examples, and the packaging-script version example.
3. Review the diff and run `git diff --check` followed by `swift test`.
4. Stage only the version-bump files and create a dedicated commit:

   ```text
   chore(release): bump version to <new-version>
   ```

The helper does not create a commit, tag, or release. To confirm the repository
is synchronized without editing it, run the helper with `--check`.

## Package and publish

Use this flow only after the release-version commit exists and the user has
explicitly authorized publication.

1. Confirm `VERSION` matches the requested version, the worktree is clean, and
   the target commit is the one intended for the release. Run `swift test`.
2. Before packaging, ensure the intended release commit contains exactly one
   `CHANGELOG.md` entry for `VERSION`. If absent, use
   [release-notes-author](../release-notes-author/SKILL.md) with the previous
   published tag and the intended end ref, review the entry, and commit it.
   Reconfirm the clean release commit, then extract the body before tagging:

   ```bash
   python3 .agents/skills/release-notes-author/scripts/extract_release_notes.py <version> <commit> > /tmp/adbuddy-release-notes.md
   ```

   Stop if extraction fails. Use this exact body for the GitHub Release.

3. Build the public artifact with notarization. Do not use
   `--skip-notarization` for a distributable binary:

   ```bash
   ADBUDDY_NOTARY_PROFILE="<Keychain profile>" scripts/package_release.sh
   ```

   The app archives are `dist/release/ADBuddy-macos-<architecture>-<version>.zip`,
   where architecture is `arm64`, `x86_64`, or `universal`. The matching sources are
   in `dist/release/ADBuddy-recording-sources-<version>.zip`. Publish all four assets
   together and keep them available; the app links to that source archive.
4. Before changing remote state, confirm that `v<version>` is absent locally
   and on `origin`, and that `gh release view v<version>` reports no GitHub
   Release. Do not force-move or reuse a tag that points at a different commit.
5. Create an annotated tag at the validated release commit, push that tag only,
   then upload the three notarized app ZIPs and source ZIP to its GitHub Release:

   ```bash
   git tag -a v<version> <commit> -m "Release v<version>"
   git push origin refs/tags/v<version>
   gh release create v<version> dist/release/ADBuddy-macos-universal-<version>.zip \
     dist/release/ADBuddy-macos-arm64-<version>.zip \
     dist/release/ADBuddy-macos-x86_64-<version>.zip \
     dist/release/ADBuddy-recording-sources-<version>.zip \
     --title "ADBuddy <version>" \
     --notes-file /tmp/adbuddy-release-notes.md
   ```

6. Record the GitHub Release URL and archive SHA-256. Do not modify the
   separate Homebrew tap unless the user explicitly includes it in the request.

If the tag push succeeds but release creation or asset upload fails, do not
move, delete, or recreate the tag. Report the exact state and wait for explicit
direction to repair the release attached to that existing tag.
