#!/usr/bin/env bash
# Runs the synthetic media contract suite. It validates FFmpeg/ffprobe behaviour
# and fixture coverage; it does not replace GUI end-to-end testing of MP4Flow.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEEP_FIXTURES=0

usage() {
  cat <<'EOF'
Usage: Scripts/run-media-regression.sh [--keep-fixtures]

Builds tiny synthetic fixtures in a unique temporary directory, validates their
media contracts with ffprobe, then removes them. --keep-fixtures leaves the
uniquely-created temporary directory in place for diagnosis.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-fixtures)
      KEEP_FIXTURES=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
FFPROBE_BIN="${FFPROBE_BIN:-ffprobe}"
command -v "$FFMPEG_BIN" >/dev/null || { printf 'FFmpeg was not found: %s\n' "$FFMPEG_BIN" >&2; exit 69; }
command -v "$FFPROBE_BIN" >/dev/null || { printf 'ffprobe was not found: %s\n' "$FFPROBE_BIN" >&2; exit 69; }

FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mp4flow-media-regression.XXXXXX")"
[[ "$FIXTURE_DIR" == "${TMPDIR:-/tmp}"/mp4flow-media-regression.* ]] || {
  printf 'Unexpected temporary fixture location: %s\n' "$FIXTURE_DIR" >&2
  exit 70
}

cleanup() {
  if [[ "$KEEP_FIXTURES" -eq 1 ]]; then
    printf 'Keeping synthetic fixtures for inspection: %s\n' "$FIXTURE_DIR"
  else
    rm -rf "$FIXTURE_DIR"
  fi
}
trap cleanup EXIT

"$PROJECT_DIR/Scripts/generate-media-fixtures.sh" --output "$FIXTURE_DIR"

failures=0
checks=0

pass() {
  checks=$((checks + 1))
  printf 'PASS  %s\n' "$1"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL  %s\n' "$1" >&2
}

stream_value() {
  local file="$1"
  local selector="$2"
  local field="$3"
  "$FFPROBE_BIN" -v error -select_streams "$selector" -show_entries "stream=$field" \
    -of default=noprint_wrappers=1:nokey=1 "$file" | /usr/bin/head -n 1
}

stream_count() {
  local file="$1"
  local selector="$2"
  "$FFPROBE_BIN" -v error -select_streams "$selector" -show_entries stream=index \
    -of default=noprint_wrappers=1:nokey=1 "$file" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }'
}

assert_equals() {
  local description="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$description"
  else
    fail "$description (expected $expected, got ${actual:-<empty>})"
  fi
}

assert_at_least() {
  local description="$1"
  local actual="$2"
  local expected="$3"
  if /usr/bin/awk -v actual="$actual" -v expected="$expected" 'BEGIN { exit !(actual >= expected) }'; then
    pass "$description"
  else
    fail "$description (expected >= $expected, got ${actual:-<empty>})"
  fi
}

assert_decode() {
  local description="$1"
  local file="$2"
  if "$FFMPEG_BIN" -hide_banner -loglevel error -nostdin -xerror -i "$file" \
    -map 0:v:0 -map '0:a?' -f null - >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description (FFmpeg could not decode the fixture)"
  fi
}

assert_unusable() {
  local description="$1"
  local file="$2"
  local video_count
  video_count="$(stream_count "$file" v)"
  if [[ "$video_count" == 0 ]]; then
    pass "$description"
  else
    fail "$description (ffprobe found $video_count video stream(s) in intentionally truncated media)"
  fi
}

assert_equals 'H.264 fixture codec' "$(stream_value "$FIXTURE_DIR/h264-aac.mp4" v:0 codec_name)" h264
assert_equals 'HEVC fixture codec' "$(stream_value "$FIXTURE_DIR/hevc-aac.mp4" v:0 codec_name)" hevc
assert_equals 'Portrait fixture width' "$(stream_value "$FIXTURE_DIR/portrait-9x16.mp4" v:0 width)" 180
assert_equals 'Portrait fixture height' "$(stream_value "$FIXTURE_DIR/portrait-9x16.mp4" v:0 height)" 320
assert_equals 'Video-only fixture has no audio' "$(stream_count "$FIXTURE_DIR/no-audio.mp4" a)" 0
assert_equals 'Multi-audio fixture retains both tracks' "$(stream_count "$FIXTURE_DIR/multiple-audio-tracks.mp4" a)" 2
assert_equals 'Subtitle fixture retains timed text' "$(stream_count "$FIXTURE_DIR/subtitles.mp4" s)" 1
assert_equals 'Odd-size fixture width' "$(stream_value "$FIXTURE_DIR/odd-dimensions.mp4" v:0 width)" 319
assert_equals 'Odd-size fixture height' "$(stream_value "$FIXTURE_DIR/odd-dimensions.mp4" v:0 height)" 179
assert_equals 'HDR fixture codec' "$(stream_value "$FIXTURE_DIR/hdr-signalled-hevc.mp4" v:0 codec_name)" hevc
assert_equals 'HDR fixture transfer metadata' "$(stream_value "$FIXTURE_DIR/hdr-signalled-hevc.mp4" v:0 color_transfer)" smpte2084
assert_at_least 'Long-duration simulation is at least 11.5 seconds' \
  "$("$FFPROBE_BIN" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FIXTURE_DIR/long-duration-simulated.mp4")" 11.5

rotation="$("$FFPROBE_BIN" -v error -select_streams v:0 -show_entries stream_side_data=rotation \
  -of default=noprint_wrappers=1:nokey=1 "$FIXTURE_DIR/rotation-90.mp4" | /usr/bin/head -n 1)"
case "$rotation" in
  90|-270) pass 'Rotation fixture exposes a 90-degree display matrix' ;;
  *) fail "Rotation fixture exposes a 90-degree display matrix (got ${rotation:-<empty>})" ;;
esac

vfr_timestamps="$("$FFPROBE_BIN" -v error -select_streams v:0 -show_entries frame=best_effort_timestamp_time \
  -of default=noprint_wrappers=1:nokey=1 "$FIXTURE_DIR/variable-frame-rate.mp4" | /usr/bin/awk '/^[0-9]/ { print $1 }')"
if printf '%s\n' "$vfr_timestamps" | /usr/bin/awk '
  NR == 1 { previous = $1; next }
  { delta = $1 - previous; seen[sprintf("%.4f", delta)] = 1; previous = $1 }
  END { exit (NR >= 3 && length(seen) >= 2) ? 0 : 1 }
'; then
  pass 'VFR fixture has unequal frame timestamp deltas'
else
  fail 'VFR fixture has unequal frame timestamp deltas'
fi

assert_decode 'H.264 baseline decodes' "$FIXTURE_DIR/h264-aac.mp4"
assert_decode 'HEVC baseline decodes' "$FIXTURE_DIR/hevc-aac.mp4"
assert_decode 'Portrait input decodes' "$FIXTURE_DIR/portrait-9x16.mp4"
assert_decode 'No-audio input decodes' "$FIXTURE_DIR/no-audio.mp4"
assert_decode 'Multi-audio input decodes' "$FIXTURE_DIR/multiple-audio-tracks.mp4"
assert_decode 'Subtitle input video/audio decodes' "$FIXTURE_DIR/subtitles.mp4"
assert_decode 'Rotation input decodes' "$FIXTURE_DIR/rotation-90.mp4"
assert_decode 'Odd-size input decodes' "$FIXTURE_DIR/odd-dimensions.mp4"
assert_decode 'HDR-signalled input decodes' "$FIXTURE_DIR/hdr-signalled-hevc.mp4"
assert_decode 'Long-duration simulated input decodes' "$FIXTURE_DIR/long-duration-simulated.mp4"
assert_decode 'Special-character filename input decodes' "$FIXTURE_DIR/spaces ' quote [中文] #1.mp4"
assert_unusable 'Truncated input has no usable video stream' "$FIXTURE_DIR/truncated-input.mp4"

# This stream-copy check catches accidental fixture/container regressions and
# verifies that a subtitle and both audio tracks survive a lossless MP4 remux.
REMUXED="$FIXTURE_DIR/remuxed-multiple-tracks.mp4"
if "$FFMPEG_BIN" -hide_banner -loglevel error -nostdin -y -i "$FIXTURE_DIR/subtitles.mp4" \
  -map 0 -c copy -movflags +faststart "$REMUXED"; then
  assert_equals 'Lossless remux keeps the audio track' "$(stream_count "$REMUXED" a)" 1
  assert_equals 'Lossless remux keeps the subtitle track' "$(stream_count "$REMUXED" s)" 1
else
  fail 'Lossless remux of subtitle fixture completes'
fi

if [[ "$failures" -gt 0 ]]; then
  printf '\nMedia regression failed: %d of %d checks failed.\n' "$failures" "$checks" >&2
  exit 1
fi

printf '\nMedia regression passed: %d checks.\n' "$checks"
