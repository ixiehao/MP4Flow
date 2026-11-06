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

The default command creates **two independent native installers**, Apple Silicon (`arm64`) and Intel (`x86_64`). Both use the same conversion rules. Each verified group is published into `dist/MP4Flow-<version>-<arch>/` and contains the DMG, SHA-256 file, stripped app, matching external dSYM and build provenance. The script signs ad hoc, remounts the final image, validates the actual CPU slice, macOS minimum, resources, signature and Finder layout. It never replaces an existing artifact group, including a dangling symbolic link.

For a test build, use a dedicated output directory to preserve existing installers:

```sh
OUTPUT_DIR="$PWD/dist/local-test" ./Scripts/package-dmg.sh
```

Build just one architecture with `--arch arm64` or `--arch x86_64`. Use `--preflight-only` to check both destination names before compiling. Relative output directories are relative to the caller. Choose a new output directory when retaining an earlier test build with the same version.

Architecture-specific SwiftPM caches are separate (`.build/native-arm64` and `.build/native-x86_64`). A packaging lock protects the shared tool environment. Owned staging directories are removed on failure; a mounted image that cannot be detached is preserved with its lock for diagnosis. Publication uses an exclusive atomic directory rename, so a concurrent file or directory cannot be overwritten.

For an app-only build, set `MP4FLOW_ARCH=arm64` (or `x86_64`) and `APP_OUTPUT_PATH` to a **new** `.app` inside the project or the temporary build directory, then run `./Scripts/build-app.sh`. This entry point also refuses to replace an existing app. Both build entry points obtain the executable/resource location from SwiftPM instead of assuming `.build/release`.

## Signing and distribution

The current distribution uses ad-hoc signing and is not notarized; no Developer ID certificate is required for this workflow. Verify the final mounted app with `codesign --verify --deep --strict --verbose=2`, verify the exact single architecture in each native build, and test launch, dependency detection and conversion from the packaged app. An ad-hoc signature verifies the bundle's integrity but does not establish an Apple-verified publisher identity. Gatekeeper may require the user to approve the downloaded app in macOS Privacy & Security; describe that limitation accurately without recommending that users disable Gatekeeper globally.

If Developer ID signing is adopted later, sign nested executable code first, sign the app, notarize the final distribution, staple the ticket, and verify Gatekeeper on a clean Mac. Generate the checksum only after the final artifact is complete. Do not label an ad-hoc build as notarized.

## Compatibility evidence

Cross-compiling Intel on Apple Silicon proves the binary can be built, not that it ran on physical Intel hardware. Rosetta execution, native hardware tests and old/new macOS acceptance are separate results. See [platform support and future macOS readiness](PLATFORMS.md). Preserve each matching dSYM outside disposable caches. `python3 -m unittest discover -s Scripts/tests -v` covers failure and concurrent-publication boundaries without touching installed apps.
