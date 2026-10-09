# Bundled emulator helper

[bundled-dependencies.json](../../bundled-dependencies.json) is the source of truth
for the helper and Node versions, archive locations, download URLs, checksums and
helper provenance. A copy ships in `Contents/Resources/Emulator` for inspection.

ADBuddy vendors the unmodified published emulator npm archive named by the
manifest. Packaging checks its SHA-256; npm SHA-512 integrity was verified on
import. The manifest records the upstream source repository and commit.
The helper supports protocol 1 and catalog.profiles/catalog.images. It uses only
Node built-ins and relative modules, with no npm production runtime dependencies.
The archive includes Apache-2.0 LICENSE, NOTICE and upstream provenance.
TypeScript and @types/node are build-only dependencies and excluded from the app.

Normal packaging uses these exact archived bytes without npm or a local helper
checkout. To verify source tests, check out the source commit in the manifest, run `npm ci`
against its lockfile, then `npm run build` and `npm test` with Node 24+. The npm
release archive is the pin; no custom version rewrite or local repack is required.
Update the pin only after contract tests and packaged runtime verification.

`scripts/prepare_emulator_backend.sh` downloads the official Node.js macOS
arm64/x64 archives specified in the manifest and validates their pinned SHA-256
values, and copies only the
runtime and complete LICENSE (including third-party notices). No npm executable,
SDK tool, system image, or Java is bundled. Single-architecture apps include
one Node executable; universal apps include both and select the native slice.
Node is signed before the app with Hardened Runtime, allow-jit and unsigned-executable-memory for V8 (the Intel runtime requires the latter).
The entitlement belongs only to Node, not the GUI or MCP executable.

To update a dependency, change its manifest entry, vendor the matching helper
archive when applicable, and verify upstream integrity and license notices.
Run the packaged-runtime tests documented in [development.md](../../docs/development.md).
Tests compare both running versions with the manifest and check that its bundled
copy matches the repository file. Scripts and tests do not carry separate pins.
