#!/usr/bin/env bash
#
# lib.sh — shared helpers for the Capsule release pipeline.
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Sourced by the other release scripts. Provides logging, a dry-run-aware `run`, and env
# checks. Honour DRY_RUN=1 (or --dry-run, parsed by each script) to print the plan without
# executing the signing/notarization steps.

set -euo pipefail

# Repo root = two levels up from Scripts/release/.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
: "${DRY_RUN:=0}"

# ANSI (skipped when not a TTY).
if [ -t 1 ]; then
  _C_BLUE='\033[36m'; _C_YELLOW='\033[33m'; _C_RED='\033[31m'; _C_RESET='\033[0m'
else
  _C_BLUE=''; _C_YELLOW=''; _C_RED=''; _C_RESET=''
fi

log()  { printf "${_C_BLUE}▸ %s${_C_RESET}\n" "$*" >&2; }
warn() { printf "${_C_YELLOW}⚠ %s${_C_RESET}\n" "$*" >&2; }
die()  { printf "${_C_RED}✖ %s${_C_RESET}\n" "$*" >&2; exit 1; }

# run <cmd...> — execute, or (in dry-run) print the command and skip it.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf "  [dry-run] %s\n" "$*" >&2
  else
    "$@"
  fi
}

# require_env NAME [hint] — fail (unless dry-run) when an env var is unset/empty.
# In dry-run, an unset var is assigned a visible placeholder so downstream `"$VAR"` expansions
# don't trip `set -u` before `run` can stub the command.
require_env() {
  local name="$1" hint="${2:-}"
  if [ -z "${!name:-}" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      warn "\$$name is unset — a real run needs it${hint:+ ($hint)}"
      printf -v "$name" '<%s>' "$name"
      export "${name?}"
    else
      die "\$$name is required${hint:+ — $hint}"
    fi
  fi
}

# require_cmd NAME — fail when a tool is missing.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH"
}

# app_version — CFBundleShortVersionString from the app Info.plist.
app_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/App/Info.plist"
}

# Parse a leading --dry-run flag from a script's args (call: parse_common_flags "$@").
parse_common_flags() {
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=1 ;;
    esac
  done
  export DRY_RUN
}
