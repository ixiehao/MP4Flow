#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

plutil -lint AppResources/Info.plist
plutil -lint AppResources/en.lproj/Localizable.strings
plutil -lint AppResources/ja.lproj/Localizable.strings
plutil -lint AppResources/zh-Hans.lproj/Localizable.strings

missing=0
while IFS= read -r key; do
  for language in en ja; do
    if ! rg -F --quiet "\"$key\" =" "AppResources/$language.lproj/Localizable.strings"; then
      printf 'Missing %s localization for dynamic key: %s\n' "$language" "$key" >&2
      missing=1
    fi
  done
done < <(rg -o 'L10n\.(text|format)\("[^"]+"|(reasonKey|solutionKey): "[^"]+"' Sources/FastConvert \
  | sed -E 's/.*L10n\.(text|format)\("([^"]+)".*/\2/; s/.*(reasonKey|solutionKey): "([^"]+)".*/\2/' \
  | sort -u)

# Base64 keeps the comparison line-oriented even when an interface key itself
# contains newlines (for example, the FFmpeg installation instructions).
while IFS= read -r encoded_key; do
  [[ -n "$encoded_key" ]] || continue
  printf 'Missing Japanese localization for interface key: ' >&2
  printf '%s' "$encoded_key" | base64 -D
  printf '\n' >&2
  missing=1
done < <(
  comm -23 \
    <(plutil -convert json -o - AppResources/en.lproj/Localizable.strings | jq -r 'keys[] | @base64' | sort) \
    <(plutil -convert json -o - AppResources/ja.lproj/Localizable.strings | jq -r 'keys[] | @base64' | sort)
)

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

printf 'Localization validation passed.\n'
