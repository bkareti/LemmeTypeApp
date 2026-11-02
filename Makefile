# Developer entry points. See the macos-development skill for the workflow.

PROJECT     := LemmeType.xcodeproj
SCHEME      := LemmeType
PACKAGE     := Packages/LemmeTypeKit
DERIVED     := build/DerivedData
DESTINATION := platform=macOS,arch=arm64
IOS_DESTINATION := platform=iOS Simulator,name=iPhone 17
IOS_XCODEBUILD := xcodebuild -project $(PROJECT) -scheme LemmeTypeiOS -destination '$(IOS_DESTINATION)' -derivedDataPath $(DERIVED)-ios
XCODEBUILD  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)
SWIFT_DIRS  := App Packages/LemmeTypeKit/Sources Packages/LemmeTypeKit/Tests Packages/LemmeTypeKit/Package.swift

.PHONY: bootstrap generate build build-ios test-ios test test-unit test-app test-ui lint format app-icons privacy-check network-check security-check privacy-docs-check l10n-check l10n-update docs-check corpus-check evaluation-check evaluation quality-gate release-build release-verify release-notarize release-script-tests ci run clean benchmark release-check

bootstrap: ## Verify required tools are installed
	@command -v xcodegen >/dev/null || { echo "Missing xcodegen: brew install xcodegen"; exit 1; }
	@command -v swiftlint >/dev/null || { echo "Missing swiftlint: brew install swiftlint"; exit 1; }
	@xcrun --find swift-format >/dev/null || { echo "Missing swift-format (ships with Xcode)"; exit 1; }
	@xcodebuild -version

generate: ## Regenerate LemmeType.xcodeproj from project.yml
	xcodegen generate --quiet

build: generate ## Debug build of the app
	$(XCODEBUILD) -configuration Debug build

build-ios: generate ## Debug build of the iPhone and iPad app for the iOS Simulator
	$(IOS_XCODEBUILD) -configuration Debug build

test-ios: generate ## iPhone and iPad app unit tests and the portable package tests on the iOS Simulator
	$(IOS_XCODEBUILD) test -skip-testing:LemmeTypeiOSUITests

test: generate ## All tests: package, app unit, and UI tests
	$(XCODEBUILD) test

test-unit: ## Fast package unit tests only
	swift test --package-path $(PACKAGE)

test-app: generate ## App unit tests (composition root)
	$(XCODEBUILD) test -only-testing:LemmeTypeTests

test-ui: generate ## UI tests (needs an unlocked GUI session)
	$(XCODEBUILD) test -only-testing:LemmeTypeUITests

lint: ## swift-format lint and SwiftLint, warnings fail
	xcrun swift-format lint --strict --recursive $(SWIFT_DIRS)
	swiftlint lint --strict --quiet

privacy-check: ## Fail if captured audio was left behind
	scripts/check-no-captured-audio.sh

network-check: ## Fail if a file outside the allowlist uses a network API
	scripts/tests/test-network-usage.sh
	scripts/check-network-usage.sh

security-check: ## Fail on an unreviewed entitlement, permission string, dependency, or hardening change
	python3 -I scripts/tests/test-security-config.py
	python3 -I scripts/check-security-config.py

privacy-docs-check: ## Fail if the threat model or privacy checklist cites something that does not exist
	python3 -I scripts/tests/test-privacy-docs.py
	python3 -I scripts/check-privacy-docs.py

l10n-check: ## Localization readiness: no bypassing literals, hand formatting, or stale/uncommented catalog
	python3 -I scripts/tests/test-localization.py
	python3 -I scripts/check-localization.py

l10n-update: ## Refresh the string catalog from the Swift sources
	python3 -I scripts/check-localization.py --update

docs-check: ## Fail if the release and support documents point at something that does not exist
	python3 -I scripts/tests/test-doc-links.py
	python3 -I scripts/check-doc-links.py

corpus-check: ## Corpus script tests and the committed corpus manifests (no audio needed)
	python3 -I scripts/tests/test-corpus.py
	python3 -I scripts/corpus.py verify docs/testing/corpus/*.json

evaluation-check: ## Evaluation report script tests (fixtures only; no engine or audio needed)
	python3 -I scripts/tests/test-evaluation-report.py

evaluation: ## Corpus evaluation with real Whisper models + reports (not CI; BASELINE=path compares)
	scripts/run-evaluation.sh $(if $(BASELINE),--baseline $(BASELINE))

quality-gate: ## Every automated check with one summary (UI=1 adds the UI tests)
	scripts/tests/test-quality-gate.sh
	scripts/quality-gate.sh $(if $(UI),--ui)

release-script-tests: ## Fixture tests for the release scripts
	scripts/tests/test-verify-release.sh

release-build: ## Build build/release (Developer ID if available; REHEARSAL=1 forces an ad-hoc build)
	scripts/build-release.sh $(if $(REHEARSAL),--rehearsal)

release-verify: ## Verify build/release/export/LemmeType.app (REHEARSAL=1 skips Gatekeeper and notarization)
	scripts/verify-release.sh build/release/export/LemmeType.app $(if $(REHEARSAL),--rehearsal)

release-notarize: ## Notarize, staple, repackage (needs NOTARY_PROFILE; see docs/release/runbook.md)
	scripts/notarize-release.sh

ci: lint build test-unit test-app privacy-check network-check security-check privacy-docs-check l10n-check docs-check ## What CI runs on every pull request

benchmark: ## End-to-end benchmark on this Mac + threshold check (not on CI)
	scripts/run-e2e-benchmark.sh

release-check: ## Thresholds and artifact scan; APP=path/to/LemmeType.app or .zip
	python3 scripts/check-performance-thresholds.py build/benchmarks
	scripts/check-release-artifact.sh $(APP)

app-icons: ## Re-render the Mac and iPhone/iPad app icons from the vector L (needs: brew install librsvg)
	python3 scripts/make-app-icons.py

format: ## Apply swift-format
	xcrun swift-format format --in-place --recursive $(SWIFT_DIRS)

run: build ## Build and launch the Debug app
	open $(DERIVED)/Build/Products/Debug/LemmeType.app

clean:
	rm -rf build $(PACKAGE)/.build $(PROJECT)
