#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ARCHITECTURE="${MP4FLOW_ARCH:-${MP4FLOW_ARCHS:-$(uname -m)}}"
[[ "$ARCHITECTURE" == arm64 || "$ARCHITECTURE" == x86_64 ]] || {
  printf 'MP4FLOW_ARCH must be arm64 or x86_64; build each native app separately.\n' >&2
  exit 2
}
python3 "$PROJECT_DIR/Scripts/build_contract.py" metadata "$PROJECT_DIR" LSMinimumSystemVersion >/dev/null
APP_PATH="$(python3 "$PROJECT_DIR/Scripts/build_contract.py" app-destination "$PROJECT_DIR" "${APP_OUTPUT_PATH:-$PROJECT_DIR/MP4Flow.app}")"
APP_PARENT="$(dirname "$APP_PATH")"
SCRATCH_PATH="$PROJECT_DIR/.build/native-$ARCHITECTURE"
LOCK_PATH="$PROJECT_DIR/.build/app-$ARCHITECTURE.lock"
STAGE_DIR=""
LOCK_ACQUIRED=false
cleanup() {
  [[ -z "$STAGE_DIR" ]] || rm -rf "$STAGE_DIR"
  if $LOCK_ACQUIRED; then rm -f "$LOCK_PATH/pid"; rmdir "$LOCK_PATH"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$PROJECT_DIR/.build" "$APP_PARENT"
if ! mkdir "$LOCK_PATH" 2>/dev/null; then
  printf 'Another %s app build holds %s.\n' "$ARCHITECTURE" "$LOCK_PATH" >&2
  exit 75
fi
LOCK_ACQUIRED=true
printf '%s\n' "$$" > "$LOCK_PATH/pid"
STAGE_DIR="$(mktemp -d "$APP_PARENT/.mp4flow-app.XXXXXX")"
[[ -n "$STAGE_DIR" && -d "$STAGE_DIR" && "$STAGE_DIR" == "$APP_PARENT/.mp4flow-app."* ]] || {
  STAGE_DIR=""; printf 'Unable to create an owned app staging directory.\n' >&2; exit 1
}
STAGED_APP="$STAGE_DIR/MP4Flow.app"
cd "$PROJECT_DIR"
export MACOSX_DEPLOYMENT_TARGET=13.0
BUILD_ARGS=(-c release --arch "$ARCHITECTURE" --scratch-path "$SCRATCH_PATH" -Xswiftc -strict-concurrency=complete)
swift build "${BUILD_ARGS[@]}"
BINARY_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
[[ -n "$BINARY_DIR" && -f "$BINARY_DIR/MP4Flow" ]] || { printf 'Missing built executable.\n' >&2; exit 1; }
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BINARY_DIR/MP4Flow" "$STAGED_APP/Contents/MacOS/MP4Flow"
cp AppResources/Info.plist "$STAGED_APP/Contents/Info.plist"
cp AppResources/AppIcon.icns AppResources/ASSET_NOTICES.md "$STAGED_APP/Contents/Resources/"
for localization in AppResources/*.lproj; do
  cp -R "$localization" "$STAGED_APP/Contents/Resources/"
done
for resource_bundle in "$BINARY_DIR"/*.bundle; do
  [[ -e "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$STAGED_APP/Contents/Resources/"
done
xattr -cr "$STAGED_APP"
codesign --force --sign - --timestamp=none "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
python3 Scripts/verify_native_binary.py --arch "$ARCHITECTURE" --bundle "$STAGED_APP"
# Unlike mv, exclusive rename cannot merge into a destination created after preflight.
python3 Scripts/build_contract.py publish "$STAGED_APP" "$APP_PATH"
printf 'Built %s (%s)\n' "$APP_PATH" "$ARCHITECTURE"
