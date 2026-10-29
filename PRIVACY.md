# Privacy

MP4Flow is designed to process media on the Mac where it is run. This document describes the behaviour of the open-source application as released in this repository; it does not describe macOS, a browser, Homebrew, or a separately installed FFmpeg build.

## Data MP4Flow handles

- The app reads the video files and folders that you add or choose. It may create an in-memory thumbnail and read media properties needed to show the queue and perform conversion.
- It stores the interface language, update preferences (including the version whose notice was dismissed), and GitHub API retry time in macOS user defaults. It does not persist a queue, video paths, conversion settings, diagnostics, account data, or a media library.
- Standard conversion, probing, trimming, cropping, aspect correction, rotation, and merging use the local `ffmpeg` and `ffprobe` executables. Experimental Smart Enhance uses Apple's AVFoundation and VideoToolbox frameworks on this Mac. This app release contains no telemetry, analytics, advertising SDK, or media-upload code.

## Update checks

- MP4Flow first sends a `HEAD` request to `https://github.com/ixiehao/MP4Flow/releases/latest` and reads the stable version from the official redirect, without downloading the release page. If that route is unavailable, it can read `https://api.github.com/repos/ixiehao/MP4Flow/releases/latest`. Both requests include only a fixed MP4Flow User-Agent and normal network metadata; they do not include cookies, video content, file paths, preferences, account credentials, or usage data. Redirects to other locations are not followed. API rate-limit responses are respected before another API attempt; the public release link can still be checked during that cooldown.
- Automatic checks are enabled by default and run once about 60 seconds after each launch, including the first launch. You can turn automatic checks off in **Settings** and still use **Help > Check for Updates** at any time.
- A found update only opens its public GitHub release page when you choose to view it. MP4Flow never downloads, installs, or executes an update automatically.

## Files created locally

- Outputs are written next to the source file by default, or in the folder you choose. Source files are never deleted or overwritten by MP4Flow.
- Work-in-progress outputs use a hidden, UUID-named `.partial.mp4` file beside the intended result and are moved into place only after processing and output verification succeed. The app tries to remove those files after an ordinary failure or cancellation. A crash, forced quit, power loss, or storage error can leave a partial file behind; it is safe to delete after confirming that no conversion is active.
- Lossless merge briefly creates a UUID-named manifest in the system temporary directory. It contains the selected source paths and is removed after the merge returns. A forced termination can leave that temporary manifest until macOS cleans its temporary directory.

## Metadata and local tools

MP4Flow asks FFmpeg not to copy container-level metadata or chapters to generated outputs. Codec-required stream information and data added by the separately installed FFmpeg build may still exist, so inspect an output before relying on it for sensitive redaction. Cropping, trimming, and conversion do not guarantee removal of visual, audio, subtitle, or other content that may identify a person or place.

MP4Flow looks for a user-supplied FFmpeg installation only in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, and `/usr/bin`. It does not download, bundle, verify, or update that executable. Install FFmpeg from a source you trust and review that build's own privacy, security, and licence information.

Selecting **Open Homebrew** opens `https://brew.sh/zh-cn/` in the default browser. That is an explicit browser action; its request and any data handled by the browser are outside MP4Flow's local-processing behaviour.

## Your choices

Keep private media in folders with appropriate macOS permissions. Before sharing an output, review its visible content, audio, subtitles, filenames, and metadata. If a future release adds data collection or a network feature beyond the public release check described above, this policy must be updated before that release.
