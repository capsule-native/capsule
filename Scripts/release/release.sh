#!/usr/bin/env bash
#
# release.sh — the full Capsule release pipeline: archive → export/sign → notarize/staple →
# package → appcast.
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Usage:
#   Scripts/release/release.sh              # real run (requires Developer ID + notary creds)
#   Scripts/release/release.sh --dry-run    # print the plan; execute nothing that needs creds
#
# Required env for a real run:
#   TEAM_ID          Apple Developer Team ID
#   NOTARY_PROFILE   keychain profile for notarytool (xcrun notarytool store-credentials)
# Optional:
#   DEVELOPER_ID_APP, SPARKLE_BIN, SPARKLE_ED_KEY_FILE, DIST_DIR

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_flags "$@"

HERE="$(dirname "${BASH_SOURCE[0]}")"
VERSION="$(app_version 2>/dev/null || echo "?")"

log "Capsule release pipeline — version $VERSION $([ "$DRY_RUN" = "1" ] && echo '(DRY RUN)')"
log "Output directory: $DIST_DIR"

# Preflight: surface missing credentials up front (fatal on a real run).
require_env TEAM_ID "Apple Developer Team ID"
require_env NOTARY_PROFILE "notarytool keychain profile"

steps=(build export notarize package appcast)
for step in "${steps[@]}"; do
  log "── Step: $step ──────────────────────────────────────────"
  # Forward the same dry-run flag to each sub-step.
  if [ "$DRY_RUN" = "1" ]; then
    bash "$HERE/$step.sh" --dry-run
  else
    bash "$HERE/$step.sh"
  fi
done

log "Release pipeline finished."
if [ "$DRY_RUN" = "1" ]; then
  log "Dry run only — no artifact was signed. Provide TEAM_ID + NOTARY_PROFILE and re-run without --dry-run."
else
  log "Distributables in $DIST_DIR: Capsule-$VERSION.zip, Capsule-$VERSION.dmg, appcast.xml"
fi
