# Developing MP4Flow

[Documentation index](README.md) · [Architecture](ARCHITECTURE.md)

## Repository layout and environment

- `Package.swift`, `Sources/`, `Tests/` — Swift package, application implementation and tests.
- `AppResources/` — app metadata, localization, icon and asset notices. The app uses system fonts and does not bundle font files.
- `Scripts/` — validation, application packaging and media regression.
- `website/` — public website source; `docs/` — maintainer guides.

Use macOS and a Swift toolchain compatible with `Package.swift`. Media regression requires local FFmpeg and ffprobe, as described in [MEDIA-REGRESSION.md](MEDIA-REGRESSION.md). Do not bundle an additional media runtime without reviewing distribution rights and product requirements.

Localization validation requires Python 3.9+ and macOS `plutil` on `PATH`. The validator checks all seven App catalogs, rejects duplicate or empty keys, verifies identical key sets and printf argument types/positions, and checks the language enum against bundle metadata. See [localization](LOCALIZATION.md) for translation and UI verification guidance.

## Build and test

From the repository root, matching the CI checks:

```sh
swift build -c release -Xswiftc -strict-concurrency=complete
./Scripts/validate-localizations.sh
python3 -m unittest discover -s Scripts/tests -v
swift test
./Scripts/run-media-regression.sh
```

Run media regression after its documented dependencies are available. To create the local app bundle:

```sh
./Scripts/build-app.sh
```

The script creates a new native `.app` and refuses to replace existing output; select `MP4FLOW_ARCH=arm64` or `x86_64` and a new `APP_OUTPUT_PATH` when needed. It is not a test or a notarized release. See [native packaging](INSTALLER-BUILD.md).

## Local build cache

After confirming that no Swift or Xcode build or test is using this checkout, run `swift package clean` from the repository root to remove regenerable build products in `.build/`. The next build recompiles the package. Preserve installers and release records in `dist/` and all user media; these are retained outputs rather than cache. Limit cleanup to this checkout, leaving global caches and other projects untouched.

## Behavioral checks

Inspect all supported languages, narrow windows, invalid input, output-folder failures, cancellation and retry. Continuously drain child-process output to avoid pipe deadlocks; test probe output and conversion completion rather than only command construction. Keep progress associated with the current attempt.

For recovery/export work, `ExportRecoveryTests` verifies versioned journals,
preserved records, write failures, isolated storage and clearing completed items
with 1–4 survivors. `ExportMediaTests` checks actual selected/all/muted audio,
subtitle tracks, preserved encoded packets, size budgets and complete decoding.
`StateStorageAuditTests` checks current-row identity, complete result reset,
private atomic replacement and damaged records. `MergeAudioRegressionTests`
checks all audio tracks in both merge modes, quoted filenames, video-only and
silent clips, default-track flags, deliberate sound delays, conflicting track
orders and actual HDR tags. Assert the fixtures' media metadata before checking
rejection behavior; encoder options alone do not prove a fixture is HDR.
`TargetCompressionQualityTests` compares decoded SSIM against the previous
speed-first encoder at a small file-size budget, checks that quality controls
change compression effort, and verifies unchanged packet-copy behavior without
the optional limit. A playable file and correct byte count are not visual
quality acceptance criteria. Inspect aligned source/output frames as well.
To repeat the full-source low-bitrate regression with locally authorized media,
set `MP4FLOW_QUALITY_INPUT`; optional `MP4FLOW_QUALITY_ARTIFACTS` retains output in
a dedicated local test directory. The eight-megabyte/SSIM assertions target the
reported 140-second, 720p low-bitrate case; do not apply them to arbitrary media.
Private sources and their paths must not be committed or uploaded.
The positive subtitle-burn and delayed-preflight tests require a libass-enabled
FFmpeg; the normal installed FFmpeg still exercises the explicit missing-support
path. Set `MP4FLOW_TEST_FFMPEG` to a trusted test build with a sibling ffprobe:

```sh
MP4FLOW_TEST_FFMPEG=/absolute/path/to/ffmpeg swift test --filter ExportMediaTests
```

For end-user subtitle burning, Homebrew's optional
[`ffmpeg-full`](https://formulae.brew.sh/formula/ffmpeg-full) includes libass:
`brew install ffmpeg-full`. It has additional dependencies and is not required
for ordinary conversion or subtitle-track preservation. The shared tool resolver
detects its Apple-silicon/Intel keg-only paths without force-linking; health
checks and conversion always use the same installation and sibling ffprobe.
Reopen Export Settings after installation to recheck actual filter support.

Use an isolated `.app` identity, UserDefaults and Application Support folder for
native QA. Finish the build before modifying QA metadata and re-signing ad hoc;
do not rebuild over a running app. A new path/identity avoids stale LaunchServices
registration after replacing a bundle. Use synthetic media in a temporary
directory to separate application bugs from fresh-bundle Documents permissions.
Verify all seven form layouts, invalid inputs, enabled/disabled choices, selected
track persistence, actual output tracks and relaunch without automatic conversion.

For website-only or documentation-only edits, use [website checks](WEBSITE.md) and link review. Application packaging is unnecessary unless application resources or behavior change.

## Release

Use [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) and [INSTALLER-BUILD.md](INSTALLER-BUILD.md). Keep version, architecture, signing state and download messaging consistent; publication requires separate approval.

## Native architecture and SDK checks

CI runs the same complete suite on explicit Apple Silicon (`macos-15`) and Intel (`macos-26-intel`) runners. The `build` aggregate check requires both; a failed or cancelled matrix cannot pass it. Changing the CI host does not raise the macOS 13 deployment target. Local tests under Rosetta must be labelled as translated execution. Use [PLATFORMS.md](PLATFORMS.md) for the readiness checklist and limits of future-system claims.
