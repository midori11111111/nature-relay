#!/bin/zsh
set -eu

# Uses actual manifest/photos, but never opens or changes the user's journal.
nr_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
nr_sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
nr_test_dir="$(mktemp -d /tmp/nature-relay-character-check.XXXXXX)"
trap 'rm -rf "$nr_test_dir"' EXIT

xcrun --sdk iphonesimulator swiftc \
  -swift-version 6 \
  -target arm64-apple-ios17.0-simulator \
  -sdk "$nr_sdk_path" \
  "$nr_project_dir/NatureRelay/Models.swift" \
  "$nr_project_dir/NatureRelay/SpeciesACollection.swift" \
  "$nr_project_dir/NatureRelay/SpeciesCharacterCatalog.swift" \
  "$nr_project_dir/Tests/SpeciesCharacterChecks.swift" \
  -o "$nr_test_dir/species-character-checks"

xcrun simctl spawn booted "$nr_test_dir/species-character-checks" "$nr_project_dir" "$@"
