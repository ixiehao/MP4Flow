#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/AppResources/Info.plist")"
VOLUME_NAME="MP4Flow $VERSION Installer"
STAGE_DIR="$(mktemp -d /tmp/mp4flow-dmg.XXXXXX)"
VENV_DIR="$STAGE_DIR/venv"
APP_PATH="$STAGE_DIR/MP4Flow.app"
DMG_PATH="$OUTPUT_DIR/MP4Flow-$VERSION.dmg"
VALIDATION_MOUNT=""
VALIDATION_DEVICE=""

cleanup() {
  [[ -n "$VALIDATION_DEVICE" ]] && hdiutil detach "$VALIDATION_DEVICE" -quiet || true
  [[ -n "$VALIDATION_MOUNT" ]] && rmdir "$VALIDATION_MOUNT" 2>/dev/null || true
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
cd "$PROJECT_DIR"

PACKAGING_PYTHON=""
for candidate in "${PACKAGING_PYTHON:-}" /opt/homebrew/opt/python@3.14/bin/python3.14 /opt/homebrew/bin/python3 /usr/local/bin/python3 python3; do
  [[ -n "$candidate" ]] || continue
  if "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' 2>/dev/null; then
    PACKAGING_PYTHON="$candidate"
    break
  fi
done
[[ -n "$PACKAGING_PYTHON" ]] || { printf 'Packaging requires Python 3.10 or newer. Set PACKAGING_PYTHON to its executable.\n' >&2; exit 1; }

if [[ "$(uname -m)" == "arm64" ]]; then
  MP4FLOW_ARCHS="arm64 x86_64" APP_OUTPUT_PATH="$APP_PATH" ./Scripts/build-app.sh
else
  APP_OUTPUT_PATH="$APP_PATH" ./Scripts/build-app.sh
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
swift Scripts/create-dmg-background.swift "$STAGE_DIR/dmg-background.png"
"$PACKAGING_PYTHON" -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --quiet -r Scripts/dmg-requirements.txt
"$VENV_DIR/bin/dmgbuild" -s Scripts/dmg-settings.py -D app="$APP_PATH" -D background="$STAGE_DIR/dmg-background.png" "$VOLUME_NAME" "$DMG_PATH"
hdiutil verify "$DMG_PATH"
VALIDATION_MOUNT="$(mktemp -d /tmp/mp4flow-installer-check.XXXXXX)"
ATTACH_OUTPUT="$(hdiutil attach -readonly -noverify -noautoopen -mountpoint "$VALIDATION_MOUNT" "$DMG_PATH")"
VALIDATION_DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"
[[ -n "$VALIDATION_DEVICE" ]] || { printf 'Unable to mount final DMG for verification.\n' >&2; exit 1; }
"$VENV_DIR/bin/python3" Scripts/verify-dmg-layout.py "$VALIDATION_MOUNT" "MP4Flow.app"
codesign --verify --deep --strict --verbose=2 "$VALIDATION_MOUNT/MP4Flow.app"
if [[ "$(uname -m)" == "arm64" ]]; then
  architectures="$(lipo -archs "$VALIDATION_MOUNT/MP4Flow.app/Contents/MacOS/MP4Flow")"
  [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || { printf 'DMG must contain arm64 and x86_64.\n' >&2; exit 1; }
fi
hdiutil detach "$VALIDATION_DEVICE" -quiet
VALIDATION_DEVICE=""
rmdir "$VALIDATION_MOUNT"
VALIDATION_MOUNT=""
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
printf 'Created %s\n' "$DMG_PATH"
