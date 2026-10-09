# Release strategy

## Distribution

ADBuddy is distributed through
[GitHub Releases](https://github.com/clawperator/adbuddy/releases), with app ZIPs
for Apple Silicon (`arm64`), Intel (`x86_64`), and both architectures (universal).
Choose the ZIP for your Mac, extract it, then move `ADBuddy.app` to Applications.
The universal ZIP runs on either architecture but is a larger download.

A Clawperator-maintained Homebrew cask remains a planned distribution channel.
The proposed command, once that cask is published, is:

```sh
brew install --cask clawperator/tap/adbuddy
```

Use the bundle identifier `com.clawperator.adbuddy`. The supported target is
macOS 14 or newer on Apple silicon and Intel Macs.

## Release artifact

The release build creates separate `arm64` and `x86_64` apps, plus a universal
app containing both slices. Each app includes the `adbuddy-mcp` stdio helper in
`Contents/MacOS` alongside the GUI executable. Package it in a versioned archive
such as:

```text
ADBuddy-macos-universal-0.2.1.zip
```

The smaller downloads use `ADBuddy-macos-arm64-<version>.zip` and
`ADBuddy-macos-x86_64-<version>.zip`. Each contains only its matching recorder
helper and Android server resources.

Every app also includes the pinned emulator helper and Node.js 24.21.0.
Single-architecture apps contain the matching Node runtime; universal apps
contain both runtimes and choose the native architecture. The shared JavaScript
helper is `0.2.0`, the published npm package pinned by archive checksum. Packaging verifies helper and Node checksums, signs each Node executable
with Hardened Runtime and the V8 allow-jit and unsigned-executable-memory entitlements before signing the app,
and includes the helper LICENSE/NOTICE and full Node third-party license text.
The GUI does not receive Node's entitlement. SDK tools, images and Java stay
external. See [bundle provenance and rebuild instructions](../vendor/emulator/README.md).

Do not treat an ad-hoc signed developer build as a public release. Public
artifacts require a Developer ID Application identity, Hardened Runtime,
notarization, and stapling.

The package also includes architecture-specific scrcpy recording helpers and
matching Android server resources. The release script verifies pinned checksums,
signs the included helpers, and keeps third-party license texts and a source
download link inside the app. Matching sources and rebuild scripts go in the separate
`ADBuddy-recording-sources-<version>.zip`. Publish all three app ZIPs and the
source ZIP on the same release and keep them available. See [recording-backend.md](recording-backend.md).

## Packaging command

`VERSION` is the source of truth for the release version. Use the repository
release helper to synchronize the MCP version, document examples, and packaging
example, then commit the version change before packaging. The current version is
`0.2.1`.

`scripts/package_release.sh` creates all three application bundles and
versioned app ZIPs, plus one shared recording-source ZIP. It defaults to the
Action Launcher Developer ID identity and accepts an override through `AD_BUDDY_SIGNING_IDENTITY` when necessary.

Before using the command for a public artifact, configure a notarization
credential as a Keychain profile outside the repository. Do not place
credentials or App Store Connect keys in environment files, scripts, or shell
history. Then run:

```sh
ADBUDDY_NOTARY_PROFILE="Action Launcher Notarization" \
  scripts/package_release.sh
```

For local signing validation only, the command can omit notarization:

```sh
scripts/package_release.sh --skip-notarization
```

To measure or test all three builds without a Developer ID certificate:

```sh
scripts/package_release.sh --local
```

This ad-hoc signs the app and skips notarization. Neither `--local` nor
`--skip-notarization` produces a public release artifact.

## Release flow

1. Follow the version-bump procedure in the repository
   [release skill](../.agents/skills/release-adbuddy/SKILL.md).
2. Run `scripts/test.sh` on the host and build both release architectures.
   A universal build does not itself prove runtime behavior on both Mac types.
3. Package the `.app` with its `Info.plist`, icon, and resources.
4. Sign all bundled code with Developer ID and Hardened Runtime enabled.
5. Submit the ZIP to Apple's notarization service, wait for acceptance, and
   staple the notarization ticket to the app.
6. Verify the artifact with `codesign`, `spctl`, and `stapler`.
7. With explicit publication authorization, tag the validated release commit
   and upload all three final app ZIPs and the matching recording-source ZIP with
   release notes to GitHub Releases. Follow the
   release skill for tag and upload recovery rules.
8. If a Homebrew tap update is explicitly requested, publish or update its cask
   URL, version, and SHA-256 after the matching asset exists.
9. Validate the published ZIP on a clean test machine or user profile. Validate
   cask installation separately when that distribution channel is available.

Typical final checks include:

```sh
codesign --verify --deep --strict --verbose ADBuddy.app
spctl --assess --type execute --verbose ADBuddy.app
stapler validate ADBuddy.app
```

Use `ditto` when extracting release ZIPs during validation to avoid introducing
AppleDouble files that can invalidate a signed bundle.

## Planned Homebrew cask

The cask should point at the immutable GitHub Release ZIP and declare the app
bundle, macOS minimum version, homepage, and app data cleanup paths. A minimal
future shape is:

```ruby
cask "adbuddy" do
  version "0.2.1"
  sha256 "<release-sha256>"

  url "https://github.com/clawperator/adbuddy/releases/download/v#{version}/ADBuddy-macos-universal-#{version}.zip"
  name "ADBuddy"
  desc "Native menu bar utility for Android developer tasks"
  homepage "https://clawperator.com/"

  depends_on macos: :sonoma
  app "ADBuddy.app"
end
```

Do not publish this cask until its matching release asset and SHA-256 exist.

## Updates

Direct-download installations use manual replacement with a newer release.
Once Homebrew distribution is available, its installations should use
`brew upgrade --cask`. There is no in-app updater. Do not add Sparkle yet:
it adds a dependency and a second update channel before the core product is
proven.

If an in-app updater is later added for direct downloads, it must be disabled
for Homebrew installations so users do not receive conflicting update paths.

## Credentials and secrets

Developer ID signing certificates, notarization credentials, and App Store
Connect API keys are release secrets. Keep them out of the repository, app
bundle, logs, shell history, and issue trackers. Do not add publishing
automation or change release credentials without an explicit request.
