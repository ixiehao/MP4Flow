#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
for tool in python3 plutil; do
  command -v "$tool" >/dev/null || {
    printf 'Localization validation requires %s on PATH.\n' "$tool" >&2
    exit 69
  }
done
exec python3 "$PROJECT_DIR/Scripts/validate_localizations.py"
