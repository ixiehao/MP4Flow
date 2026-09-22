#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

plutil -lint AppResources/Info.plist
plutil -lint AppResources/en.lproj/Localizable.strings
plutil -lint AppResources/zh-Hans.lproj/Localizable.strings

missing=0
while IFS= read -r key; do
  if ! rg -F --quiet "\"$key\" =" AppResources/en.lproj/Localizable.strings; then
    printf 'Missing English localization for dynamic key: %s\n' "$key" >&2
    missing=1
  fi
done < <(rg -o 'L10n\.(text|format)\("[^"]+"' Sources/FastConvert \
  | sed -E 's/.*L10n\.(text|format)\("([^"]+)".*/\2/' \
  | sort -u)

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

printf 'Localization validation passed.\n'
