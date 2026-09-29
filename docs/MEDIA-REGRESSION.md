# Media regression and release gate

MP4Flow is a desktop app: its most important behaviours happen in the UI and in
real FFmpeg processes, not in a pure function. This document separates the fast,
deterministic CI signal from the release validation that must happen on real Macs.

## Automated synthetic suite

Run this before every release and on every pull request:

```sh
./Scripts/run-media-regression.sh
```

The script generates tiny, deterministic files in a uniquely-created temporary
directory, asserts stream metadata and decoding contracts with `ffprobe` and
FFmpeg, and removes the files afterwards. It tests H.264, HEVC, variable frame
rate, portrait video, video-only input, multiple audio tracks, subtitles,
rotation metadata, odd dimensions, HDR signalling, simulated long duration,
special file names, and truncated input. It does not download or commit media.

Passing this suite means the **test toolchain and fixture contracts** are sound.
It does not prove that a SwiftUI action, a hardware encoder, or a particular
customer video is supported.

## Required release matrix

For a release candidate, use media you have permission to test and record only
the results and tool versions—not the source media or its full path.

| Input or workflow | Expected result / decision that must be visible |
| --- | --- |
| H.264 + AAC | Smart Convert picks a fast compatible path; output opens in QuickTime. |
| HEVC + AAC | The selected hardware/software path is named; output remains playable. |
| Variable frame rate | Start/end times, trim result, and duration remain plausible; no audio drift. |
| Portrait or rotation metadata | The preview and exported display orientation match; no stretching. |
| Video-only | Conversion works and does not invent or require audio. |
| Multiple audio tracks | The selected policy is displayed before conversion; any dropped tracks are named. |
| Subtitle / timed text | The selected policy is displayed before conversion; retained subtitles remain selectable. |
| HDR source | The UI says whether HDR is retained, tone-mapped, or unsupported before start. |
| Odd dimensions / unusual pixel aspect ratio | Output has the expected displayed aspect ratio and is not stretched. |
| 30+ minute source | Progress advances, cancellation responds, and the app remains responsive. |
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
