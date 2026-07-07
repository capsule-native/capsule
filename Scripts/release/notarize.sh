#!/usr/bin/env bash
#
# notarize.sh — notarize dist/Capsule.app and staple the ticket.
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Zips the signed app, submits to Apple's notary service (waiting for the result), then staples
# the ticket onto the .app so it validates offline.
#
# Required env (real run): NOTARY_PROFILE — a keychain profile created once with
#   xcrun notarytool store-credentials NOTARY_PROFILE \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_flags "$@"

APP="$DIST_DIR/Capsule.app"
SUBMIT_ZIP="$DIST_DIR/Capsule-notarize.zip"

require_cmd xcrun
require_env NOTARY_PROFILE "run 'xcrun notarytool store-credentials' once to create it"

[ -d "$APP" ] || [ "$DRY_RUN" = "1" ] || die "missing $APP — run build.sh + export.sh first"

log "Zipping app for notarization → $SUBMIT_ZIP"
run ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

log "Submitting to the notary service (this can take a few minutes)…"
# --timeout bounds the --wait poll. A healthy submission clears in minutes, but Apple's notary
# service can occasionally wedge a submission "In Progress" indefinitely; without a bound, --wait
# blocks until the CI job itself is killed (a stuck run once burned GitHub's full 6-hour budget).
# Fail fast at 30m so the release errors loudly instead of idling to the runner's hard ceiling.
run xcrun notarytool submit "$SUBMIT_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --timeout 30m

log "Stapling the notarization ticket onto the app"
run xcrun stapler staple "$APP"

if [ "$DRY_RUN" != "1" ]; then
  log "Validating staple + Gatekeeper assessment"
  run xcrun stapler validate "$APP"
  run spctl --assess --type execute --verbose=4 "$APP"
fi

run rm -f "$SUBMIT_ZIP"
log "Notarization complete."
