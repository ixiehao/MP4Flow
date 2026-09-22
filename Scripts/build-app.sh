#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${APP_OUTPUT_PATH:-$PROJECT_DIR/MP4Flow.app}"
[[ "$APP_PATH" == *.app && "$APP_PATH" != "/" ]] || {
  printf 'APP_OUTPUT_PATH must name a .app bundle.\n' >&2
  exit 1
}
cd "$PROJECT_DIR"
BUILD_ARGS=(-c release)
if [[ -n "${MP4FLOW_ARCHS:-}" ]]; then
  for arch in ${=MP4FLOW_ARCHS}; do BUILD_ARGS+=(--arch "$arch"); done
fi
swift build "${BUILD_ARGS[@]}"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources/Fonts"
cp .build/release/MP4Flow "$APP_PATH/Contents/MacOS/MP4Flow"
cp AppResources/Info.plist "$APP_PATH/Contents/Info.plist"
cp AppResources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
cp AppResources/NotoSansSC-Variable.ttf "$APP_PATH/Contents/Resources/Fonts/NotoSansSC-Variable.ttf"
cp AppResources/OFL.txt "$APP_PATH/Contents/Resources/Fonts/OFL.txt"
cp AppResources/ASSET_NOTICES.md "$APP_PATH/Contents/Resources/ASSET_NOTICES.md"
cp -R AppResources/en.lproj AppResources/zh-Hans.lproj "$APP_PATH/Contents/Resources/"
# Resource forks and Finder attributes create AppleDouble files in ordinary ZIPs,
# invalidating the sealed code signature after extraction.
xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --force --sign - "$APP_PATH"
echo "Built $APP_PATH"
