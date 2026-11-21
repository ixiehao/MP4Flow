#!/bin/bash
set -euo pipefail
work="$RUNNER_TEMP/mp4flow-tutorials"
mkdir -p "$work"/{mount,public}
cd "$work"
id
stat -f '%Su' /dev/console
repo="$GITHUB_WORKSPACE"
xcrun swiftc "$repo/.github/tutorial-qa/Exercise.swift" -o exercise
./exercise preflight
url=https://github.com/ixiehao/MP4Flow/releases/download/v1.5.3
stem=MP4Flow-1.5.3-arm64.dmg
curl -fsSL --retry 3 "$url/$stem" -o "$stem"
curl -fsSL --retry 3 "$url/$stem.sha256" -o "$stem.sha256"
shasum -a 256 -c "$stem.sha256"
hdiutil attach -readonly -nobrowse -mountpoint "$work/mount" "$stem" -quiet
trap 'hdiutil detach "$work/mount" -quiet || true' EXIT
codesign --verify --deep --strict "$work/mount/MP4Flow.app"
if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then brew install ffmpeg; fi
ffmpeg -v error -f lavfi -i 'testsrc2=s=640x360:r=30' -t 12 -an -c:v libx264 -b:v 2M -minrate 2M -maxrate 2M -bufsize 4M -x264-params nal-hrd=cbr public/Patterns.mkv
sha=$(shasum -a 256 public/Patterns.mkv | cut -d' ' -f1)
for lang in en zh ja; do
  code="$lang"
  if [[ $lang == zh ]]; then code=zh-Hans; fi
  app="$work/MP4Flow-Guide-$lang.app"
  bundle="com.ixiehao.mp4flow.tutorialisolation.$lang"
  ditto "$work/mount/MP4Flow.app" "$app"
  plutil -replace CFBundleIdentifier -string "$bundle" "$app/Contents/Info.plist"
  codesign --force --sign - "$app"
  defaults write "$bundle" appLanguage -string "$code"
  defaults write "$bundle" com.ixiehao.MP4Flow.updates.automaticChecksEnabled -bool false
  for task in convert trim size; do
    dir="$work/$lang-$task"
    mkdir -p "$dir"
    cp public/Patterns.mkv "$dir/Patterns.mkv"
    python3 - "$bundle" "$dir/Patterns.mkv" "$task" <<'PY'
import json, sys, uuid
from pathlib import Path
bundle, source, task = sys.argv[1:]
folder = Path.home()/'Library/Application Support'/('MP4Flow-'+bundle)
folder.mkdir(mode=0o700, exist_ok=True)
options = {'audio':'all','subtitles':'none'}
if task == 'size':
    options['targetSizeMB'] = 1
job = {'id': str(uuid.uuid4()), 'source': Path(source).as_uri(), 'brightness': 0, 'shadows': 0, 'denoise': False, 'options':options}
if task == 'trim':
    job['trim'] = [3.0, 8.0]
snapshot = {'version':1, 'preset':'smartMP4', 'quality':'balanced', 'resolution':'original', 'enhanceTarget':720, 'jobs':[job]}
(folder/'queue-v1.json').write_text(json.dumps(snapshot))
PY
    open -n "$app"
    ./exercise "$app" "$bundle" "$code" "$task" "$work/public/$task-$lang.png"
    output="$dir/Patterns-MP4FlowConverted.mp4"
    ffmpeg -v error -i "$output" -f null -
    ffprobe -v error -show_entries 'stream=codec_name,width,height:format=duration,size' -of json "$output" > "$work/public/$task-$lang.json"
    test "$(shasum -a 256 "$dir/Patterns.mkv" | cut -d' ' -f1)" = "$sha"
  done
done
