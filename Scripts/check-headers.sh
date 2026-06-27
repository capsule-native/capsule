#!/usr/bin/env bash
#
# check-headers.sh
# Capsule
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Verifies that every Swift source carries the standard Capsule license header.
# Run `Scripts/add-headers.sh` to add it to any files that are missing it.

set -euo pipefail
cd "$(dirname "$0")/.."

missing=0
while IFS= read -r -d '' file; do
  if ! head -n 8 "$file" | grep -q "Copyright ©"; then
    echo "❌ Missing license header: $file"
    missing=1
  fi
done < <(find Sources Tests App/Sources App/CapsuleUITests -name '*.swift' -print0 2>/dev/null)

if [ "$missing" -eq 0 ]; then
  echo "✅ License headers OK"
fi
exit "$missing"
