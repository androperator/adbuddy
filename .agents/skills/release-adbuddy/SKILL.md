---
name: release-adbuddy
description: Prepare, publish, or resume an ADBuddy release end to end, including version synchronization, authored notes, signed macOS archives, and GitHub verification. Also handles version-only bumps and explicitly scoped packaging or upload requests.
---

# ADBuddy releases

`VERSION` is the release version source of truth. The packaging scripts use it
for app bundle metadata and archive names. The MCP server and current release
examples must remain synchronized. Read [docs/release.md](../../../docs/release.md)
for signing, notarization, and distribution requirements.

## Choose the scope

- A version-bump request runs **Version bump** only.
- A request to release or publish version X runs **Release end to end**, including
  version preparation when necessary. A request to resume an authorized release
  continues that same version and scope.
- For packaging, tag-only, or asset-upload requests, perform the necessary
  prerequisites and stop at the requested stage. Packaging alone does not
  authorize pushing a tag or publishing a GitHub Release.
- Do not update the Homebrew tap or advance to the next development version
  unless explicitly requested. ADBuddy has one version source, with no separate
  published-version follow-up.

Use the version and release commit already selected by the user. For publication,
require a stable bare `major.minor.patch` version, such as `0.2.2`. Ask only if the
intended version or source commit remains ambiguous; do not infer a new version
on resume.

## Version bump

1. Inspect `git status --short` and preserve unrelated changes. If `VERSION`
   already matches the target, run the helper with `--check` instead of bumping
   again. Verify the synchronized files are committed; matching working files
   alone do not complete this stage.
2. Otherwise run:

   ```bash
   python3 .agents/skills/release-adbuddy/scripts/set_release_version.py <new-version>
   ```

   The helper validates the current synchronized version and updates only
   `VERSION`, MCP `serverInfo`, current release-document examples, and the
   packaging-script version example. If synchronization is inconsistent, inspect
   and repair the affected version fields before retrying; preserve other edits.
3. Review changed files, run `git diff --check`, and run `scripts/test.sh` when
   version fields changed. Stage only the version changes and commit separately:

   ```text
   chore(release): bump version to <new-version>
   ```

The helper does not commit, tag, or publish. If the target is already committed
and synchronized, do not create an empty or duplicate version commit.

## Release end to end

### Establish state and resume

Inspect the worktree, committed version surfaces, target changelog entry, prior
validation evidence, local archives, local and remote `v<version>` tags, and the
GitHub Release. Use the configured repository, not a hard-coded owner.
Read-only checks include `git ls-remote --tags origin` and:

```bash
gh release view v<version> --json tagName,name,body,isDraft,isPrerelease,isImmutable,assets,url
```

A network or authentication error does not prove that a tag or release is absent.
Resolve it before publication. Compare tag targets as peeled commit SHAs, not
annotated tag object IDs or GitHub's `targetCommitish` branch name.

Resume at the first incomplete stage below. Recheck dependencies before skipping
a stage. Record the release commit, completed checks, artifact SHA-256 values,
and remote state in progress updates so a later run can verify them. Never infer
completion from a filename or an earlier claim alone.

| Stage | Evidence required to skip it |
|---|---|
| Version | Target version and all synchronized surfaces are committed and pass the helper's `--check`. |
| Notes | Exactly one complete target entry can be extracted from the intended commit and covers the release range. |
| Validation and packaging | Passing checks and all four public archives are tied to the exact release commit, with recorded hashes and signing/notarization verification. |
| Tag | The local and remote tag, where present, resolve to the validated release commit. Push only if the remote tag is absent. |
| GitHub Release | The release uses that tag and authored body; all four assets are present and their downloaded bytes match the validated hashes. |

If an existing release or tag identifies another commit, stop and report the
conflict. Never move or delete a release tag. If resuming a tagged release, use
its exact commit for any necessary local validation or rebuilding; do not bump
the current branch back to an older version. If the published release already
passes all checks, report completion without rebuilding or republishing.

### Complete the remaining stages

1. **Prepare the version.** Run **Version bump** when needed, then validate with:

   ```bash
   python3 .agents/skills/release-adbuddy/scripts/set_release_version.py <version> --check
   ```

2. **Author release notes.** Select the previous published release tag that is
   an ancestor of the intended release commit. If the target entry is absent or
   incomplete, use [release-notes-author](../release-notes-author/SKILL.md) with
   that tag and the intended end ref, review the entry, and commit it. Reuse a
   complete entry. After all preparation commits, record the exact clean release
   commit and extract its body:

   ```bash
   python3 .agents/skills/release-notes-author/scripts/extract_release_notes.py <version> <commit> > /tmp/adbuddy-release-notes.md
   ```

   Stop if extraction fails. If the user selected an immutable commit that lacks
   preparation, explain that a new release commit is needed before tagging.

3. **Validate and package.** Run `scripts/test.sh` on the clean release commit
   unless passing results for that exact commit are already established. Build
   the public artifacts with notarization:

   ```bash
   ADBUDDY_NOTARY_PROFILE="<Keychain profile>" scripts/package_release.sh
   ```

   Do not use `--local` or `--skip-notarization` for publication. The script
   builds both architectures and the universal app, notarizes and staples each,
   verifies signatures and Gatekeeper acceptance, and prints archive hashes.
   Keep all four matching assets:
   `dist/release/ADBuddy-macos-<architecture>-<version>.zip`, where architecture
   is `arm64`, `x86_64`, or `universal`, plus
   `dist/release/ADBuddy-recording-sources-<version>.zip`.
   Reuse archives only with evidence linking their hashes and successful public
   packaging to this commit; otherwise rebuild before any upload. Record the
   hashes and preserve the verified archives for interrupted uploads.

4. **Create or finish pushing the tag.** Recheck remote state immediately before
   mutation. If the local tag is absent, create it at the validated commit:

   ```bash
   git tag -a v<version> <commit> -m "Release v<version>"
   ```

   Reuse a matching existing tag. If the remote tag is absent, push that tag only:

   ```bash
   git push origin refs/tags/v<version>
   ```

5. **Create or finish the GitHub Release.** If absent, create it with the existing
   remote tag and all four verified archives:

   ```bash
   gh release create v<version> dist/release/ADBuddy-macos-universal-<version>.zip \
     dist/release/ADBuddy-macos-arm64-<version>.zip \
     dist/release/ADBuddy-macos-x86_64-<version>.zip \
     dist/release/ADBuddy-recording-sources-<version>.zip \
     --verify-tag --title "ADBuddy <version>" \
     --notes-file /tmp/adbuddy-release-notes.md
   ```

   On resume, inspect an existing release before mutation. If its tag and body
   match, use `gh release upload v<version> <missing-assets...>` for missing
   assets only, after checking the existing assets against the recorded hashes.
   Do not use `--clobber`, replace existing assets, or rewrite published notes.
   An explicit request to resume publication authorizes completing these missing
   uploads. Publish a matching draft only after verifying all four assets, using
   `gh release edit v<version> --draft=false --verify-tag`.
   Conflicting notes, mismatched assets, or an immutable incomplete release need
   explicit repair direction; report the exact state and stop.

6. **Verify publication.** Inspect the live release and confirm the tag commit,
   authored body, non-draft/non-prerelease status, and all four asset names.
   Download the assets to a temporary directory and compare SHA-256 values with
   the verified local archives or recorded release hashes. Report the release
   URL, commit, hashes, and any runtime checks not performed. Public completion
   requires these checks; failed or incomplete uploads are not a completed
   release. Clean-machine and native Intel runtime checks remain separate from
   packaging verification as described in `docs/release.md`.

If any external step fails, inspect its resulting state and report the first
incomplete stage. Preserve successful prior stages. Continue only within the
existing authorization; a later resume request can finish the same release
without recreating its tag or repeating completed work. Do not push preparation
branch commits or modify the separate Homebrew tap unless explicitly requested.
