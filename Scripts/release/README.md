# Release pipeline

Capsule ships as a **Developer ID–signed, notarized, stapled** `.app`, distributed as a DMG
for humans and a zip for Sparkle auto-updates. The Mac App Store is out of scope (the app is
unsandboxed to drive the `container` CLI).

## How updates reach users

1. Tagging `vX.Y.Z` runs [`.github/workflows/release.yml`](../../.github/workflows/release.yml)
   on `capsule-native/capsule`: build → Developer-ID sign → notarize → staple → package →
   **sign the appcast**.
2. The workflow publishes a **GitHub Release** with `Capsule-<v>.dmg`, `Capsule-<v>.zip`, and
   `appcast.xml`. The appcast's `<enclosure>` URLs point at that release's own asset download
   URLs (via `--download-url-prefix`, set from the tag).
3. A **Sync appcast** workflow in the Pages repo
   [`capsule-native/capsule-native.github.io`](https://github.com/capsule-native/capsule-native.github.io)
   pulls the latest release's `appcast.xml` and commits it, republishing the feed at
   **<https://capsule-native.github.io/appcast.xml>** — the app's `SUFeedURL`. It runs on a
   schedule (~15 min) and on demand (Actions ▸ Sync appcast ▸ Run workflow) for an instant
   publish right after a release.
4. The release job also **bumps the Homebrew cask**: it recomputes the DMG's SHA-256, renders
   `Casks/capsule.rb` via [`update-homebrew-cask.sh`](update-homebrew-cask.sh), and pushes it to
   [`capsule-native/homebrew-tap`](https://github.com/capsule-native/homebrew-tap) so that
   `brew install --cask capsule-native/tap/capsule` serves the new version. Gated on the
   `HOMEBREW_TAP_TOKEN` secret (a fine-grained PAT with **Contents: read+write** on the tap);
   absent on forks, it's skipped with a warning. `auto_updates true` means *existing* installs are
   updated in place by Sparkle regardless — the bump keeps **fresh** installs current.

> The code repo stays **public** so Sparkle can download the update zip from the release assets
> without authentication.

## Signing

Signed, notarized releases require Developer-ID + notarization credentials held by the
maintainer, plus a Sparkle EdDSA key whose public half is baked into `App/Info.plist`
(`SUPublicEDKey`). These are configured as repository secrets and their setup is intentionally
**not** documented in this public repo. When the signing secrets are absent (a fork, or a PR from
one), the workflow still **builds and validates** the whole pipeline but skips
notarization/publishing — it never fails for want of credentials, so contributors can run it.

> Pipeline behaviour worth knowing: `generate_appcast` writes `sparkle:edSignature` **only when
> the app's embedded `SUPublicEDKey` matches the signing key's public key** — otherwise it emits
> an *unsigned* enclosure with no error, and every client silently rejects the update. Keep the
> Info.plist public key and the signing key in lockstep.

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
| 5 | `appcast.sh` | `make appcast` | Sparkle `generate_appcast` signs the zip (in an isolated dir — the `.dmg` is kept out so Sparkle doesn't reject the same-version pair) + writes `appcast.xml` (with `RELEASE_DOWNLOAD_URL_PREFIX`), then **fails if any enclosure is unsigned** |

## Environment (local runs)

| Var | Required | Meaning |
| --- | --- | --- |
| `TEAM_ID` | signed runs | Apple Developer Team ID |
| `NOTARY_PROFILE` | signed runs | `notarytool` keychain profile name |
| `RELEASE_DOWNLOAD_URL_PREFIX` | CI-set | prepended to the appcast's enclosure filenames — the tag's release-download URL. Empty → filenames stay relative to the appcast. |
| `SPARKLE_BIN` | optional | dir containing `generate_appcast` / `generate_keys`. If unset, `appcast.sh` searches `.build/artifacts`, `DerivedData/SourcePackages/artifacts`, and the global Xcode DerivedData (where `xcodebuild archive` resolves Sparkle), then `PATH`. |
| `SPARKLE_ED_KEY_FILE` | optional | private-key file; else the login keychain |
| `SPARKLE_ACCOUNT` | optional | keychain account for the private key when `SPARKLE_ED_KEY_FILE` is unset (this repo's key was generated under `capsule-native`; without it a local run signs with the wrong/default account → unsigned enclosures) |
| `DIST_DIR` | optional | output dir (default `dist/`) |

## Cutting a release

1. Bump `CFBundleShortVersionString` **and** `CFBundleVersion` in `App/Info.plist`; commit + push.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`. The tag `vX.Y.Z` **must** match the Info.plist
   version — the workflow's *Verify tag matches app version* step fails the build otherwise (no
   more `v1.2.3` tags that package `Capsule-0.1.0.zip`).
3. The workflow builds, signs, notarizes, and publishes the Release. The Pages repo picks up the
   new appcast automatically within ~15 min, or immediately if you run **Sync appcast** there.

## Notes

- **Version comes from the app, not the tag.** Artifact names and the Sparkle appcast use
  `CFBundleShortVersionString` from `App/Info.plist`; the tag guard just enforces they agree.
- **Unsigned appcasts can't ship.** If the signing key's public half doesn't match the app's
  `SUPublicEDKey`, `generate_appcast` only *warns* and writes an enclosure with no
  `sparkle:edSignature` (every client then rejects the update). `appcast.sh` now **fails the
  build** unless every enclosure is signed, so this can't slip out silently.
- **Sparkle key secret is encoding-agnostic.** `release.yml` accepts `SPARKLE_ED_PRIVATE_KEY`
  whether it was stored as Sparkle's raw base64 key string or base64-encoded once more, and
  writes the correct `--ed-key-file` either way.
- **`generate_appcast` discovery on CI.** The clean runner has no `.build/`; the tool is resolved
  into DerivedData by the `xcodebuild archive` step (and a `swift package resolve` step warms
  `.build/artifacts`), and `appcast.sh` searches both — so the appcast step no longer dies for
  want of the binary.
- **Notary password on argv.** `notarize.sh` / `release.yml` pass the app-specific password to
  `notarytool store-credentials --password` (the API has no stdin form). It's masked and never
  echoed; on the ephemeral, single-tenant `macos-26` runner nothing else can read the process
  table. Don't port this workflow to a shared/self-hosted runner without switching to a notary
  API key.

## Why archive→export instead of `codesign --deep`

`xcodebuild -exportArchive` signs embedded code inside-out — including Sparkle's nested
`Autoupdate`, `Updater.app`, and XPC services — with the Hardened Runtime and a secure
timestamp, which is what the notary service demands. `codesign --deep` is discouraged by Apple
and easy to get subtly wrong for a framework with nested helpers.
