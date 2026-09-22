# Architecture

MP4Flow is a small native SwiftUI application without a server.

- `FastConvertApp.swift` contains the SwiftUI screens, editors, and interaction components.
- `ConverterStore.swift` owns the serial queue, FFmpeg process lifecycle, progress parsing, media probing, output naming, and merge logic.
- `AppLanguage.swift` resolves the selected language and exposes `L10n` for dynamic strings that SwiftUI cannot localize automatically.
- `AppResources/*.lproj/Localizable.strings` holds English and Simplified Chinese localizations. Chinese source strings are the Chinese fallback; English must include every user-facing key used dynamically.
- `Scripts/build-app.sh` produces an app bundle; `Scripts/package-dmg.sh` creates an installer from an isolated temporary build.

The converter uses FFmpeg and ffprobe from the local computer. Queue work is serial by design: it avoids competing for CPU, disk I/O, and VideoToolbox resources during long batch operations.
