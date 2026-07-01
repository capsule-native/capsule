# Makefile
# Capsule
#
# Copyright © 2026 Capsule. All rights reserved.
#
# Common entry points for building, testing, formatting, and packaging Capsule.
# The SwiftPM modules build with either toolchain, but XCTest (swift test) and the
# Xcode app target require full Xcode, so we point DEVELOPER_DIR at it.

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

SWIFT ?= swift
XCODEGEN ?= xcodegen
PROJECT := Capsule.xcodeproj
SCHEME := Capsule
DERIVED_DATA := DerivedData
FORMAT_PATHS := Sources Tests App/Sources App/CapsuleUITests Package.swift

.DEFAULT_GOAL := help

.PHONY: help build test format lint arch headers check ci xcodeproj app run clean hooks bootstrap \
	coverage archive export notarize package appcast release release-dry

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build all SwiftPM modules
	$(SWIFT) build

test: ## Run unit tests (integration tests self-skip unless CAPSULE_INTEGRATION=1)
	$(SWIFT) test

format: ## Format sources in place (swift-format)
	$(SWIFT) format format --in-place --recursive --parallel \
		--configuration .swift-format $(FORMAT_PATHS)

lint: ## Lint formatting without modifying files (used by CI / pre-commit)
	$(SWIFT) format lint --strict --recursive --parallel \
		--configuration .swift-format $(FORMAT_PATHS)

arch: ## Verify architectural boundaries (no UI->Backend, no Domain->UI)
	./Scripts/check-architecture.sh

headers: ## Verify license headers on all Swift sources
	./Scripts/check-headers.sh

check: lint arch headers ## Run all static checks

ci: build lint arch headers test ## Everything CI runs (no Xcode app build / no UI tests)

xcodeproj: ## Generate Capsule.xcodeproj from App/project.yml (requires xcodegen)
	$(XCODEGEN) generate --spec App/project.yml --project-root . --project .

app: xcodeproj ## Build the macOS .app bundle via xcodebuild
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS' build

run: app ## Build and launch the macOS app
	open "$(DERIVED_DATA)/Build/Products/Debug/Capsule.app"

coverage: ## Run unit tests with coverage; write dist/coverage/{coverage.lcov,coverage.txt}
	./Scripts/coverage.sh

# ── Release pipeline (see Scripts/release/README.md) ─────────────────────────
# Each step accepts --dry-run via the scripts; `release-dry` prints the whole plan without
# needing a Developer ID or notary credentials.

archive: ## Release pipeline: archive Capsule → dist/Capsule.xcarchive
	./Scripts/release/build.sh

export: ## Release pipeline: export a Developer-ID-signed dist/Capsule.app
	./Scripts/release/export.sh

notarize: ## Release pipeline: notarize + staple dist/Capsule.app
	./Scripts/release/notarize.sh

package: ## Release pipeline: build the distributable zip + DMG
	./Scripts/release/package.sh

appcast: ## Release pipeline: sign artifacts + (re)generate appcast.xml (Sparkle)
	./Scripts/release/appcast.sh

release: ## Full signed/notarized/stapled release (requires TEAM_ID + NOTARY_PROFILE)
	./Scripts/release/release.sh

release-dry: ## Print the full release plan without signing anything (no credentials needed)
	./Scripts/release/release.sh --dry-run

clean: ## Remove build artifacts and the generated Xcode project
	rm -rf .build DerivedData dist $(PROJECT)

hooks: ## Install git hooks (formatting + license headers on commit)
	git config core.hooksPath Scripts/hooks
	@echo "Installed git hooks (core.hooksPath -> Scripts/hooks)"

bootstrap: hooks ## One-time setup for a fresh clone
	@command -v $(XCODEGEN) >/dev/null 2>&1 \
		|| echo "warning: xcodegen not found — 'brew install xcodegen' to build the Xcode app target"
	@echo "Bootstrap complete."
