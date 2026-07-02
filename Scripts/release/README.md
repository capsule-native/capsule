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

> The code repo must stay **public** so Sparkle can download the update zip from the release
> assets without authentication.

## One-time setup

1. **Developer ID** — a "Developer ID Application" certificate in your login keychain, and your
   Team ID.
2. **Notary credentials** — store them once as a keychain profile:
   ```sh
   xcrun notarytool store-credentials capsule-notary \
     --apple-id you@example.com --team-id ABCDE12345 \
     --password <app-specific-password>
   ```
3. **Sparkle signing key** — already generated under the keychain account `capsule-native`. Its
   public key is baked into `App/Info.plist` (`SUPublicEDKey`) and its private key is the CI
   secret `SPARKLE_ED_PRIVATE_KEY`. A base64 backup is kept off-repo by the maintainer.

   > **Gotcha:** `generate_appcast` signs an update **only when the `.app`'s embedded
   > `SUPublicEDKey` matches the signing key's public key.** If the Info.plist public key and
   > the CI private key aren't a pair, the appcast ships **unsigned with no error** and every
   > client silently rejects the update. Keep them in lockstep when rotating.

## GitHub Actions secrets (`capsule-native/capsule`)

| Secret | For |
| --- | --- |
| `APPLE_TEAM_ID` | signing + notarization |
| `DEVELOPER_ID_CERT_P12_BASE64` | Developer ID Application cert (base64 `.p12`) |
| `DEVELOPER_ID_CERT_PASSWORD` | `.p12` password |
| `NOTARY_APPLE_ID` | Apple ID for `notarytool` |
| `NOTARY_PASSWORD` | app-specific password for `notarytool` |
| `SPARKLE_ED_PRIVATE_KEY` | base64 of the Sparkle EdDSA private key — signs the appcast (**already set**) |

To rotate the Sparkle key: `generate_keys --account capsule-native` (paste the new public key
into `App/Info.plist`), then re-export and update the secret:
```sh
generate_keys --account capsule-native -x sparkle_priv
base64 < sparkle_priv | gh secret set SPARKLE_ED_PRIVATE_KEY --repo capsule-native/capsule
rm sparkle_priv
```
When signing secrets are absent (e.g. on a fork), the workflow still builds + validates the
pipeline but skips notarization/publishing — it never fails for want of credentials.

## Environment (local runs)

| Var | Required | Meaning |
| --- | --- | --- |
| `TEAM_ID` | yes | Apple Developer Team ID |
| `NOTARY_PROFILE` | yes | `notarytool` keychain profile name (e.g. `capsule-notary`) |
| `RELEASE_DOWNLOAD_URL_PREFIX` | CI-set | prepended to the appcast's enclosure filenames — the tag's release-download URL. Empty → filenames stay relative to the appcast. |
| `DEVELOPER_ID_APP` | optional | explicit signing identity string |
| `SPARKLE_BIN` | optional | dir containing `generate_appcast` / `generate_keys` |
| `SPARKLE_ED_KEY_FILE` | optional | private-key file; else the login keychain (`capsule-native`) |
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
| 5 | `appcast.sh` | `make appcast` | Sparkle `generate_appcast` signs the zip + writes `appcast.xml` (with `RELEASE_DOWNLOAD_URL_PREFIX`) |

## Cutting a release

1. Bump `CFBundleShortVersionString` **and** `CFBundleVersion` in `App/Info.plist`; commit + push.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`. The tag `vX.Y.Z` **must** match the Info.plist
   version — the workflow's *Verify tag matches app version* step fails the build otherwise (no
   more `v1.2.3` tags that package `Capsule-0.1.0.zip`).
3. The workflow builds, signs, notarizes, and publishes the Release. The Pages repo picks up the
   new appcast automatically within ~15 min, or immediately if you run **Sync appcast** there.

## CI

`.github/workflows/release.yml` runs the same pipeline on a `v*` tag, importing the Developer ID
cert + notary creds + Sparkle key from repository secrets, then publishes the artifacts and the
signed `appcast.xml` to the GitHub Release.

## Notes

- **Version comes from the app, not the tag.** Artifact names and the Sparkle appcast use
  `CFBundleShortVersionString` from `App/Info.plist`; the tag guard just enforces they agree.
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
