#!/bin/bash

set -euo pipefail

VERSION="${1:?usage: verify-release-artifacts.sh VERSION [ARTIFACT_DIRECTORY]}"
ARTIFACT_DIR="${2:-.}"
DMG="$ARTIFACT_DIR/Snapper-$VERSION.dmg"
ZIP="$ARTIFACT_DIR/Snapper-$VERSION.zip"
WORK_DIR="$(mktemp -d)"
MOUNT_POINT="$WORK_DIR/dmg"
MOUNTED=false

cleanup() {
  if [ "$MOUNTED" = true ]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

verify_app() {
  local app="$1"
  local source="$2"

  if [ ! -d "$app" ]; then
    echo "Snapper.app is missing from $source" >&2
    exit 1
  fi

  codesign --verify --deep --strict --verbose=2 "$app"
  codesign -dv --verbose=4 "$app" 2>&1 | grep -q '^Authority=Developer ID Application:'
  spctl --assess --type execute --verbose=4 "$app"
  xcrun stapler validate "$app"

  local plist="$app/Contents/Info.plist"
  test "$(plutil -extract CFBundlePackageType raw "$plist")" = "APPL"
  test "$(plutil -extract CFBundleShortVersionString raw "$plist")" = "$VERSION"
  test -n "$(plutil -extract CFBundleVersion raw "$plist")"
}

test -f "$DMG"
test -f "$ZIP"

mkdir -p "$WORK_DIR/zip"
ditto -x -k "$ZIP" "$WORK_DIR/zip"
verify_app "$WORK_DIR/zip/Snapper.app" "the ZIP"

mkdir -p "$MOUNT_POINT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG" >/dev/null
MOUNTED=true
verify_app "$MOUNT_POINT/Snapper.app" "the DMG"

if [ -f "$ARTIFACT_DIR/Snapper-latest.dmg" ]; then
  cmp "$DMG" "$ARTIFACT_DIR/Snapper-latest.dmg"
fi

echo "Verified signed and notarized Snapper $VERSION release artifacts."
