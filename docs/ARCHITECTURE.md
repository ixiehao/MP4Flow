# Architecture

MP4Flow is a small native SwiftUI application without a server.

- `FastConvertApp.swift` contains the SwiftUI screens, editors, and interaction components.
- `ConverterStore.swift` owns the serial queue, process registration, progress, cancellation and atomic output publication. Pure planning and media parsing live outside its observable state.
- `ConversionModels.swift` defines immutable item identities and media facts. `ConversionItem.prepareForExport()` is the single reset transition for changed edits, options and retries, including stale output sizes and notices.
- `MediaInspector.swift` owns the bounded ffprobe request and typed decoding shared by editors, workers and verification, including audio languages, channel layouts and default-track flags.
- `ExportPlan.swift` validates one immutable export contract for the sheet, worker and retries. Audio encoders are chosen per output stream, retaining compatible AAC packets even when another track needs encoding.
- `FFmpegCommandBuilder.swift` builds commands without reading mutable UI state or starting processes. Numeric command values use POSIX formatting regardless of the selected interface language.
- `QueueResultHeader.swift` groups completion status, output size and optional details with fixed adjacent spacing on one baseline; extra column space follows the entire group and the success icon aligns with the header. The source column identifies the file; completed rows do not repeat an output filename. The existing folder action reveals the actual output in Finder. The optional detail button adapts its label to the available width while keeping one action, one popover presenter and its complete accessibility label. Rendered layout regressions check that widening the column does not push details away and that icon-only actions do not shift the status baseline. `QueueMediaFacts.swift` keeps the source dimensions, duration and size complete at narrow widths.
- `MergePlanning.swift` and `MergeAudioPlan.swift` validate track order, languages, channel layouts, displayed geometry and HDR policy before compatible encoding. Both merge paths retain all audio tracks; missing audio can be filled with silence without inventing audio for video-only batches. `ConcatManifest.swift` quotes filenames according to FFmpeg's token rules.
- `QueueJournal.swift` stores versioned local queue facts. Durable business mutations request a coalesced save; progress and general view updates do not construct snapshots. `PrivateAtomicFile.swift` creates private temporary inodes, synchronizes and renames them without truncating the previous generation. Stable IDs, edits and completed outputs survive relaunch; unfinished items wait for manual Start. QA bundle IDs use separate folders. Typed recovery/save notices are rendered in the main window and translated when read.
- `ExportOptions.swift` validates per-file target-size, audio and subtitle choices. `ExportSettingsView.swift` exposes them in a compact, seven-language sheet using the app's shared styles.
- `FFmpegProcessRunner.swift` owns each FFmpeg/ffprobe process, pipe drains, cancellation and progress-stall watchdog.
- `SmartEnhanceExporter.swift` owns the optional macOS 27 VideoToolbox enhancement pipeline and its reader/writer lifecycle.
- `DependencyHealth.swift` checks local tools, hardware encoding, and output locations. Tool results are reused during ordinary queue edits; manual refresh performs a fresh tool check.
- `AppLanguage.swift` resolves the selected language and exposes `L10n` for dynamic strings that SwiftUI cannot localize automatically.
- `AppResources/*.lproj/Localizable.strings` holds seven App languages, with English as the fallback. CI checks matching keys and format arguments across all catalogs; see [Localization](LOCALIZATION.md).
- `MenuBarLocalization.swift` refreshes native menu titles through public roles and actions, preserving targets, shortcuts and validation. Language selection lives in the menu bar.
- `AspectCorrection.swift` stores validated rational display ratios and bounded square-pixel output dimensions. `AspectPreview.swift` reshapes the existing player live, applying the same crop → rotation → final display-ratio order as export; no preview transcodes or per-keystroke probing are required.
- `CropGeometry.swift` normalizes crop coordinates and presets within even-pixel source bounds; zero is a valid origin.
- `ImageAdjustment.swift` owns bounded brightness/shadow settings, matching Core Image preview and FFmpeg export curves, and SDR color normalization. `PreviewCanvas.swift` provides a transparent AVPlayerLayer surface and the shared light editor canvas.
- `Scripts/build-app.sh` produces an app bundle; `Scripts/package-dmg.sh` creates an installer from an isolated temporary build.

The converter uses FFmpeg and ffprobe from the local computer. For supported H.264 and HEVC input without cropping, VideoToolbox keeps decode, scaling, rotation, and encoding in hardware memory. Rotation uses FFmpeg's `transpose_vt` filter when available and falls back to its software filter if a local FFmpeg build cannot run the hardware path. Queue work is serial by design: it avoids competing for CPU, disk I/O, and VideoToolbox resources during long batch operations.

Both pipes are drained through EOF while each child runs; waiting for `ffprobe` to exit before reading its JSON can deadlock on stream-rich media. Inspection, conversion and both merge modes share ownership and cancellation. Encoding watchdogs require advancing media time, frames or bytes; repeated progress packets and stderr noise do not hide a stall. The watchdog uses a monotonic clock and stops when its process exits.

Drains use POSIX pipe reads, retrying `EINTR`, so small writes reach the progress parser immediately. Foundation's `read(upToCount:)` can accumulate a requested buffer on macOS and delay progress until EOF; large-output/finished-file tests alone do not catch this. Editor inspection uses the same cancellable runner with a short deadline, and dismissal cancels its owned task.

Conversion and merge write to uniquely named partial MP4s, verify them, and publish only if the attempt has not been cancelled. Each conversion worker owns cleanup of its partial file with `defer`; moving it to the final destination leaves the published file untouched. Retryable probe failures are restricted to cloud and nonlocal sources. Encoding fallback requires a specific VideoToolbox component failure; media, muxing, I/O and timeout failures do not trigger automatic full-file replays. Each conversion/merge attempt has its own progress identity so delayed callbacks cannot update a later retry. Per-process progress buffers are released when their owning attempt ends.

Queue presentation loading has bounded concurrency. Clearing the queue cancels pending presentation operations; running loads check item membership before loading and before publishing their result. An already-started AVFoundation read may still finish. The native enhancement reader returns pixels in encoded orientation, so the writer preserves the source display transform and rebases its translation for the enlarged frame bounds.

Each presentation request has an identity. Successful conversion preflight replaces cached source dimensions, duration and byte size using the existing ffprobe result, so a repaired source does not keep stale failure-time facts after retry. This adds no extra probe or synchronous file read on the main actor. Earlier thumbnail requests cannot overwrite these facts; optional thumbnail-only refreshes resume after conversion and preserve the inspected metadata even when AVFoundation cannot read that format. Removing rows releases their request identities.

For ordinary transcoding, accurate input seeking avoids decoding a discarded prefix, and a validated numeric source time base preserves VFR timing. Resize planning uses displayed orientation and post-crop dimensions. Smart Convert can copy unchanged compatible video, including an audio-only AAC conversion when no pixel edit or trim is requested; explicit encoding presets retain their selected behavior.

When re-encoding a nonzero trim, a first-frame gap of at most one nominal frame
is filled by presenting that first selected frame at zero. All later video
timestamps and copied audio are preserved. This avoids an empty MP4 edit at
time zero that makes Finder's paused preview black. The bound uses the measured
average frame rate when available, since a VFR timestamp grid is not its playback
cadence. Longer leading gaps and stream-copy cuts retain their original timing.

Lossless merge compatibility includes the video time base, pixel aspect ratio and display rotation. Compatible merge normalizes pixel aspect ratio before proportional fitting and padding, and chooses its canvas from displayed geometry so orientation metadata cannot squash the content.

User notices describe actual affected media, not routine mapping policy. Ordinary single-track and video-only inputs have no per-row notice. Extra video/audio, subtitles and at-risk HDR handling remain visible after completion. Chapter bookmarks are optional navigation data: their omission is explained in a quiet per-row Conversion Details popover rather than an orange playback warning. Full default policy remains accessible from the queue and environment details. `QueueMediaFacts.swift` groups resolution, duration and file size into atomic fields, adapting to multiple lines instead of truncating numbers or units; filenames, option summaries and errors can wrap. All languages use the same layout. Cancellation and output verification have distinct UI states. Controlled native-enhancement errors are classified by type rather than their translated message.

## Update checks

The shared checker runs once 60 seconds after launch when enabled; manual checks
use the same path. It first sends a no-cache, cookie-free HEAD request to the
repository's official `releases/latest` URL. Redirects are not followed: only an
exact HTTPS tag page for this repository with a canonical stable version is
accepted. This avoids the shared unauthenticated REST API quota and downloads no
release HTML. If the link check fails, a bounded GET to the public REST endpoint
is used instead. Each request has a five-second timeout; there is no retry loop.

API 403/429 responses store a retry deadline from Retry-After / X-RateLimit-Reset
(with at least a minute of backoff), including across relaunches. Link checks
remain available during API cooldown. Offline or invalid responses are failures,
never proof that the app is up to date; an already-found update stays visible.
A dismissed version stays dismissed, while a later version can notify normally.
The checker neither downloads nor installs updates and uses no account token.

References: [official latest-release links](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
and [REST API rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).

## Per-file export and recovery

Audio and text-subtitle selection preserve compatible encoded video under Smart
Convert. All audio tracks are retained by default. Users can instead choose the
first track, a selected absolute stream index, or no audio. Text subtitles can be omitted, converted to an MP4 mov_text
track, or burned into the frame. Keeping subtitles may simplify styling; bitmap
subtitles are rejected with guidance. Burning requires a detected `subtitles`
filter in the user's FFmpeg (libass); missing support is explained before export.
No fonts or additional media runtime are bundled. Burn filters handle two-stage
FFmpeg escaping and restore source timestamps around subtitle rendering after
input seeking.

Target size uses the selected clip duration, a 3% container reserve and a separate
128 kb/s AAC budget for every retained audio track. H.264 size-budget exports use
offline x264 average-bitrate encoding; the quality levels select fast, medium,
and slow compression effort. They do not increase the fixed byte budget. The
real-time hardware encoder and tight VBV ceiling are unsuitable for this path:
a low-bitrate source can lose substantial detail even at the highest quality
selection. Explicit HEVC remains HEVC. Ordinary exports retain their existing
fast paths, including packet copy for compatible, unedited Smart Convert input.
The optional size limit starts disabled and suggests the rounded-up source size,
not an automatic percentage reduction or an arbitrary 100 MB cap. UI labels
explain that size takes priority and smaller targets can reduce quality.
Generous targets do not inflate the source bitrate; results are approximate,
particularly for simple scenes. Target
compression and subtitle burning require SDR and re-encoding. Native enhancement
supports a single audio track; preserving multiple tracks requires ordinary
conversion, or explicit selection of the first audio track for enhancement.
Edited/custom-export sources must be exported before merging.

Every retry preserves export choices. Verification checks the actual audio and
subtitle counts before the partial output is published. After any asynchronous
capability check, resolve a queue row by ID again: Clear Done can shift array
indices while conversion continues. Capability checks are cancellable processes.

Journal writes are coalesced after durable queue/configuration changes and flushed after completed
outputs or explicit edits, and on termination. Corrupt/future journals are
preserved as recovery files; failure to preserve the original blocks replacement.
Both the temporary and final records use user-only permissions in Application Support, with no
network upload. It contains local file paths; diagnostic sharing must not include
the journal. Recovery reloads thumbnails separately from persisted queue facts.

## Frame geometry and aspect correction

The crop/aspect editor probes the selected real video stream, its sample aspect
ratio and display rotation. Its coordinates match FFmpeg's automatically oriented
frame, while the crop guide fits the displayed pixel shape. Crop ratio presets
account for non-square pixels. Correction applies to the final cropped/rotated
frame and exports even square-pixel dimensions, preserving the complete selected
frame. Decimal custom inputs accept a dot or comma; numeric parsing rejects
expressions and invalid ratios outside 1:10–10:1. Extremely large output
dimensions are rejected before encoding. A correction forces encoding even
under Smart Convert or remux; native enhancement requires a separate ordinary
edit/conversion first. Edited pending sources cannot be merged before conversion.

Hardware decoding does not reliably bake input display matrices into frames.
For known orthogonal rotations, clear the input display rotation and apply it
explicitly with transpose_vt, then invert SAR for quarter turns before any user
rotation. CPU fallbacks retain FFmpeg's automatic orientation. Non-orthogonal
rotations avoid the hardware-filter pipeline. Missing display_rotation support
or transpose_vt falls back to CPU decoding/filtering without changing the edit.

Output verification compares displayed aspect against the inspected source and
edits (or the explicitly chosen correction), allowing bounded integer-pixel
rounding. Corrected outputs must also have square pixels. A decodable file with
the wrong geometry is rejected and its partial output removed. Regression
fixtures assert actual decoded circle shape and four-corner positions, not just
DAR metadata; quarter-turn input matrices are verified in fixtures before use.

## Image adjustments and preview surfaces

The frame editor groups crop, aspect correction and image adjustments in one
sheet. Custom ratio fields appear only for Custom; invalid ratios remain visible
as an actionable footer error when another tab is selected. All frame settings
are saved together, retaining trim and rotation. A neutral adjustment is a no-op;
changed settings requeue completed items without overwriting existing output.

Brightness and shadow lift share a bounded encoded-RGB curve with an offset.
Shadow lift uses `x + gain*x²*(1-x)²/(x+0.08)`, with gain in 0–1.2. Its slope
approaches one at black and white, avoiding the unbounded near-black gain of
the earlier gamma curve. FFmpeg builds a LUT once; Core Image uses a small
interpolated RGB curve table prepared once per video composition.
Preview and export explicitly select matching SDR color tags. Primaries and the
YCbCr matrix normalize to Rec.709; sRGB recordings retain their sRGB transfer
function, while ordinary video uses Rec.709. Encoder/container tags match that
selection. Core Image automatic color matching is disabled so filters operate on
the same encoded RGB values as the FFmpeg LUT across macOS versions. Regression
fixtures set and verify actual frame/container tags rather than relying on encoder
bitstream flags alone. A new video composition refreshes paused frames too (Apple QA1966), without
seeking, creating preview files or replacing the player item. Original comparison
bypasses color adjustments while retaining the current crop, rotation and ratio.

Optional light denoising is off by default and precedes tone adjustment. It
mixes 65% original with a 35% 3×3 Gaussian, baked into one convolution with
weights `[7,14,7;14,236,14;7,14,7]/320`. Native preview and FFmpeg share the
kernel and replicated-border semantics; no temporal history can leave motion
trails. The optional export stage uses 8-bit RGB to match the current 8-bit SDR
encoders, then applies the tone LUT at 16-bit precision. This avoids expensive
histogram medians and extra frame branches. Slight detail softening is disclosed
in the control's tooltip; denoise-only edits also encode and exclude direct merge.

Actual adjustments require encoding, exclude pending clips from direct merge,
and cannot be combined with native enhancement. CPU filters retain hardware
encoding when available; neutral settings retain the existing fast path. PQ/HLG
inputs are rejected with an SDR conversion instruction rather than silently
changing HDR color. Outputs are verified and published through the existing
cancellable partial-file owner; AAC audio can still be copied.

Every preview uses a transparent AVPlayerLayer over the same subtle gray-blue
canvas. Aspect-fit letterboxing shows the canvas; black pixels inside the source
remain video content. The stretched layer is limited to geometry correction.
No blur, duplicate player or screenshot cache is used for background decoration.

The frame editor measures the complete scaffold from its first presentation:
header, mode cards, fixed preview, playback, parameters and footer remain present
while inspection is loading or fails. Only preview content changes; controls are
disabled until dimensions are ready. This avoids a short initial sheet growing
from an incorrect native vertical origin and clipping its header. Color-preview
and HDR notices overlay the fixed canvas rather than adding a parameter row.
All ordinary editing modes share a 30-point minimum control-row height. Crop coordinates and dimensions sit inline with the aspect
presets, with labels inside compact numeric field surfaces. This avoids growing
and shrinking the sheet when moving between crop, ratio and image adjustment.
Numeric field widths still accommodate ordinary four/five-digit pixel values.
Custom ratio fields appear inline with the presets only
when Custom is selected; short width/height labels share the field surface,
while full accessible labels and decimal input remain available. Brightness,
shadows, denoise, comparison and reset share one row across all seven languages.
The comparison button keeps the same localized title in both states; its selected
appearance indicates original comparison without moving the sliders.
Invalid custom ratios disable Apply and remain visible as a
return-to-ratio action even after switching editing modes.

Playback controls subscribe when the actual player arrives, release the token on
that same player, and do not capture the loading state's zero duration in periodic
callbacks. End-of-item notifications are restricted to the editor's own item so
the play button resets even if the final tick precedes AVPlayer's paused status.
Crop fields reconcile to normalized bounds on commit/focus changes; only one
original/aspect preset is highlighted for a full-frame selection.
