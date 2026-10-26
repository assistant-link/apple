# Assistant Link iOS app. Run from this directory: `make <target>`.
# SIMULATOR=<name or UDID> overrides the automatically picked simulator, and DEVICE= the
# iPhone for `make device`. SERVICE_URL=<url> points `run` and `device` at another service.
# Local.mk (git-ignored) holds per-developer settings such as DEVELOPMENT_TEAM; see
# docs/physical-device.md.

-include Local.mk

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Use the full Xcode even when `xcode-select` points at the Command Line Tools.
ifeq ($(origin DEVELOPER_DIR),undefined)
  ifeq ($(findstring .app/,$(shell xcode-select -p 2>/dev/null)),)
    ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer),)
      export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
    endif
  endif
endif

PROJECT := AssistantLink.xcodeproj
SCHEME := AssistantLink
BUNDLE_ID := ai.assistantlink.app
BUILD_DIR := build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/AssistantLink.app
DEVICE_APP_PATH := $(DERIVED_DATA)/Build/Products/Debug-iphoneos/AssistantLink.app
TEST_RESULTS := $(BUILD_DIR)/TestResults.xcresult
SCREENSHOT_DIR := $(BUILD_DIR)/screenshots
SOURCES := AssistantLink AssistantLinkTests AssistantLinkUITests
SIMULATOR ?=
DEVICE ?=
DEVELOPMENT_TEAM ?=
DEVICE_BUNDLE_ID ?= $(BUNDLE_ID)
SERVICE_URL ?=
LAUNCH_ARGS = $(if $(SERVICE_URL),-serviceURL $(SERVICE_URL))
XCODEBUILD_FLAGS ?= -quiet

SWIFT_FORMAT := xcrun swift format
# With Rosetta installed, every Simulator is also an x86_64 destination; pick the native one.
HOST_ARCH := $(shell uname -m)
# Recipe prefix: fail fast (make 3.81 ignores .SHELLFLAGS) and resolve the simulator
# into $udid, stopping if none matches.
PICK_SIMULATOR = set -euo pipefail; udid="$$(scripts/simulator-udid.sh '$(SIMULATOR)')";
XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	-destination "platform=iOS Simulator,id=$$udid,arch=$(HOST_ARCH)" -derivedDataPath $(DERIVED_DATA) \
	$(XCODEBUILD_FLAGS)

.PHONY: help generate build test screenshots run device lint format clean

help: ## Show this help
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

generate: ## Generate AssistantLink.xcodeproj from project.yml
	xcodegen generate --spec project.yml

$(PROJECT): project.yml
	xcodegen generate --spec project.yml

build: $(PROJECT) ## Build the app for the Simulator into build/
	$(PICK_SIMULATOR) $(XCODEBUILD) build

test: $(PROJECT) ## Run the unit tests on the Simulator
	@rm -rf $(TEST_RESULTS)
	@$(PICK_SIMULATOR) status=0; $(XCODEBUILD) -resultBundlePath $(TEST_RESULTS) test || status=$$?; \
	if [[ -d $(TEST_RESULTS) ]]; then \
	  xcrun xcresulttool get test-results summary --path $(TEST_RESULTS) --compact | jq -r \
	    '"\(.result): \(.passedTests) passed, \(.failedTests) failed, \(.skippedTests) skipped on \(.devicesAndConfigurations[0].device.deviceName) (iOS \(.devicesAndConfigurations[0].device.osVersion))", (.testFailures[] | "  FAILED \(.testName): \(.failureText)")'; \
	fi; \
	exit $$status

screenshots: SCHEME := AssistantLinkScreenshots
screenshots: $(PROJECT) ## Capture screenshots of the key screens in light and dark into build/screenshots
	@rm -rf $(BUILD_DIR)/Screenshots-*.xcresult $(SCREENSHOT_DIR) $(BUILD_DIR)/attachments
	@$(PICK_SIMULATOR) \
	xcrun simctl bootstatus "$$udid" -b > /dev/null; \
	original="$$(xcrun simctl ui "$$udid" appearance)"; \
	python3 scripts/mock-service.py & mock=$$!; \
	trap 'kill $$mock 2>/dev/null || true; xcrun simctl ui "$$udid" appearance "$$original" || true' EXIT; \
	sleep 1; \
	kill -0 $$mock 2>/dev/null || { echo "error: the mock service did not start; is port 8765 in use?" >&2; exit 1; }; \
	status=0; \
	for style in light dark; do \
	  bundle=$(BUILD_DIR)/Screenshots-$$style.xcresult; \
	  attachments=$(BUILD_DIR)/attachments/$$style; \
	  out=$(SCREENSHOT_DIR)/$$style; \
	  xcrun simctl ui "$$udid" appearance $$style; \
	  $(XCODEBUILD) -resultBundlePath $$bundle test || status=$$?; \
	  if [[ -d $$bundle ]]; then \
	    xcrun xcresulttool export attachments --path $$bundle --output-path $$attachments; \
	    mkdir -p $$out; \
	    jq -r '.[].attachments[]? | select(.suggestedHumanReadableName | test("^[0-9]-")) | [.exportedFileName, (.suggestedHumanReadableName | sub("(_[0-9]+_[0-9A-Fa-f-]{36})?(\\.png)?$$"; ""))] | @tsv' \
	      $$attachments/manifest.json | \
	    while IFS=$$'\t' read -r file name; do cp "$$attachments/$$file" "$$out/$$name.png"; done; \
	  fi; \
	  count=$$(ls $$out 2>/dev/null | wc -l || true); \
	  echo "Exported $$count $$style screenshots to $$out"; \
	  [[ $$count -gt 0 ]] || { echo "error: no $$style screenshot was exported." >&2; status=1; }; \
	done; \
	exit $$status

run: build ## Boot the Simulator, install and launch the app
	@$(PICK_SIMULATOR) \
	xcrun simctl bootstatus "$$udid" -b > /dev/null; \
	echo "Simulator: $$(xcrun simctl list devices | grep "$$udid" | sed -E 's/^ +//')"; \
	open -a Simulator --args -CurrentDeviceUDID "$$udid"; \
	xcrun simctl install "$$udid" "$(APP_PATH)"; \
	xcrun simctl launch --terminate-running-process "$$udid" $(BUNDLE_ID) $(LAUNCH_ARGS)

device: $(PROJECT) ## Build, install and launch on a paired iPhone
	@set -euo pipefail; \
	if [[ -z "$(DEVELOPMENT_TEAM)" ]]; then \
	  echo "error: set DEVELOPMENT_TEAM in Local.mk; see docs/physical-device.md." >&2; exit 1; \
	fi; \
	udid="$$(scripts/device-udid.sh '$(DEVICE)')"; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	  -destination "platform=iOS,id=$$udid" -derivedDataPath $(DERIVED_DATA) \
	  -allowProvisioningUpdates -allowProvisioningDeviceRegistration $(XCODEBUILD_FLAGS) \
	  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
	  PRODUCT_BUNDLE_IDENTIFIER=$(DEVICE_BUNDLE_ID) build; \
	xcrun devicectl device install app --device "$$udid" "$(DEVICE_APP_PATH)"; \
	xcrun devicectl device process launch --terminate-existing --device "$$udid" \
	  $(DEVICE_BUNDLE_ID) $(LAUNCH_ARGS)

lint: ## Check formatting and style with swift format
	$(SWIFT_FORMAT) lint --strict --recursive --parallel --configuration .swift-format $(SOURCES)

format: ## Reformat Swift sources in place with swift format
	$(SWIFT_FORMAT) format --in-place --recursive --parallel --configuration .swift-format $(SOURCES)

clean: ## Remove build/ and the generated Xcode project
	rm -rf $(BUILD_DIR) $(PROJECT)
