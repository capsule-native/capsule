#!/usr/bin/env bash
#
# package.sh — produce the distributable artifacts from the stapled app.
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Emits:
#   dist/Capsule-<version>.zip  — the Sparkle update artifact (must contain the stapled .app)
#   dist/Capsule-<version>.dmg  — the human download (if `create-dmg` or hdiutil is available)

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_flags "$@"

APP="$DIST_DIR/Capsule.app"
VERSION="$(app_version 2>/dev/null || echo "0.0.0")"
ZIP="$DIST_DIR/Capsule-$VERSION.zip"
DMG="$DIST_DIR/Capsule-$VERSION.dmg"

[ -d "$APP" ] || [ "$DRY_RUN" = "1" ] || die "missing $APP — run the earlier steps first"

log "Zipping stapled app → $ZIP (Sparkle update artifact)"
run rm -f "$ZIP"
run ditto -c -k --keepParent "$APP" "$ZIP"

log "Building DMG → $DMG"
if command -v create-dmg >/dev/null 2>&1; then
  run rm -f "$DMG"
  run create-dmg \
    --volname "Capsule $VERSION" \
    --app-drop-link 480 170 \
    --icon "Capsule.app" 160 170 \
    "$DMG" "$APP"
else
  warn "create-dmg not found — falling back to a plain hdiutil DMG (brew install create-dmg for the styled one)"
  run rm -f "$DMG"
  run hdiutil create -volname "Capsule $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"
fi

log "Artifacts:"
log "  $ZIP"
log "  $DMG"
