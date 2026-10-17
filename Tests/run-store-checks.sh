#!/bin/zsh
set -eu

# Requires one booted iOS Simulator. Runs the real store in its own temporary directory;
# does not launch the app, import bundled catalog records, or touch an app journal.
nr_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
nr_sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
nr_test_dir="$(mktemp -d /tmp/nature-relay-store-check.XXXXXX)"
trap 'rm -rf "$nr_test_dir"' EXIT

xcrun --sdk iphonesimulator swiftc \
  -swift-version 6 \
  -target arm64-apple-ios17.0-simulator \
  -sdk "$nr_sdk_path" \
  "$nr_project_dir/NatureRelay/Models.swift" \
  "$nr_project_dir/NatureRelay/CaliforniaCatalog.swift" \
  "$nr_project_dir/NatureRelay/RelayStore.swift" \
  "$nr_project_dir/Tests/RelayStoreChecks.swift" \
  -o "$nr_test_dir/relay-store-checks"

xcrun simctl spawn booted "$nr_test_dir/relay-store-checks"
