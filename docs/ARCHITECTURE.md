# Architecture

MP4Flow is a small native SwiftUI application without a server.

- `FastConvertApp.swift` contains the SwiftUI screens, editors, and interaction components.
- `ConverterStore.swift` owns the serial queue, conversion strategy, progress parsing, media probing, output naming, and merge logic.
- `FFmpegProcessRunner.swift` owns each FFmpeg/ffprobe process, pipe drains, cancellation and progress-stall watchdog.
- `SmartEnhanceExporter.swift` owns the optional macOS 27 VideoToolbox enhancement pipeline and its reader/writer lifecycle.
- `DependencyHealth.swift` checks local tools, hardware encoding, and output locations. Tool results are reused during ordinary queue edits; manual refresh performs a fresh tool check.
- `AppLanguage.swift` resolves the selected language and exposes `L10n` for dynamic strings that SwiftUI cannot localize automatically.
- `AppResources/*.lproj/Localizable.strings` holds English, Japanese, and Simplified Chinese localizations. Chinese source strings are the Chinese fallback; English and Japanese include every user-facing key used dynamically, and CI verifies their coverage.
- `Scripts/build-app.sh` produces an app bundle; `Scripts/package-dmg.sh` creates an installer from an isolated temporary build.

The converter uses FFmpeg and ffprobe from the local computer. For supported H.264 and HEVC input without cropping, VideoToolbox keeps decode, scaling, rotation, and encoding in hardware memory. Rotation uses FFmpeg's `transpose_vt` filter when available and falls back to its software filter if a local FFmpeg build cannot run the hardware path. Queue work is serial by design: it avoids competing for CPU, disk I/O, and VideoToolbox resources during long batch operations.

Both pipes are drained through EOF while each child runs; waiting for `ffprobe` to exit before reading its JSON can deadlock on stream-rich media. Inspection, conversion and both merge modes share ownership and cancellation. Encoding watchdogs require advancing media time, frames or bytes; repeated progress packets and stderr noise do not hide a stall. The watchdog uses a monotonic clock and stops when its process exits.

Drains use POSIX pipe reads, retrying `EINTR`, so small writes reach the progress parser immediately. Foundation's `read(upToCount:)` can accumulate a requested buffer on macOS and delay progress until EOF; large-output/finished-file tests alone do not catch this. Editor inspection uses the same cancellable runner with a short deadline, and dismissal cancels its owned task.

Conversion and merge write to uniquely named partial MP4s, verify them, and publish only if the attempt has not been cancelled. Each conversion worker owns cleanup of its partial file with `defer`; moving it to the final destination leaves the published file untouched. Retryable probe failures are restricted to cloud and nonlocal sources. Encoding fallback requires a specific VideoToolbox component failure; media, muxing, I/O and timeout failures do not trigger automatic full-file replays. Each conversion/merge attempt has its own progress identity so delayed callbacks cannot update a later retry. Per-process progress buffers are released when their owning attempt ends.

Queue presentation loading has bounded concurrency. Clearing the queue cancels pending presentation operations; running loads check item membership before loading and before publishing their result. An already-started AVFoundation read may still finish. The native enhancement reader returns pixels in encoded orientation, so the writer preserves the source display transform and rebases its translation for the enlarged frame bounds.

For ordinary transcoding, accurate input seeking avoids decoding a discarded prefix, and a validated numeric source time base preserves VFR timing. Resize planning uses displayed orientation and post-crop dimensions. Smart Convert can copy unchanged compatible video, including an audio-only AAC conversion when no pixel edit or trim is requested; explicit encoding presets retain their selected behavior.

Lossless merge compatibility includes the video time base, pixel aspect ratio and display rotation. Compatible merge normalizes pixel aspect ratio before proportional fitting and padding, and chooses its canvas from displayed geometry so orientation metadata cannot squash the content.

User notices describe actual affected media, not routine mapping policy. Ordinary single-track and video-only inputs have no per-row notice. Extra video/audio, subtitles, chapters and at-risk HDR handling remain visible after completion; full default policy is accessible from the queue and environment details. Cancellation and output verification have distinct UI states. Controlled native-enhancement errors are classified by type rather than their translated message.
