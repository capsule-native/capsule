#!/usr/bin/env bash
#
# check-architecture.sh
# Capsule
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Fast, dependency-free guard for the milestone's hard architectural boundaries.
# Mirrors Tests/CapsuleUnitTests/ArchitectureGuardTests (which is authoritative under
# `swift test`); this version gives quick feedback in hooks and CI.

set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

forbid_import() { # <module> <forbidden-module>
  local module="$1" forbidden="$2"
  if grep -rlE "^[[:space:]]*import[[:space:]]+${forbidden}([[:space:]]|$)" "Sources/${module}" 2>/dev/null; then
    echo "❌ ${module} must not import ${forbidden}"
    fail=1
  fi
}

# UI must never depend on a backend module.
forbid_import CapsuleUI CapsuleBackend
forbid_import CapsuleUI CapsuleCLIBackend
# Domain must never depend on UI or a concrete backend adapter.
forbid_import CapsuleDomain CapsuleUI
forbid_import CapsuleDomain CapsuleCLIBackend

# Terminal engine boundaries: UI/Domain never import the engine; the engine never imports
# a backend module (it receives the resolved executable via injection).
forbid_import CapsuleUI CapsuleTerminal
forbid_import CapsuleDomain CapsuleTerminal
forbid_import CapsuleTerminal CapsuleBackend
forbid_import CapsuleTerminal CapsuleCLIBackend

# Domain must not touch Foundation.Process.
if grep -rnE "\bProcess[[:space:]]*\(" Sources/CapsuleDomain 2>/dev/null; then
  echo "❌ CapsuleDomain must not use Foundation.Process"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "✅ Architecture boundaries OK"
fi
exit "$fail"
