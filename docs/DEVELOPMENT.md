# Developing MP4Flow

[Documentation index](README.md) · [Architecture](ARCHITECTURE.md)

## Repository layout and environment

- `Package.swift`, `Sources/`, `Tests/` — Swift package, application implementation and tests.
- `AppResources/` — app metadata, localization, icon, fonts and asset notices.
- `Scripts/` — validation, application packaging and media regression.
- `website/` — public website source; `docs/` — maintainer guides.

Use macOS and a Swift toolchain compatible with `Package.swift`. Media regression requires local FFmpeg and ffprobe, as described in [MEDIA-REGRESSION.md](MEDIA-REGRESSION.md). Do not bundle an additional media runtime without reviewing distribution rights and product requirements.

## Build and test

From the repository root, matching the CI checks:

```sh
swift build -c release
./Scripts/validate-localizations.sh
swift test
./Scripts/run-media-regression.sh
```

Run media regression after its documented dependencies are available. To create the local app bundle:

```sh
./Scripts/build-app.sh
```

The script rebuilds its configured `.app` output; it is not a test or a notarized release. Check existing output before running it.

## Behavioral checks

Inspect all supported languages, narrow windows, invalid input, output-folder failures, cancellation and retry. Continuously drain child-process output to avoid pipe deadlocks; test probe output and conversion completion rather than only command construction. Keep progress associated with the current attempt.

For website-only or documentation-only edits, use [website checks](WEBSITE.md) and link review. Application packaging is unnecessary unless application resources or behavior change.

## Release

Use [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) and [INSTALLER-BUILD.md](INSTALLER-BUILD.md). Keep version, architecture, signing state and download messaging consistent; publication requires separate approval.
