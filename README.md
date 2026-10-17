# MP4Flow

> **A free, open-source macOS app that turns video into MP4 — seriously simple.**

[![Latest release](https://img.shields.io/github/v/release/ixiehao/MP4Flow?display_name=tag&sort=semver&label=release)](https://github.com/ixiehao/MP4Flow/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](https://github.com/ixiehao/MP4Flow/releases/latest)
[![License](https://img.shields.io/github/license/ixiehao/MP4Flow)](LICENSE)

[Download free](https://github.com/ixiehao/MP4Flow/releases/latest) · [Website](https://ixiehao.github.io/MP4Flow/) · [中文](README.zh-CN.md) · [日本語](README.ja.md) · [Get help](SUPPORT.md)

Free, open source, and local. **No account, no upload, no codec jargon.** Add a video, choose a quality, and convert it on your Mac.

![MP4Flow feature demo](docs/assets/mp4flow-demo.gif)

## Start in 3 steps

1. Download the `.dmg` from the [latest release](https://github.com/ixiehao/MP4Flow/releases/latest), open it, and drag **MP4Flow** to **Applications**.
2. Install the one local dependency. It includes both `ffmpeg` and `ffprobe`:

   ```sh
   brew install ffmpeg
   ```

3. Open MP4Flow, add videos, keep **Smart Convert (Recommended)** selected, then click **Start Conversion**.

That is all most people need. Open **Environment Check** in the app if you want to confirm FFmpeg or hardware encoding is ready.

> macOS 13 Ventura or later is required. Apple Silicon and Intel Macs are supported. If macOS blocks the first launch, Control-click MP4Flow and choose **Open**. See the short [download and checksum guide](docs/DOWNLOAD.md) if needed.

## What you can do

| Feature | What it means |
| --- | --- |
| **Smart Convert** | The recommended default. MP4Flow chooses the practical route for the file. |
| **Fast local processing** | Uses direct MP4 remuxing or stream-copy trimming when possible, avoiding unnecessary re-encoding. |
| **Trim, crop, rotate** | Keep just the clip you need, adjust the frame, or fix orientation before exporting. |
| **Merge videos** | Use lossless merge for matching files, or compatible merge for different files without stretching the image. |
| **Choose a size** | Keep the original resolution or select 1080p, 720p, 576p, or 480p while preserving the aspect ratio. |
| **Private by default** | Video processing stays on your Mac. MP4Flow has no account, analytics, or video-upload service. |

### Want a different result?

- Need the widest playback compatibility? Choose **H.264**.
- Want a smaller file on newer devices? Choose **HEVC**.
- Need maximum compatibility after a difficult conversion? Choose the **software** option.
- Need to enlarge a supported video? Try **Smart Enhance Upscale**. It is experimental and available only on Apple Silicon with macOS 27 or later when VideoToolbox supports that exact scale. It does not support crop or rotation at the same time, and macOS may download a system model on first use.

## Good to know

- **One output per input:** existing files are never overwritten; you can reveal completed files in Finder.
- **Clear progress:** MP4Flow shows inspection, direct remuxing, hardware or software conversion, and final verification. Failed items can be retried.
- **Tracks and metadata:** before converting, the app reports multi-audio, subtitles, and HDR. The default export keeps the first video and audio track and does not copy container metadata or chapters. Check the result before sharing sensitive material.
- **No magic enlargement:** normal upscaling changes dimensions, not missing detail. Smart Enhance is the optional system-assisted exception described above.

## Common questions

### “FFmpeg” or “ffprobe” is missing

Run `brew install ffmpeg`, then select **Environment Check** → **Check Again**. MP4Flow does not bundle or download FFmpeg for you.

### A file failed once

Try **Retry** first. If it still fails, use **Smart Convert** to create a new MP4, add that new file, and try the edit or enhancement again. The status message explains the failed stage when possible.

### How do I merge clips?

Add at least two untouched waiting items and choose **Merge**. Use **Compatible Merge** when their codecs, frame rates, or sizes differ.

## Build from source

```sh
git clone https://github.com/ixiehao/MP4Flow.git
cd MP4Flow
./Scripts/build-app.sh
open MP4Flow.app
```

For contributors, run `swift test` and `./Scripts/run-media-regression.sh` (with FFmpeg installed) before submitting a change. More details: [contributing](CONTRIBUTING.md), [media regression](docs/MEDIA-REGRESSION.md), [installer build](docs/INSTALLER-BUILD.md), and [release checklist](docs/RELEASE-CHECKLIST.md).

## Privacy, dependencies, and license

- MP4Flow uses Swift, SwiftUI, and Apple system frameworks. [Privacy policy](PRIVACY.md) · [Security policy](SECURITY.md)
- FFmpeg is a separately installed local runtime dependency; its licence depends on the build you install. MP4Flow neither bundles nor downloads it.
- Smart Enhance uses Apple’s on-device VideoToolbox capability when macOS makes it available. Its supported factors and system model delivery are controlled by macOS.
- The app includes Noto Sans SC under the [SIL Open Font License 1.1](AppResources/OFL.txt), plus a curated local subset of [Tabler Icons Outline](https://github.com/tabler/tabler-icons) (v3.49.0) under the [MIT License](AppResources/ASSET_NOTICES.md).

See [NOTICE.md](NOTICE.md) for attribution and [LICENSE](LICENSE) for the project licence.

## Development documentation

[Documentation index](docs/README.md) · [Development and validation](docs/DEVELOPMENT.md) · [Website maintenance](docs/WEBSITE.md).

The official website source lives in `website/`; `docs/` is reserved for maintainer documentation.
