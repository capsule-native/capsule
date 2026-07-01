#!/usr/bin/env bash
#
# coverage.sh — run the unit tests with code coverage and emit a report + lcov.
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Produces:
#   - a per-file coverage summary on stdout (Sources only; tests/checkouts excluded)
#   - dist/coverage/coverage.lcov  (for CI upload)
#   - dist/coverage/coverage.txt   (the summary, saved)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${COVERAGE_OUT:-$REPO_ROOT/dist/coverage}"
IGNORE_REGEX='(Tests/|\.build/|/checkouts/|/Fixtures/)'

cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"

echo "▸ Running tests with coverage instrumentation…" >&2
swift test --enable-code-coverage >&2

BIN_PATH="$(swift build --show-bin-path)"
XCTEST="$(find "$BIN_PATH" -name '*.xctest' -maxdepth 1 | head -1)"
[ -n "$XCTEST" ] || { echo "✖ could not find the .xctest bundle under $BIN_PATH" >&2; exit 1; }
BIN="$XCTEST/Contents/MacOS/$(basename "$XCTEST" .xctest)"
PROFDATA="$BIN_PATH/codecov/default.profdata"
[ -f "$PROFDATA" ] || { echo "✖ missing $PROFDATA" >&2; exit 1; }

echo "▸ Coverage report (Sources only):" >&2
xcrun llvm-cov report "$BIN" \
  -instr-profile "$PROFDATA" \
  -ignore-filename-regex="$IGNORE_REGEX" \
  | tee "$OUT_DIR/coverage.txt"

xcrun llvm-cov export "$BIN" \
  -instr-profile "$PROFDATA" \
  -ignore-filename-regex="$IGNORE_REGEX" \
  -format=lcov > "$OUT_DIR/coverage.lcov"

echo "▸ Wrote $OUT_DIR/coverage.lcov and $OUT_DIR/coverage.txt" >&2
