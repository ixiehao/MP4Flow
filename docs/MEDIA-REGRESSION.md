# Media regression and release gate

MP4Flow is a desktop app: its most important behaviours happen in the UI and in
real FFmpeg processes, not in a pure function. This document separates the fast,
deterministic CI signal from the release validation that must happen on real Macs.

## Automated synthetic suite

Run the application integration tests and media fixture checks before every release and on every pull request:

```sh
swift test
./Scripts/run-media-regression.sh
```

`swift test` exercises `ConverterStore` with generated videos: default 1080p-to-720p
conversion, unchanged-size smart stream copy, audio-only conversion, late accurate
trimming, VFR presentation timestamps, failed-source retry, and trim/crop/rotation
geometry. Non-square-pixel fixtures check displayed proportions through software
and hardware rotation. Merge tests reject incompatible clocks/orientations and
measure a displayed square inside the output, rather than checking only canvas
dimensions. Process tests exercise large stdout/stderr through EOF,
stalled progress, cancellation during inspection and a live merge, retry cleanup,
and a stream-rich `ffprobe` response larger than a pipe buffer. On macOS 27
machines with supported VideoToolbox hardware, it also exports and decodes a
short native Smart Enhance video with audio. That test skips on older or
unsupported Macs; the ordinary converter tests still run. CI installs FFmpeg
before invoking the Swift tests.

Fractional-trim regressions request a zero-tolerance frame at time zero through
AVFoundation, rather than assuming a valid stream or thumbnail proves Finder's
paused preview works. They cover software encoding, hardware crop/rotation,
HEVC, video-only input, copied AAC, VFR, and native Smart Enhance. Checks also
preserve later frame timestamps, compare decoded copied audio, and retain a
deliberately delayed video track.

Realtime tests additionally require small progress packets to arrive while the
producer is still running, verify that regularly advancing packets prevent false
inactivity timeouts, and observe positive 1080p-to-720p queue progress before
publication. Editor-preview tests cover malformed responses and cancellation of
a silent process that ignores TERM. Notice tests distinguish ordinary media from
actual track/subtitle/chapter/HDR consequences; tool tests reject mixed FFmpeg
and ffprobe installations.

Video-stream tests distinguish embedded cover art and timed thumbnails from
movie tracks, including a cover-first probe response and genuine MJPEG video.
Real files with embedded JPEG covers exercise stream copy, software/hardware
rotation, lossless merge, compatible merge, and native Smart Enhance. Assertions
check copied movie bytes, frame count, changing decoded frames and duration.
Cover-only input and output must fail without publishing a final file. Native
exports use the inspected container track ID and reject an ambiguous fallback;
lossless concatenation also requires matching stream layouts.

### Optional local performance check

The queue benchmark is skipped by default. To measure a full authorized local
video through the actual application queue, run:

```sh
MP4FLOW_BENCHMARK_INPUT="/path/to/authorized/video.mp4" \
  swift test --filter ConverterStoreTests.testAuthorizedMedia720pBenchmark
```

It selects Smart Convert and 720p, writes into a unique temporary directory,
checks duration/frame count and full decoding, then removes the output. The
reported elapsed time ends after the app's normal output verification; the
additional test decode is excluded. The source path is not printed or stored in
the repository. Keep private media and probe metadata out of public reports.
Record the chip, FFmpeg version, input facts and chosen route with performance
results; this is a measured diagnostic, not a CI speed threshold.

The script generates tiny, deterministic files in a uniquely-created temporary
directory, asserts stream metadata and decoding contracts with `ffprobe` and
FFmpeg, and removes the files afterwards. It tests H.264, HEVC, variable frame
rate, portrait video, video-only input, multiple audio tracks, subtitles,
rotation metadata, odd dimensions, HDR signalling, simulated long duration,
special file names, and truncated input. It does not download or commit media.

Passing these checks confirms the exercised conversion paths and fixture
contracts. It does not prove that every SwiftUI action, hardware encoder, or
particular customer video is supported.

## Required release matrix

For a release candidate, use media you have permission to test and record only
the results and tool versions—not the source media or its full path.

| Input or workflow | Expected result / decision that must be visible |
| --- | --- |
| H.264 + AAC | Smart Convert picks a fast compatible path; output opens in QuickTime. |
| HEVC + AAC | The selected hardware/software path is named; output remains playable. |
| Variable frame rate | Start/end times, trim result, and duration remain plausible; no audio drift. |
| Trim between frames, then crop or rotate | Finder shows a paused first frame; later video timing and audio remain aligned. |
| Portrait or rotation metadata | The preview and exported display orientation match; no stretching. |
| Video-only | Conversion works and does not invent or require audio. |
| Movie with embedded cover / thumbnails | Covers are excluded from movie count and selection; the exported movie has the expected frames and duration. |
| Audio with cover only | No usable movie is reported; no video output is published. |
| Multiple audio tracks | The selected policy is displayed before conversion; any dropped tracks are named. |
| Subtitle / timed text | The selected policy is displayed before conversion; retained subtitles remain selectable. |
| HDR source | The UI says whether HDR is retained, tone-mapped, or unsupported before start. |
| Odd dimensions / unusual pixel aspect ratio | Output has the expected displayed aspect ratio and is not stretched. |
| 30+ minute source | Progress advances, cancellation responds, and the app remains responsive. |
| A normal job lasting longer than the inactivity window | Live small progress packets prevent a false timeout; first progress appears before completion. |
| File name with spaces, quotes, Unicode, and brackets | Source is untouched; output succeeds without shell-path errors. |
| Truncated / damaged source | Conversion fails quickly with a reason and recovery guidance; no fake success. |
| Network/removable volume | A disconnect or write failure is recoverable; no partial file is presented as final. |
| Full or unwritable output disk | The app reports the failure and removes its temporary output. |

Run the matrix on the minimum supported macOS version, the current macOS
version, Apple silicon, and Intel hardware when that architecture is shipped.
Exercise each quality choice and the software fallback at least once. Record:

- MP4Flow version and git revision
- macOS, model/architecture, and available disk space
- FFmpeg/ffprobe version and install origin
- source codec/container facts, not personal file paths or media
- conversion route selected, elapsed time, output verification result, and any
  cancellation/retry result

## Release quality thresholds

Do not call a build stable until all supported matrix cases pass, every failed
case has a user-facing reason and safe recovery action, and the following have
been checked:

- No crash, unbounded wait, or UI freeze during a successful job, cancellation,
  or ordinary input/output failure.
- A progress stall has an observable process/status explanation and a bounded
  recovery path; a completed process is always followed by output validation.
- Watch an actual installed candidate during a full customer-authorized job:
  record the first positive progress time and intermediate percentages, not
  just the final duration. Verification/cancellation must not be labelled as
  continued transcoding, and 100% must not imply unchecked output is published.
- Ordinary single-video/single-audio and video-only inputs do not show routine
  orange warnings. The policy remains accessible, real losses remain visible,
  and failure recovery text is readable in all supported languages.
- Source files remain unchanged. Failed jobs leave no user-visible final output
  and no retained `.partial.mp4` file.
- Track and HDR handling is explicit. The app must never silently promise that
  subtitles, secondary audio, chapters, metadata, or HDR were retained.
- Diagnostics redact paths, file names, metadata, and media content by default.
  A user must opt in before sharing a report.

## Gaps that require manual coverage

Synthetic fixtures cannot represent every camera, screen recorder, codec build,
or hardware driver. Before a broad release, add authorised representative
samples for ProRes, AV1/VP9 where advertised, phone HDR, interlaced content,
chapters, non-square pixels, and subtitle formats outside MP4 timed text. Keep
those samples outside the public repository unless redistribution rights are
clear; store only checksums and non-sensitive technical probe summaries in a
private release record.
