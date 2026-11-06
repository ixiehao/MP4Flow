#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ARCHITECTURE="all"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
PREFLIGHT_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch|--output-dir)
      [[ $# -ge 2 && -n "$2" ]] || { printf 'Missing option value.\n' >&2; exit 2; }
      case "$1" in --arch) ARCHITECTURE="$2" ;; --output-dir) OUTPUT_DIR="$2" ;; esac
      shift 2 ;;
    --preflight-only) PREFLIGHT_ONLY=true; shift ;;
    --help|-h)
      printf 'Usage: %s [--arch all|arm64|x86_64] [--output-dir PATH] [--preflight-only]\n' "$0"
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
case "$ARCHITECTURE" in
  all) ARCHITECTURES=(arm64 x86_64) ;;
  arm64|x86_64) ARCHITECTURES=("$ARCHITECTURE") ;;
  *) printf 'Choose all, arm64 or x86_64.\n' >&2; exit 2 ;;
esac
VERSION="$(python3 "$PROJECT_DIR/Scripts/build_contract.py" metadata "$PROJECT_DIR" CFBundleShortVersionString)"
[[ ! -L "$OUTPUT_DIR" && ( ! -e "$OUTPUT_DIR" || -d "$OUTPUT_DIR" ) ]] || {
  printf 'Output must be a real directory.\n' >&2; exit 1
}
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
for target in "${ARCHITECTURES[@]}"; do
  DESTINATION="$OUTPUT_DIR/MP4Flow-$VERSION-$target"
  [[ ! -e "$DESTINATION" && ! -L "$DESTINATION" ]] || {
    printf 'Refusing to replace %s; choose a new output directory.\n' "$DESTINATION" >&2; exit 1
  }
done
if $PREFLIGHT_ONLY; then exit 0; fi

STAGE_DIR=""
APP_BUILD_DIR=""
VALIDATION_MOUNT=""
MOUNTED=false
LOCK_PATH="$PROJECT_DIR/.build/package-dmg.lock"
LOCK_ACQUIRED=false
cleanup() {
  if $MOUNTED; then
    if ! hdiutil detach "$VALIDATION_MOUNT" -quiet; then
      printf 'Preserving mounted staging files and lock: %s\n' "$STAGE_DIR" >&2
      return
    fi
  fi
  [[ -z "$VALIDATION_MOUNT" ]] || rmdir "$VALIDATION_MOUNT" 2>/dev/null || true
  [[ -z "$STAGE_DIR" ]] || rm -rf "$STAGE_DIR"
  [[ -z "$APP_BUILD_DIR" ]] || rm -rf "$APP_BUILD_DIR"
  if $LOCK_ACQUIRED; then rm -f "$LOCK_PATH/pid"; rmdir "$LOCK_PATH"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$PROJECT_DIR/.build"
if ! mkdir "$LOCK_PATH" 2>/dev/null; then
  printf 'Another installer build holds %s.\n' "$LOCK_PATH" >&2; exit 75
fi
LOCK_ACQUIRED=true
printf '%s\n' "$$" > "$LOCK_PATH/pid"
SOURCE_IDENTITY="$(python3 "$PROJECT_DIR/Scripts/build_contract.py" source-identity "$PROJECT_DIR")"
PACKAGING_PYTHON_PATH=""
for candidate in "${PACKAGING_PYTHON:-}" /opt/homebrew/bin/python3 /usr/local/bin/python3 python3; do
  [[ -n "$candidate" ]] || continue
  if "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' 2>/dev/null; then
    PACKAGING_PYTHON_PATH="$candidate"; break
  fi
done
[[ -n "$PACKAGING_PYTHON_PATH" ]] || { printf 'Packaging requires Python 3.10+.\n' >&2; exit 1; }
TOOLS_DIR="$PROJECT_DIR/.build/dmg-tools"
cd "$PROJECT_DIR"
for target in "${ARCHITECTURES[@]}"; do
  ARTIFACT_NAME="MP4Flow-$VERSION-$target"
  DESTINATION="$OUTPUT_DIR/$ARTIFACT_NAME"
  STAGE_DIR="$(mktemp -d "$OUTPUT_DIR/.mp4flow-$target.XXXXXX")"
  [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" && "$STAGE_DIR" == "$OUTPUT_DIR/.mp4flow-$target."* ]] || {
    STAGE_DIR=""; printf 'Unable to create an owned installer staging directory.\n' >&2; exit 1
  }
  APP_PATH="$STAGE_DIR/MP4Flow.app"
  SYMBOLS_PATH="$STAGE_DIR/MP4Flow.app.dSYM"
  DMG_PATH="$STAGE_DIR/$ARTIFACT_NAME.dmg"
  # Keep the compiler's own TMPDIR unchanged: a long/non-ASCII installer path
  # can exceed Darwin's short compiler/IPC temporary-path budget. The app-only
  # builder works in an owned system-temp directory, then we move the completed
  # bundle into this installer's still-unpublished group.
  APP_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mp4flow-native-app.XXXXXX")"
  [[ -n "$APP_BUILD_DIR" && -d "$APP_BUILD_DIR" ]] || {
    APP_BUILD_DIR=""; printf 'Unable to create an app build directory.\n' >&2; exit 1
  }
  MP4FLOW_ARCH="$target" APP_OUTPUT_PATH="$APP_BUILD_DIR/MP4Flow.app" ./Scripts/build-app.sh
  mv "$APP_BUILD_DIR/MP4Flow.app" "$APP_PATH"
  rmdir "$APP_BUILD_DIR"
  APP_BUILD_DIR=""
  xcrun dsymutil "$APP_PATH/Contents/MacOS/MP4Flow" -o "$SYMBOLS_PATH"
  xcrun strip -S -x "$APP_PATH/Contents/MacOS/MP4Flow"
  codesign --force --sign - --timestamp=none "$APP_PATH"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  python3 Scripts/verify_native_binary.py --arch "$target" --symbols "$SYMBOLS_PATH" --bundle "$APP_PATH"
  if [[ ! -x "$TOOLS_DIR/bin/python3" ]]; then "$PACKAGING_PYTHON_PATH" -m venv "$TOOLS_DIR"; fi
  "$TOOLS_DIR/bin/python3" -m pip install --disable-pip-version-check --quiet -r Scripts/dmg-requirements.txt
  swift Scripts/create-dmg-background.swift "$STAGE_DIR/background.png" "$target"
  "$TOOLS_DIR/bin/dmgbuild" -s Scripts/dmg-settings.py -D app="$APP_PATH" -D background="$STAGE_DIR/background.png" \
    "MP4Flow $VERSION $target Installer" "$DMG_PATH"
  hdiutil verify "$DMG_PATH"
  VALIDATION_MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/mp4flow-installer-check.XXXXXX")"
  [[ -n "$VALIDATION_MOUNT" && -d "$VALIDATION_MOUNT" ]] || {
    VALIDATION_MOUNT=""; printf 'Unable to create a validation mount.\n' >&2; exit 1
  }
  if ! hdiutil attach -readonly -noverify -noautoopen -mountpoint "$VALIDATION_MOUNT" "$DMG_PATH" >/dev/null; then
    [[ ! -d "$VALIDATION_MOUNT/MP4Flow.app" ]] || MOUNTED=true
    printf 'Unable to mount final installer.\n' >&2; exit 1
  fi
  MOUNTED=true
  "$TOOLS_DIR/bin/python3" Scripts/verify-dmg-layout.py "$VALIDATION_MOUNT" MP4Flow.app
  codesign --verify --deep --strict --verbose=2 "$VALIDATION_MOUNT/MP4Flow.app"
  python3 Scripts/verify_native_binary.py --arch "$target" --symbols "$SYMBOLS_PATH" --bundle "$VALIDATION_MOUNT/MP4Flow.app"
  hdiutil detach "$VALIDATION_MOUNT" -quiet
  MOUNTED=false
  rmdir "$VALIDATION_MOUNT"
  VALIDATION_MOUNT=""
  (cd "$STAGE_DIR" && shasum -a 256 "$ARTIFACT_NAME.dmg" > "$ARTIFACT_NAME.dmg.sha256")
  [[ "$SOURCE_IDENTITY" == "$(python3 Scripts/build_contract.py source-identity "$PROJECT_DIR")" ]] || {
    printf 'Source changed during packaging; refusing publication.\n' >&2; exit 1
  }
  python3 Scripts/build_contract.py provenance "$PROJECT_DIR" "$target" "$STAGE_DIR/build-provenance.json"
  rm "$STAGE_DIR/background.png"
  python3 Scripts/build_contract.py publish "$STAGE_DIR" "$DESTINATION"
  STAGE_DIR=""
  printf 'Created %s/%s.dmg\n' "$DESTINATION" "$ARTIFACT_NAME"
done
