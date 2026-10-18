# Building the DMG installer

`Scripts/package-dmg.sh` builds a self-contained drag-to-install DMG. Its Finder window uses the MP4Flow app icon on the left and an Applications shortcut on the right, with the same 960 × 600 installation layout used by ShotTessera. MP4Flow's background artwork and text are original to this project.

## Prerequisites

- Xcode Command Line Tools
- Python 3.10 or newer with `venv`; set `PACKAGING_PYTHON` to select an executable
- Network access on the first run to install the pinned `dmgbuild` dependency
- FFmpeg is not required to build the app or DMG

## Create a local installer

```sh
./Scripts/package-dmg.sh
```

The artifact is written to `dist/MP4Flow-<version>.dmg` with a SHA-256 file beside it. The script builds a universal binary on Apple Silicon and an architecture-native binary on Intel, signs the app ad-hoc, validates the signature, and runs `hdiutil verify`.

For a test build, use a dedicated output directory to preserve existing installers:

```sh
OUTPUT_DIR="$PWD/dist/local-test" ./Scripts/package-dmg.sh
```

The app is staged in a unique temporary directory, so this command does not replace a developer's existing `MP4Flow.app`. Choose a new output directory when retaining an earlier test build with the same version.

## Signing and distribution

The current distribution uses ad-hoc signing and is not notarized; no Developer ID certificate is required for this workflow. Verify the final mounted app with `codesign --verify --deep --strict --verbose=2`, check both architectures when shipping a universal build, and test launch, dependency detection and conversion from the packaged app. An ad-hoc signature verifies the bundle's integrity but does not establish an Apple-verified publisher identity. Gatekeeper may require the user to approve the downloaded app in macOS Privacy & Security; describe that limitation accurately without recommending that users disable Gatekeeper globally.

If Developer ID signing is adopted later, sign nested executable code first, sign the app, notarize the final distribution, staple the ticket, and verify Gatekeeper on a clean Mac. Generate the checksum only after the final artifact is complete. Do not label an ad-hoc build as notarized.
