# Architecture

MP4Flow is a small native SwiftUI application without a server.

- `FastConvertApp.swift` contains the SwiftUI screens, editors, and interaction components.
- `ConverterStore.swift` owns the serial queue, FFmpeg process lifecycle, progress parsing, media probing, output naming, and merge logic.
- `SmartEnhanceExporter.swift` owns the optional macOS 27 VideoToolbox enhancement pipeline and its reader/writer lifecycle.
- `DependencyHealth.swift` checks local tools, hardware encoding, and output locations. Tool results are reused during ordinary queue edits; manual refresh performs a fresh tool check.
- `AppLanguage.swift` resolves the selected language and exposes `L10n` for dynamic strings that SwiftUI cannot localize automatically.
- `AppResources/*.lproj/Localizable.strings` holds English, Japanese, and Simplified Chinese localizations. Chinese source strings are the Chinese fallback; English and Japanese include every user-facing key used dynamically, and CI verifies their coverage.
- `Scripts/build-app.sh` produces an app bundle; `Scripts/package-dmg.sh` creates an installer from an isolated temporary build.

The converter uses FFmpeg and ffprobe from the local computer. For supported H.264 and HEVC input without cropping, VideoToolbox keeps decode, scaling, rotation, and encoding in hardware memory. Rotation uses FFmpeg's `transpose_vt` filter when available and falls back to its software filter if a local FFmpeg build cannot run the hardware path. Queue work is serial by design: it avoids competing for CPU, disk I/O, and VideoToolbox resources during long batch operations.

Process output is drained while each child runs; waiting for `ffprobe` to exit before reading its JSON can deadlock on stream-rich media. A conversion writes to a uniquely named partial MP4, verifies it, and publishes the final path only if the attempt has not been cancelled. Retryable probe failures are restricted to cloud and nonlocal sources; disk and permission failures do not trigger encoding fallbacks. Each FFmpeg attempt has its own progress identity so delayed callbacks cannot update a later retry.
