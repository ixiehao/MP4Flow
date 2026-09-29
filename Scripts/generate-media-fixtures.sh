#!/usr/bin/env bash
# Creates deliberately tiny, synthetic media files for MP4Flow regression tests.
# Nothing in this directory is licensed production content or should be released.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Scripts/generate-media-fixtures.sh --output DIRECTORY

Create a deterministic, small fixture matrix using the installed FFmpeg and
ffprobe. DIRECTORY must be empty (or not yet exist); this guard prevents
accidental replacement of a media collection.
EOF
}

OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      OUTPUT_DIR="$2"
      shift 2
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

[[ -n "$OUTPUT_DIR" ]] || { usage >&2; exit 64; }
[[ "$OUTPUT_DIR" != "/" ]] || { printf 'Refusing to use the filesystem root as fixture output.\n' >&2; exit 64; }

FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
FFPROBE_BIN="${FFPROBE_BIN:-ffprobe}"
command -v "$FFMPEG_BIN" >/dev/null || { printf 'FFmpeg was not found: %s\n' "$FFMPEG_BIN" >&2; exit 69; }
command -v "$FFPROBE_BIN" >/dev/null || { printf 'ffprobe was not found: %s\n' "$FFPROBE_BIN" >&2; exit 69; }

if [[ -e "$OUTPUT_DIR" ]]; then
  [[ -d "$OUTPUT_DIR" ]] || { printf 'Fixture output exists and is not a directory: %s\n' "$OUTPUT_DIR" >&2; exit 73; }
  [[ -z "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
    printf 'Fixture output must be empty: %s\n' "$OUTPUT_DIR" >&2
    exit 73
  }
else
  mkdir -p "$OUTPUT_DIR"
fi

run_ffmpeg() {
  command "$FFMPEG_BIN" -hide_banner -loglevel error -nostdin -y "$@"
}

probe_video() {
  "$FFPROBE_BIN" -v error -select_streams v:0 \
    -show_entries stream=width,height,codec_name -of default=noprint_wrappers=1 "$1"
}

require_encoder() {
  local encoder="$1"
  local encoders
  encoders="$(command "$FFMPEG_BIN" -hide_banner -encoders 2>/dev/null)"
  [[ "$encoders" == *" $encoder "* ]] || {
    printf 'Required FFmpeg encoder is unavailable: %s\n' "$encoder" >&2
    exit 69
  }
}

require_encoder libx264
require_encoder libx265

H264="$OUTPUT_DIR/h264-aac.mp4"
run_ffmpeg \
  -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1.2' \
  -f lavfi -i 'sine=frequency=880:sample_rate=48000:duration=1.2' \
  -map 0:v:0 -map 1:a:0 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 28 -g 24 \
  -c:a aac -b:a 64k -movflags +faststart "$H264"

run_ffmpeg \
  -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1.2' \
  -f lavfi -i 'sine=frequency=660:sample_rate=48000:duration=1.2' \
  -map 0:v:0 -map 1:a:0 -c:v libx265 -pix_fmt yuv420p -preset ultrafast \
  -x265-params 'pools=1:frame-threads=1:log-level=error' -c:a aac -b:a 64k \
  -movflags +faststart "$OUTPUT_DIR/hevc-aac.mp4"

# Keep source timestamps after frame selection; the unequal gaps form a VFR file.
run_ffmpeg \
  -f lavfi -i 'testsrc2=size=320x180:rate=30:duration=1' \
  -vf "select='eq(n,0)+eq(n,1)+eq(n,4)+eq(n,10)+eq(n,18)',setpts=PTS-STARTPTS" \
  -fps_mode vfr -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 28 \
  -an "$OUTPUT_DIR/variable-frame-rate.mp4"

run_ffmpeg \
  -f lavfi -i 'testsrc2=size=180x320:rate=24:duration=1.2' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1.2' \
  -map 0:v:0 -map 1:a:0 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 28 \
  -c:a aac -b:a 64k -movflags +faststart "$OUTPUT_DIR/portrait-9x16.mp4"

run_ffmpeg \
  -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1.2' \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 28 -an \
  -movflags +faststart "$OUTPUT_DIR/no-audio.mp4"

run_ffmpeg \
  -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=1.2' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=1.2' \
  -f lavfi -i 'sine=frequency=880:sample_rate=48000:duration=1.2' \
  -map 0:v:0 -map 1:a:0 -map 2:a:0 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 28 \
  -c:a aac -b:a 64k -metadata:s:a:0 language=eng -metadata:s:a:1 language=fra \
  -movflags +faststart "$OUTPUT_DIR/multiple-audio-tracks.mp4"

cat > "$OUTPUT_DIR/captions.srt" <<'EOF'
1
00:00:00,100 --> 00:00:00,800
MP4Flow synthetic subtitle sample

EOF
run_ffmpeg -i "$H264" -f srt -i "$OUTPUT_DIR/captions.srt" \
  -map 0:v:0 -map 0:a:0 -map 1:0 -c:v copy -c:a copy -c:s mov_text \
  -metadata:s:s:0 language=eng -movflags +faststart "$OUTPUT_DIR/subtitles.mp4"

# A display matrix tests rotation metadata independently of encoded dimensions.
run_ffmpeg -display_rotation:v:0 90 -i "$H264" -map 0 -c copy \
  -movflags +faststart "$OUTPUT_DIR/rotation-90.mp4"

# yuv444p allows an intentionally odd encoded size, a common scale edge case.
run_ffmpeg \
  -f lavfi -i 'testsrc=size=319x179:rate=24:duration=1.2' \
  -c:v libx264 -pix_fmt yuv444p -preset veryfast -crf 28 -an \
  -movflags +faststart "$OUTPUT_DIR/odd-dimensions.mp4"

# This uses real HDR signalling rather than claiming that a colour-bar is HDR content.
run_ffmpeg \
  -f lavfi -i 'testsrc2=size=160x90:rate=24:duration=1.2' \
  -c:v libx265 -pix_fmt yuv420p10le -preset ultrafast \
  -x265-params 'pools=1:frame-threads=1:log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc' \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -an \
  -movflags +faststart "$OUTPUT_DIR/hdr-signalled-hevc.mp4"

# Twelve seconds at 160x90 is small enough for CI but still exercises duration math.
run_ffmpeg \
  -f lavfi -i 'testsrc2=size=160x90:rate=10:duration=12' \
  -f lavfi -i 'sine=frequency=330:sample_rate=48000:duration=12' \
  -map 0:v:0 -map 1:a:0 -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 32 \
  -c:a aac -b:a 32k -movflags +faststart "$OUTPUT_DIR/long-duration-simulated.mp4"

SPECIAL_NAME="spaces ' quote [中文] #1.mp4"
cp "$H264" "$OUTPUT_DIR/$SPECIAL_NAME"

# Keep the partial header, making this a genuinely truncated MP4 rather than random input.
dd if="$H264" of="$OUTPUT_DIR/truncated-input.mp4" bs=1 count=64 status=none

{
  printf '# MP4Flow synthetic media fixture manifest\n'
  printf '# Generated with: '
  "$FFMPEG_BIN" -version | /usr/bin/head -n 1
  printf 'h264-aac.mp4\tH.264 + AAC baseline\n'
  printf 'hevc-aac.mp4\tHEVC + AAC baseline\n'
  printf 'variable-frame-rate.mp4\tVariable presentation timestamps\n'
  printf 'portrait-9x16.mp4\tPortrait 9:16 video\n'
  printf 'no-audio.mp4\tVideo-only input\n'
  printf 'multiple-audio-tracks.mp4\tTwo language-tagged AAC tracks\n'
  printf 'subtitles.mp4\tTimed text subtitle track\n'
  printf 'rotation-90.mp4\t90 degree display matrix\n'
  printf 'odd-dimensions.mp4\t319x179 odd dimensions\n'
  printf 'hdr-signalled-hevc.mp4\tHEVC with BT.2020/PQ signalling\n'
  printf 'long-duration-simulated.mp4\t12-second low-resolution scheduling sample\n'
  printf '%s\tUnicode, space, quote, and shell metacharacter filename\n' "$SPECIAL_NAME"
  printf 'truncated-input.mp4\tIntentionally corrupt/truncated input\n'
} > "$OUTPUT_DIR/MANIFEST.tsv"

printf 'Created synthetic fixtures in %s\n' "$OUTPUT_DIR"
probe_video "$H264"
