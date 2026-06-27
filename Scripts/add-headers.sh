#!/usr/bin/env bash
#
# add-headers.sh
# Capsule
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Prepends the standard Capsule license header to any *.swift file missing it.

set -euo pipefail
cd "$(dirname "$0")/.."

YEAR="${CAPSULE_HEADER_YEAR:-2026}"

add_header() {
  local file="$1"
  local name
  name="$(basename "$file")"
  if head -n 8 "$file" | grep -q "Copyright ©"; then
    return
  fi
  local tmp
  tmp="$(mktemp)"
  {
    printf '//\n//  %s\n//  Capsule\n//\n//  Copyright © %s Capsule. All rights reserved.\n//\n\n' \
      "$name" "$YEAR"
    cat "$file"
  } >"$tmp"
  mv "$tmp" "$file"
  echo "added header: $file"
}

while IFS= read -r -d '' file; do
  add_header "$file"
done < <(find Sources Tests App/Sources App/CapsuleUITests -name '*.swift' -print0 2>/dev/null)

echo "✅ Headers ensured"
