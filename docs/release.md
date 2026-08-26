# Release strategy

## Distribution goal

ADBuddy will ship as a non-Mac-App-Store application. The initial public
distribution channels are:

1. a signed, notarized universal app ZIP attached to a GitHub Release;
2. a Homebrew cask in a Clawperator-maintained tap.

The intended installation command is:

```sh
brew install --cask clawperator/tap/adbuddy
```

Use the bundle identifier `com.clawperator.adbuddy`. The initial target is
macOS 14 or newer on Apple silicon and Intel Macs.

## Release artifact

The release build should create a universal `ADBuddy.app` containing `arm64`
and `x86_64` slices. It must include the `adbuddy-mcp` stdio helper in
`Contents/MacOS` alongside the GUI executable. Package it in a versioned archive
such as:

```text
ADBuddy-macos-universal-0.1.1.zip
```

Do not treat an ad-hoc signed developer build as a public release. Public
artifacts require a Developer ID Application identity, Hardened Runtime,
notarization, and stapling.

## Packaging command

`VERSION` is the source of truth for the release version. Update it before a
release, then commit that change with the release notes. The current version is
`0.1.1`.

`scripts/package_release.sh` creates the universal application bundle and
versioned ZIP archive. It defaults to the Action Launcher Developer ID identity
and accepts an override through `AD_BUDDY_SIGNING_IDENTITY` when necessary.

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

An archive created with `--skip-notarization` is not a public release artifact.

## Initial release flow

1. Update the app version and user-facing changelog.
2. Build and test both architectures.
3. Package the `.app` with its `Info.plist`, icon, and resources.
4. Sign all bundled code with Developer ID and Hardened Runtime enabled.
5. Submit the ZIP to Apple's notarization service, wait for acceptance, and
   staple the notarization ticket to the app.
6. Verify the artifact with `codesign`, `spctl`, and `stapler`.
7. Upload the final ZIP and release notes to GitHub Releases.
8. Update the cask URL, version, and SHA-256 in the tap.
9. Install the cask on a clean test machine or user profile and launch the app.

Typical final checks include:

```sh
codesign --verify --deep --strict --verbose ADBuddy.app
spctl --assess --type execute --verbose ADBuddy.app
stapler validate ADBuddy.app
```

Use `ditto` when extracting release ZIPs during validation to avoid introducing
AppleDouble files that can invalidate a signed bundle.

## Homebrew cask

The cask should point at the immutable GitHub Release ZIP and declare the app
bundle, macOS minimum version, homepage, and app data cleanup paths. A minimal
future shape is:

```ruby
cask "adbuddy" do
  version "0.1.1"
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

Version 0.1 should rely on `brew upgrade --cask` for cask installations and
manual replacement for direct-download installations. Do not add Sparkle yet:
it adds a dependency and a second update channel before the core product is
proven.

If an in-app updater is later added for direct downloads, it must be disabled
for Homebrew installations so users do not receive conflicting update paths.

## Credentials and secrets

Developer ID signing certificates, notarization credentials, and App Store
Connect API keys are release secrets. Keep them out of the repository, app
bundle, logs, shell history, and issue trackers. Do not add publishing
automation until the local signed-and-notarized flow has been proven.
