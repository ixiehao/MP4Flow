# Building the DMG installer

`Scripts/package-dmg.sh` builds a self-contained drag-to-install DMG. Its Finder window uses the MP4Flow app icon on the left and an Applications shortcut on the right, with the same 960 × 600 installation layout used by ShotTessera. MP4Flow's background artwork and text are original to this project.

## Prerequisites

- Xcode Command Line Tools
- Python 3 with `venv`
- Network access on the first run to install the pinned `dmgbuild` dependency
- FFmpeg is not required to build the app or DMG

## Create a local installer

```sh
./Scripts/package-dmg.sh
```

The artifact is written to `dist/MP4Flow-<version>.dmg` with a SHA-256 file beside it. The script builds a universal binary on Apple Silicon and an architecture-native binary on Intel, signs the app ad-hoc, validates the signature, and runs `hdiutil verify`.

## Publish safely

The generated DMG is suitable for internal testing, not public distribution. Before publishing, replace the ad-hoc signing step with your Apple Developer ID Application certificate, sign every nested executable, submit the DMG for notarization, staple the ticket, and verify it on a clean Mac. Do not ship a DMG that has not passed Gatekeeper testing.
