# Release pipeline

Capsule ships as a **Developer ID–signed, notarized, stapled** `.app`, distributed as a DMG
for humans and a zip for Sparkle auto-updates. The Mac App Store is out of scope (the app is
unsandboxed to drive the `container` CLI).

## One-time setup

1. **Developer ID** — a “Developer ID Application” certificate in your login keychain, and your
   Team ID.
2. **Notary credentials** — store them once as a keychain profile:
   ```sh
   xcrun notarytool store-credentials capsule-notary \
     --apple-id you@example.com --team-id ABCDE12345 \
     --password <app-specific-password>
   ```
3. **Sparkle signing keys** — generate the EdDSA key pair once:
   ```sh
   # generate_keys ships with Sparkle (find it under .build/artifacts or set $SPARKLE_BIN)
   ./generate_keys
   ```
   Paste the printed **public** key into `App/Info.plist` → `SUPublicEDKey`. The **private** key
   stays in your keychain and never enters the repo.

## Environment

| Var | Required | Meaning |
| --- | --- | --- |
| `TEAM_ID` | yes | Apple Developer Team ID |
| `NOTARY_PROFILE` | yes | notarytool keychain profile name (e.g. `capsule-notary`) |
| `DEVELOPER_ID_APP` | optional | explicit signing identity string |
| `SPARKLE_BIN` | optional | dir containing `generate_appcast` / `generate_keys` |
| `SPARKLE_ED_KEY_FILE` | optional | private-key file, if not using the keychain |
| `DIST_DIR` | optional | output dir (default `dist/`) |

## Run it

```sh
make release              # full pipeline (or: Scripts/release/release.sh)
make release-dry          # print the plan without signing anything (no creds needed)
```

Individual steps (each accepts `--dry-run`):

| Step | Script | Make target | Does |
| --- | --- | --- | --- |
| 1 | `build.sh` | `make archive` | XcodeGen + `xcodebuild archive` (Release) → `dist/Capsule.xcarchive` |
| 2 | `export.sh` | `make export` | `xcodebuild -exportArchive` (Developer ID) → signed `dist/Capsule.app` (inside-out, incl. Sparkle; Hardened Runtime) |
| 3 | `notarize.sh` | `make notarize` | zip + `notarytool submit --wait` + `stapler staple` |
| 4 | `package.sh` | `make package` | `dist/Capsule-<v>.zip` (Sparkle) + `dist/Capsule-<v>.dmg` |
| 5 | `appcast.sh` | `make appcast` | Sparkle `generate_appcast` signs the zip + writes `appcast.xml` |

## CI

`.github/workflows/release.yml` runs the same pipeline on a `v*` tag, importing the Developer
ID cert + notary creds from repository secrets, then publishes the artifacts and `appcast.xml`.
The signing/notarization steps are skipped automatically when the secrets are absent (e.g. on a
fork), so the workflow never fails for want of credentials.

## Why archive→export instead of `codesign --deep`

`xcodebuild -exportArchive` signs embedded code inside-out — including Sparkle’s nested
`Autoupdate`, `Updater.app`, and XPC services — with the Hardened Runtime and a secure
timestamp, which is what the notary service demands. `codesign --deep` is discouraged by Apple
and easy to get subtly wrong for a framework with nested helpers.
