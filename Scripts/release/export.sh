#!/usr/bin/env bash
#
# export.sh — export a Developer-ID-signed Capsule.app from the archive.
#
# Copyright © 2026 Capsule. All rights reserved.
#
# `xcodebuild -exportArchive` with a Developer ID export options plist signs inside-out —
# including Sparkle's nested Autoupdate / Updater.app / XPC services — with the Hardened
# Runtime and a secure timestamp, which is exactly what notarization requires. Doing it this
# way (instead of hand-rolled `codesign --deep`) is Apple's recommended path.
#
# Required env (real run): DEVELOPER_ID_APP or TEAM_ID.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_flags "$@"

ARCHIVE="$DIST_DIR/Capsule.xcarchive"
EXPORT_DIR="$DIST_DIR/export"
OPTIONS_PLIST="$DIST_DIR/ExportOptions.plist"

require_cmd xcodebuild
require_env TEAM_ID "your Apple Developer Team ID, e.g. ABCDE12345"

log "Writing export options → $OPTIONS_PLIST (method: developer-id)"
if [ "$DRY_RUN" != "1" ]; then
  cat > "$OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>            <string>developer-id</string>
  <key>teamID</key>            <string>${TEAM_ID}</string>
  <key>signingStyle</key>      <string>manual</string>
  <key>destination</key>       <string>export</string>
  <!-- Sparkle is delivered via its own appcast, not the App Store, so no manifest is needed. -->
</dict>
</plist>
PLIST
else
  printf "  [dry-run] would write ExportOptions.plist with teamID=%s\n" "${TEAM_ID:-<unset>}" >&2
fi

log "Exporting signed Capsule.app → $EXPORT_DIR"
run xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS_PLIST"

# Move the exported app to a stable path the later steps expect.
run rm -rf "$DIST_DIR/Capsule.app"
run cp -R "$EXPORT_DIR/Capsule.app" "$DIST_DIR/Capsule.app"

if [ "$DRY_RUN" != "1" ]; then
  log "Verifying signature + hardened runtime"
  run codesign --verify --deep --strict --verbose=2 "$DIST_DIR/Capsule.app"
  run codesign --display --verbose=4 "$DIST_DIR/Capsule.app" 2>&1 | grep -i 'flags\|Authority' || true
fi

log "Export complete → $DIST_DIR/Capsule.app"
