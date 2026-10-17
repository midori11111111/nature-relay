#!/bin/zsh
set -eu

# Requires one booted iOS Simulator. This does not modify or launch the app.
# Optional arguments: photo path, expected category, directory for synthetic metadata fixtures.
nr_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
nr_sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
nr_test_dir="$(mktemp -d /tmp/nature-relay-photo-check.XXXXXX)"
trap 'rm -rf "$nr_test_dir"' EXIT

xcrun --sdk iphonesimulator swiftc \
  -swift-version 6 \
  -target arm64-apple-ios17.0-simulator \
  -sdk "$nr_sdk_path" \
  "$nr_project_dir/NatureRelay/Models.swift" \
  "$nr_project_dir/NatureRelay/PhotoRecognitionService.swift" \
  "$nr_project_dir/Tests/PhotoRecognitionChecks.swift" \
  -o "$nr_test_dir/photo-checks"

nr_photo_path="${1:-$nr_project_dir/Resources/CaliforniaCatalog/photos/inat-108094155-181928247.jpg}"
nr_photo_path="${nr_photo_path:A}"
nr_fixture_directory="${3:-}"
if [[ -n "$nr_fixture_directory" ]]; then
  nr_fixture_directory="${nr_fixture_directory:A}"
fi
xcrun simctl spawn "${SIMULATOR_UDID:-booted}" "$nr_test_dir/photo-checks" \
  "$nr_photo_path" \
  "$nr_project_dir/NatureRelay/MobileNetV2FP16.mlmodelc" \
  "${2:-}" \
  "$nr_fixture_directory"
