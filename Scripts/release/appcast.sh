#!/usr/bin/env bash
#
# appcast.sh — sign the update artifacts and (re)generate appcast.xml with Sparkle.
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Sparkle's `generate_appcast` scans a directory of update zips, signs each with the EdDSA
# private key, and writes/updates appcast.xml. The private key lives in the release runner's
# keychain (created once with Sparkle's `generate_keys`) — it NEVER enters the repo. Point
# SUFeedURL (App/Info.plist) at wherever you host the resulting appcast.xml.
#
# Optional env: SPARKLE_BIN (dir containing generate_appcast), SPARKLE_ED_KEY_FILE (a private
# key file, if you don't use the keychain), SPARKLE_ACCOUNT (keychain account for the private
# key when SPARKLE_ED_KEY_FILE is unset; defaults to the account the key was generated under).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_flags "$@"

# Locate generate_appcast. Sparkle's tools ship inside its SwiftPM binary artifact; where that
# lands depends on how the package was resolved:
#   • `swift build`/`swift package resolve`      → $REPO_ROOT/.build/artifacts
#   • `xcodebuild -derivedDataPath DerivedData`  → $REPO_ROOT/DerivedData/SourcePackages/artifacts
#   • `xcodebuild archive` (default derived data) → ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts
# The release pipeline archives with xcodebuild BEFORE this step, so on a clean CI runner the
# tool exists only under the global DerivedData — search all three (plus $SPARKLE_BIN / PATH).
find_generate_appcast() {
  if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "$SPARKLE_BIN/generate_appcast"; return 0
  fi
  local root hit
  for root in \
    "$REPO_ROOT/.build/artifacts" \
    "$REPO_ROOT/DerivedData/SourcePackages/artifacts" \
    "$HOME/Library/Developer/Xcode/DerivedData"; do
    [ -d "$root" ] || continue
    hit="$(find "$root" -name generate_appcast -type f 2>/dev/null | head -1 || true)"
    if [ -n "$hit" ]; then echo "$hit"; return 0; fi
  done
  if command -v generate_appcast >/dev/null 2>&1; then command -v generate_appcast; return 0; fi
  return 1
}

GEN="$(find_generate_appcast || true)"
if [ -z "$GEN" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    warn "generate_appcast not found — resolve Sparkle (swift package resolve) or set \$SPARKLE_BIN"
    GEN="generate_appcast"
  else
    die "generate_appcast not found. Run 'swift package resolve' or set \$SPARKLE_BIN (Sparkle's bin dir)."
  fi
fi

# Optional: prefix the bare enclosure filenames with the public download URL (e.g. the GitHub
# Release asset base for this tag). Without it, generate_appcast writes filenames relative to
# the appcast's own location — wrong here, since the appcast is hosted on the Pages repo but the
# zips live on the code repo's Release. The release workflow sets this to the tag's download URL.
PREFIX_ARGS=()
if [ -n "${RELEASE_DOWNLOAD_URL_PREFIX:-}" ]; then
  PREFIX_ARGS=(--download-url-prefix "$RELEASE_DOWNLOAD_URL_PREFIX")
  log "Enclosure URL prefix: $RELEASE_DOWNLOAD_URL_PREFIX"
fi

# generate_appcast scans a WHOLE directory and rejects two archives that carry the same bundle
# version — and package.sh emits both Capsule-<v>.zip AND Capsule-<v>.dmg into $DIST_DIR. Run
# generate_appcast over a dedicated dir holding ONLY the Sparkle update zip(s), then move the
# result back. (The .dmg is a human download only; Sparkle never sees it.) Note: this dir is
# reset each run and holds only the current zip, so appcasts are single-item with no deltas —
# fine for full-zip updates; wiring delta/version history would mean retaining prior zips here.
APPCAST_SRC="$DIST_DIR/appcast-src"
run rm -rf "$APPCAST_SRC"
run mkdir -p "$APPCAST_SRC"
if [ "$DRY_RUN" != "1" ]; then
  shopt -s nullglob
  zips=("$DIST_DIR"/Capsule-*.zip)
  shopt -u nullglob
  [ ${#zips[@]} -gt 0 ] || die "no Capsule-*.zip in $DIST_DIR — run package.sh first"
  for z in "${zips[@]}"; do run cp "$z" "$APPCAST_SRC/"; done
fi

log "Signing artifacts + generating appcast with: $GEN"
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  run "$GEN" --ed-key-file "$SPARKLE_ED_KEY_FILE" ${PREFIX_ARGS[@]+"${PREFIX_ARGS[@]}"} "$APPCAST_SRC"
else
  # No key file → generate_appcast reads the private key from the login keychain. Sparkle looks
  # up the DEFAULT "ed25519" account unless told otherwise; this key was generated under a named
  # account (see App/Info.plist), so pass it through or the run silently emits UNSIGNED enclosures.
  ACCOUNT_ARGS=()
  [ -n "${SPARKLE_ACCOUNT:-}" ] && ACCOUNT_ARGS=(--account "$SPARKLE_ACCOUNT")
  run "$GEN" ${ACCOUNT_ARGS[@]+"${ACCOUNT_ARGS[@]}"} ${PREFIX_ARGS[@]+"${PREFIX_ARGS[@]}"} "$APPCAST_SRC"
fi
[ "$DRY_RUN" = "1" ] || [ -f "$APPCAST_SRC/appcast.xml" ] || die "generate_appcast wrote no appcast.xml — nothing was signed."
run mv "$APPCAST_SRC/appcast.xml" "$DIST_DIR/appcast.xml"

# Guard the silent-unsigned-update failure mode: if the signing key's public half does not match
# the app's embedded SUPublicEDKey, generate_appcast only WARNS, exits 0, and writes enclosures
# with NO sparkle:edSignature — which every client rejects. Refuse to publish such an appcast.
if [ "$DRY_RUN" != "1" ]; then
  APPCAST="$DIST_DIR/appcast.xml"
  [ -f "$APPCAST" ] || die "generate_appcast produced no appcast.xml"
  # `|| true`: zero matches makes grep exit 1, which under `set -euo pipefail` would abort the
  # script before the checks below — swallow it so the guard (not set -e) reports the problem.
  n_enc="$( { grep -o '<enclosure' "$APPCAST" || true; } | wc -l | tr -d ' ')"
  n_sig="$( { grep -o 'sparkle:edSignature' "$APPCAST" || true; } | wc -l | tr -d ' ')"
  [ "${n_enc:-0}" -ge 1 ] || die "appcast.xml has no <enclosure> — nothing to publish."
  if [ "${n_sig:-0}" -lt "${n_enc:-0}" ]; then
    pub="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$REPO_ROOT/App/Info.plist" 2>/dev/null || echo '?')"
    die "appcast.xml has $n_enc enclosure(s) but only $n_sig EdDSA signature(s) — refusing to publish an UNSIGNED update (Sparkle clients reject it). The signing key's public half must equal App/Info.plist SUPublicEDKey ($pub)."
  fi
  log "Verified $n_sig/$n_enc enclosure(s) carry an EdDSA signature."
fi

log "appcast written → $DIST_DIR/appcast.xml"
if [ "$DRY_RUN" != "1" ] && [ -f "$DIST_DIR/appcast.xml" ]; then
  log "Attached to the GitHub Release; the Pages repo's sync workflow publishes it at SUFeedURL."
fi
