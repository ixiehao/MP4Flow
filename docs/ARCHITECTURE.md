# Architecture

MP4Flow is a small native SwiftUI application without a server.

- `FastConvertApp.swift` contains the SwiftUI screens, editors, and interaction components.
- `ConverterStore.swift` owns the serial queue, conversion strategy, progress parsing, media probing, output naming, and merge logic.
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

For ordinary transcoding, accurate input seeking avoids decoding a discarded prefix, and a validated numeric source time base preserves VFR timing. Resize planning uses displayed orientation and post-crop dimensions. Smart Convert can copy unchanged compatible video, including an audio-only AAC conversion when no pixel edit or trim is requested; explicit encoding presets retain their selected behavior.

When re-encoding a nonzero trim, a first-frame gap of at most one nominal frame
is filled by presenting that first selected frame at zero. All later video
timestamps and copied audio are preserved. This avoids an empty MP4 edit at
time zero that makes Finder's paused preview black. The bound uses the measured
average frame rate when available, since a VFR timestamp grid is not its playback
cadence. Longer leading gaps and stream-copy cuts retain their original timing.

Lossless merge compatibility includes the video time base, pixel aspect ratio and display rotation. Compatible merge normalizes pixel aspect ratio before proportional fitting and padding, and chooses its canvas from displayed geometry so orientation metadata cannot squash the content.

User notices describe actual affected media, not routine mapping policy. Ordinary single-track and video-only inputs have no per-row notice. Extra video/audio, subtitles, chapters and at-risk HDR handling remain visible after completion; full default policy is accessible from the queue and environment details. Cancellation and output verification have distinct UI states. Controlled native-enhancement errors are classified by type rather than their translated message.

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
