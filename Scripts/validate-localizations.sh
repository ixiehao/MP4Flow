#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

for tool in plutil rg jq perl sed sort base64; do
  command -v "$tool" >/dev/null || {
    printf 'Localization validation requires %s on PATH.\n' "$tool" >&2
    exit 69
  }
done

plutil -lint AppResources/Info.plist

missing=0
for language in en ja zh-Hans; do
  localization_file="AppResources/$language.lproj/Localizable.strings"
  plutil -lint "$localization_file"
  # plutil accepts repeated keys and keeps only the last value. Inspect entries
  # before conversion, skipping comments and consuming each complete value.
  if ! duplicate_keys="$(perl -0777 -ne '
    while (m{/\*.*?\*/|//[^\n]*|("(?:\\.|[^"\\])*")\s*=\s*"(?:\\.|[^"\\])*"\s*;}sg) {
      next unless defined $1;
      print "$1\n" if $seen{$1}++ == 1;
    }
  ' "$localization_file")"; then
    printf 'Unable to inspect localization keys: %s\n' "$localization_file" >&2
    exit 1
  fi
  if [[ -n "$duplicate_keys" ]]; then
    printf 'Duplicate localization keys in %s:\n%s\n' "$localization_file" "$duplicate_keys" >&2
    missing=1
  fi
done

# Capture fallible pipelines in the main shell so pipefail can stop validation.
# A failing command inside process substitution would otherwise look like EOF.
if ! dynamic_keys="$(rg --no-filename -o 'L10n\.(text|format)\("[^"]+"|(reasonKey|solutionKey): "[^"]+"' Sources/FastConvert \
  | sed -E 's/.*L10n\.(text|format)\("([^"]+)".*/\2/; s/.*(reasonKey|solutionKey): "([^"]+)".*/\2/' \
  | sort -u)"; then
  printf 'Unable to extract dynamic localization keys.\n' >&2
  exit 1
fi

while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  for language in en ja; do
    if ! rg -F --quiet "\"$key\" =" "AppResources/$language.lproj/Localizable.strings"; then
      printf 'Missing %s localization for dynamic key: %s\n' "$language" "$key" >&2
      missing=1
    fi
  done
done <<< "$dynamic_keys"

english_keys="$(plutil -convert json -o - AppResources/en.lproj/Localizable.strings | jq -c 'keys')"
japanese_keys="$(plutil -convert json -o - AppResources/ja.lproj/Localizable.strings | jq -c 'keys')"
missing_interface_keys="$(jq -nr --argjson english "$english_keys" --argjson japanese "$japanese_keys" \
  '($english - $japanese)[] | @base64')"

# Base64 keeps the comparison line-oriented even when an interface key itself
# contains newlines (for example, the FFmpeg installation instructions).
while IFS= read -r encoded_key; do
  [[ -n "$encoded_key" ]] || continue
  printf 'Missing Japanese localization for interface key: ' >&2
  printf '%s' "$encoded_key" | base64 -D
  printf '\n' >&2
  missing=1
done <<< "$missing_interface_keys"

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

printf 'Localization validation passed.\n'
