# Developer entry points. See the macos-development skill for the workflow.

PROJECT     := LemmeType.xcodeproj
SCHEME      := LemmeType
PACKAGE     := Packages/LemmeTypeKit
DERIVED     := build/DerivedData
DESTINATION := platform=macOS,arch=arm64
XCODEBUILD  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED)
SWIFT_DIRS  := App Packages/LemmeTypeKit/Sources Packages/LemmeTypeKit/Tests Packages/LemmeTypeKit/Package.swift

.PHONY: bootstrap generate build test test-unit test-app test-ui lint format run clean

bootstrap: ## Verify required tools are installed
	@command -v xcodegen >/dev/null || { echo "Missing xcodegen: brew install xcodegen"; exit 1; }
	@command -v swiftlint >/dev/null || { echo "Missing swiftlint: brew install swiftlint"; exit 1; }
	@xcrun --find swift-format >/dev/null || { echo "Missing swift-format (ships with Xcode)"; exit 1; }
	@xcodebuild -version

generate: ## Regenerate LemmeType.xcodeproj from project.yml
	xcodegen generate --quiet

build: generate ## Debug build of the app
	$(XCODEBUILD) -configuration Debug build

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

format: ## Apply swift-format
	xcrun swift-format format --in-place --recursive $(SWIFT_DIRS)

run: build ## Build and launch the Debug app
	open $(DERIVED)/Build/Products/Debug/LemmeType.app

clean:
	rm -rf build $(PACKAGE)/.build $(PROJECT)
