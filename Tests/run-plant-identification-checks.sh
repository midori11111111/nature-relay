#!/bin/zsh
set -eu

# Contract and privacy checks use injected fixture responses, without paid or free API calls.
# Requires one booted iOS Simulator; does not modify or launch the Nature Relay app.
nr_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
nr_sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
nr_test_dir="$(mktemp -d /tmp/nature-relay-plant-check.XXXXXX)"
trap 'rm -rf "$nr_test_dir"' EXIT

xcrun --sdk iphonesimulator swiftc \
  -swift-version 6 \
  -target arm64-apple-ios17.0-simulator \
  -sdk "$nr_sdk_path" \
  "$nr_project_dir/NatureRelay/PlantIdentificationService.swift" \
  "$nr_project_dir/Tests/PlantIdentificationChecks.swift" \
  -o "$nr_test_dir/plant-identification-checks"

xcrun simctl spawn booted "$nr_test_dir/plant-identification-checks"
