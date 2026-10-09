# Bundled emulator helper

ADBuddy vendors the unmodified published `@androperator/emulator@0.2.0` archive:
https://registry.npmjs.org/@androperator/emulator/-/emulator-0.2.0.tgz

SHA-256 (checked by packaging):
`eaa2f002b3d658acd3ffa99ba054e8be470588eface47a1586f946e95c36f2c9`

npm registry SHA-512 integrity (verified on import):
`sha512-bXcZJfsVg3eMx4TeOsGNdqPr67uyo28RZmas/6rsL6mmxwZ4l7Hbm2NALf+JlJbjtx+ssGVIcv4g0HSDnsnSsw==`

The registry provenance records source commit
`56281ab7e560ad5bb57e3130a2cdca22d4de5a40` at tag `v0.2.0` in
https://github.com/androperator/androperator-emulator.
The helper supports protocol 1 and catalog.profiles/catalog.images. It uses only
Node built-ins and relative modules, with no npm production runtime dependencies.
The archive includes Apache-2.0 LICENSE, NOTICE and upstream provenance.
TypeScript and @types/node are build-only dependencies and excluded from the app.

Normal packaging uses these exact archived bytes without npm or a local helper
checkout. To verify source tests, check out the source commit above, run `npm ci`
against its lockfile, then `npm run build` and `npm test` with Node 24+. The npm
release archive is the pin; no custom version rewrite or local repack is required.
Update the pin only after contract tests and packaged runtime verification.

`scripts/prepare_emulator_backend.sh` downloads official Node.js 24.21.0 macOS
arm64/x64 archives from https://nodejs.org/dist/v24.21.0/, validates their
SHA-256 values against pinned upstream SHASUMS256 entries, and copies only the
runtime and complete LICENSE (including third-party notices). No npm executable,
SDK tool, system image, or Java is bundled. Single-architecture apps include
one Node executable; universal apps include both and select the native slice.
Node is signed before the app with Hardened Runtime, allow-jit and unsigned-executable-memory for V8 (the Intel runtime requires the latter).
The entitlement belongs only to Node, not the GUI or MCP executable.
