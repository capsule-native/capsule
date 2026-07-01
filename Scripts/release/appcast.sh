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
# key file, if you don't use the keychain).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_flags "$@"

# Locate generate_appcast: explicit SPARKLE_BIN, then the resolved SwiftPM artifact, then PATH.
find_generate_appcast() {
  if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "$SPARKLE_BIN/generate_appcast"; return 0
  fi
  local hit
  hit="$(find "$REPO_ROOT/.build/artifacts" -name generate_appcast -type f 2>/dev/null | head -1 || true)"
  if [ -n "$hit" ]; then echo "$hit"; return 0; fi
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

log "Signing artifacts + generating appcast with: $GEN"
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  run "$GEN" --ed-key-file "$SPARKLE_ED_KEY_FILE" "$DIST_DIR"
else
  # No key file → generate_appcast reads the private key from the login keychain.
  run "$GEN" "$DIST_DIR"
fi

log "appcast written → $DIST_DIR/appcast.xml"
if [ "$DRY_RUN" != "1" ] && [ -f "$DIST_DIR/appcast.xml" ]; then
  log "Host this file at the URL in App/Info.plist's SUFeedURL."
fi
