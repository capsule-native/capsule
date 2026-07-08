#!/usr/bin/env bash
#
# update-homebrew-cask.sh
# Capsule
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Renders the Homebrew cask for a released build to stdout, pinning the SHA-256 of the release
# DMG. Pure and network-free: the CI release job redirects this into a checkout of
# capsule-native/homebrew-tap and pushes the result (see .github/workflows/release.yml). Keeping
# the template here makes the main repo the single source of truth for the cask.
#
# Usage: update-homebrew-cask.sh <version> <dmg-path>
#   e.g. update-homebrew-cask.sh 0.1.0 dist/Capsule-0.1.0.dmg

set -euo pipefail

version="${1:?usage: update-homebrew-cask.sh <version> <dmg-path>}"
dmg="${2:?usage: update-homebrew-cask.sh <version> <dmg-path>}"

[ -f "$dmg" ] || { echo "update-homebrew-cask.sh: missing DMG: $dmg" >&2; exit 1; }

sha256="$(shasum -a 256 "$dmg" | awk '{print $1}')"

# The `#{version}` tokens below are Ruby interpolation for Homebrew and must survive verbatim;
# only ${version}/${sha256} are expanded by the shell here.
cat <<EOF
cask "capsule" do
  version "${version}"
  sha256 "${sha256}"

  url "https://github.com/capsule-native/capsule/releases/download/v#{version}/Capsule-#{version}.dmg",
      verified: "github.com/capsule-native/capsule/"
  name "Capsule"
  desc "GUI for Apple's container CLI"
  homepage "https://capsule-native.github.io/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Capsule.app"

  zap trash: [
    "~/Library/Application Support/com.capsule.app",
    "~/Library/Caches/com.capsule.app",
    "~/Library/HTTPStorages/com.capsule.app",
    "~/Library/Preferences/com.capsule.app.plist",
    "~/Library/Saved Application State/com.capsule.app.savedState",
  ]
end
EOF
