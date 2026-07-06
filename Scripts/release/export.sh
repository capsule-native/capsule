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
# Required env (real run): TEAM_ID (the export selects the team's "Developer ID Application"
# certificate; TEAM_ID also scopes notarization).

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
  <!-- Pin identity selection so a second (e.g. renewed/expired) Developer ID Application cert in
       the keychain can't be chosen instead of the current one. -->
  <key>signingCertificate</key> <string>Developer ID Application</string>
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

# assert_signed <path> <label> — fail unless <path> is signed with this team's identity AND
# carries the Hardened Runtime flag. `codesign --verify --deep` alone can't catch these
# notarization-fatal cases (a nested helper still on Sparkle's team, or a missing runtime flag),
# so check them explicitly on the app and every nested Sparkle Mach-O.
assert_signed() {
  local path="$1" label="$2" out team
  [ -e "$path" ] || { warn "  (skip $label — not present)"; return 0; }
  out="$(codesign -dvvv "$path" 2>&1 || true)"
  # Parse the variable directly (no pipes): a `printf | grep -q` here can SIGPIPE printf and,
  # under `set -euo pipefail`, look like a failure even when the flag is present.
  if [[ "$out" =~ TeamIdentifier=([A-Za-z0-9]+) ]]; then team="${BASH_REMATCH[1]}"; else team=""; fi
  [ "$team" = "$TEAM_ID" ] || die "signature: $label has TeamIdentifier='$team', expected '$TEAM_ID'"
  # Match the `runtime` token inside codesign's comma-joined flags list, e.g.
  # flags=0x10000(runtime) or flags=0x12000(library-validation,runtime) — not just a lone
  # "(runtime)". (The SDK line is capital-R "Runtime Version="; only the flags use lowercase.)
  local flags=""
  [[ "$out" =~ flags=0x[0-9a-fA-F]+\(([^\)]*)\) ]] && flags="${BASH_REMATCH[1]}"
  case ",$flags," in
    *,runtime,*) : ;;
    *) die "signature: $label is missing the Hardened Runtime flag (flags='$flags')" ;;
  esac
  log "  ✓ $label (team $team, hardened runtime)"
}

if [ "$DRY_RUN" != "1" ]; then
  APP="$DIST_DIR/Capsule.app"
  log "Verifying Developer ID + Hardened Runtime (app + nested Sparkle code)"
  run codesign --verify --strict --verbose=2 "$APP"
  assert_signed "$APP" "Capsule.app"
  FW="$APP/Contents/Frameworks/Sparkle.framework"
  if [ -d "$FW" ]; then
    assert_signed "$FW" "Sparkle.framework"
    while IFS= read -r nested; do
      assert_signed "$nested" "${nested#"$APP"/Contents/Frameworks/}"
    done < <(find "$FW" \( -name Autoupdate -o -name 'Updater.app' -o -name '*.xpc' \) 2>/dev/null)
  fi
fi

log "Export complete → $DIST_DIR/Capsule.app"
