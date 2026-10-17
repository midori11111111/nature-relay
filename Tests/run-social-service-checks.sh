#!/bin/zsh
set -eu

# Requires one booted iOS Simulator. Uses in-memory credentials and fixture responses only.
# No app launch, Keychain writes, paid calls or free-service quota are used.
nr_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
nr_sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
nr_test_dir="$(mktemp -d /tmp/nature-relay-social-check.XXXXXX)"
trap 'rm -rf "$nr_test_dir"' EXIT

xcrun --sdk iphonesimulator swiftc \
  -swift-version 5 \
  -target arm64-apple-ios17.0-simulator \
  -sdk "$nr_sdk_path" \
  "$nr_project_dir/NatureRelay/Models.swift" \
  "$nr_project_dir/NatureRelay/SocialAPIService.swift" \
  "$nr_project_dir/NatureRelay/CommunityMapping.swift" \
  "$nr_project_dir/Tests/SocialServiceChecks.swift" \
  -o "$nr_test_dir/social-service-checks"

xcrun simctl spawn booted "$nr_test_dir/social-service-checks"
