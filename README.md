# MP4Flow

**A local, native macOS video-to-MP4 converter.**

MP4Flow converts common video files to playable MP4 on your Mac. It replaces codec jargon with clear choices: keep the original, save space, use a compatible format, trim, crop, rotate, or merge clips. Nothing is uploaded.

Beyond MP4 conversion, use MP4Flow to trim clips, crop the frame, and rotate video. We are building a fast, lightweight, free, and open-source video conversion tool that feels at home on macOS.

![MP4Flow feature demo](docs/assets/mp4flow-demo.gif)

*Add a video, make quick edits, and convert it locally.*

[中文说明](README.zh-CN.md) · [Installer guide](docs/INSTALLER-BUILD.md) · [Release checklist](docs/RELEASE-CHECKLIST.md) · [Privacy](PRIVACY.md) · [Security](SECURITY.md)

## Highlights

- **English and Simplified Chinese UI** — follows the system language on first launch and can be changed in the app.
- **Fast when possible** — direct MP4 remuxing and stream-copy trimming avoid re-encoding; supported H.264/HEVC scaling uses Apple VideoToolbox.
- **Clear choices** — Smart Convert, Clear and Compact, Preserve Original Quality, device-compatible H.264, smaller HEVC, and a software fallback.
- **Resolution control** — keep original dimensions or convert to 1080p, 720p, 576p, or 480p while preserving aspect ratio. Upscaling enlarges the canvas, not missing detail.
- **Experimental Smart Enhance Upscale** — on Apple Silicon running macOS 27 or later, use VideoToolbox super resolution for the exact scale factors reported by the system. It is intentionally opt-in, supports no crop or rotation yet, and may require a one-time system model download.
- **Simple editing** — trim a time range, crop with draggable handles and numeric fields, and rotate 90° or 180°.
- **Two merge modes** — lossless merging for matching streams; compatible merging normalises clips to the largest source resolution without stretching.
- **Reliable batches** — progress, retry failed items, cancellation, safe temporary outputs, and no overwrite of existing files.
- **Privacy by design** — processing stays on your Mac. Outputs are configured not to copy container metadata or chapters; review exports when sensitive redaction matters.

## Requirements

- macOS 13 Ventura or later
- [FFmpeg](https://ffmpeg.org/) and `ffprobe` installed together in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, or `/usr/bin`
- Apple Silicon or Intel Mac; hardware acceleration depends on the Mac and source codec
- **Smart Enhance Upscale (experimental):** Apple Silicon, macOS 27 or later, and a source/target pair that matches a VideoToolbox-supported scale factor. The system may download its model before the first use. It is not bundled with MP4Flow and does not send your video to MP4Flow or a third-party service.

Install FFmpeg with Homebrew:

```sh
brew install ffmpeg
```

## Use

1. Open MP4Flow and add video files or drag them into the queue.
2. Choose a conversion mode, quality/size, resolution, and output location.
3. Optionally use Trim, Crop, or Rotate on a waiting item.
4. Select **Start Conversion**. Completed files can be revealed in Finder.

To merge, add at least two untouched waiting files and select **Merge**. Choose **Compatible Merge** when their stream parameters differ.

## Build from source

```sh
git clone https://github.com/ixiehao/MP4Flow.git
cd MP4Flow
./Scripts/build-app.sh
open MP4Flow.app
```

The generated app is ad-hoc signed for local development. See [docs/INSTALLER-BUILD.md](docs/INSTALLER-BUILD.md) to create a distributable DMG.

## Dependencies and licensing

- MP4Flow uses Swift, SwiftUI, and Apple system frameworks.
- FFmpeg is an external runtime dependency and is not bundled, downloaded, or licensed by the app. Its licence depends on the build you install.
- Smart Enhance Upscale uses Apple's on-device VideoToolbox framework when it is supported by the current Mac and macOS. Its availability, supported factors, and model delivery are controlled by the operating system.
- The bundled Noto Sans SC font is licensed under the [SIL Open Font License 1.1](AppResources/OFL.txt).

See [NOTICE.md](NOTICE.md) for attribution, [PRIVACY.md](PRIVACY.md) for data handling, and [LICENSE](LICENSE) for the project license.
