#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

bash scripts/build-app.sh

APP_PATH="$PROJECT_ROOT/dist/Colima View.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
APP_ARCH="$(lipo -archs "$APP_PATH/Contents/MacOS/ColimaDesk")"

case "$APP_ARCH" in
  arm64|x86_64) ;;
  *) printf 'Unsupported release architecture: %s\n' "$APP_ARCH" >&2; exit 1 ;;
esac

ARCHIVE_NAME="Colima-View-$APP_VERSION-macos-$APP_ARCH.zip"
ARCHIVE_PATH="$PROJECT_ROOT/dist/$ARCHIVE_NAME"
STAGING_DIR="$(mktemp -d "$PROJECT_ROOT/dist/.release-stage.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/Colima View.app"

# Finder can add metadata to the running local app. Package an isolated copy.
ditto --norsrc --noextattr "$APP_PATH" "$STAGED_APP"
xattr -cr "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
ditto -c -k --keepParent --norsrc --noextattr "$STAGED_APP" "$ARCHIVE_PATH"
(
  cd "$PROJECT_ROOT/dist"
  shasum -a 256 "$ARCHIVE_NAME" > SHA256SUMS.txt
)

printf '\nRelease archive: %s\nChecksum: %s\n' "$ARCHIVE_PATH" "$PROJECT_ROOT/dist/SHA256SUMS.txt"
