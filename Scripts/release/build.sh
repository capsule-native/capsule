#!/usr/bin/env bash
#
# build.sh — archive Capsule (Release) into dist/Capsule.xcarchive.
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Regenerates the Xcode project (XcodeGen) and archives the Release configuration. The archive
# embeds Sparkle.framework and is signed at export time (export.sh) with the Developer ID.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_common_flags "$@"

ARCHIVE="$DIST_DIR/Capsule.xcarchive"

log "Archiving Capsule (Release) → $ARCHIVE"
require_cmd xcodebuild
require_cmd xcodegen

run mkdir -p "$DIST_DIR"
run make -C "$REPO_ROOT" xcodeproj

# Archive without signing here — export.sh applies the Developer ID (hardened runtime comes
# from the project's ENABLE_HARDENED_RUNTIME=YES).
run xcodebuild \
  -project "$REPO_ROOT/Capsule.xcodeproj" \
  -scheme Capsule \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  archive

log "Archive complete."
