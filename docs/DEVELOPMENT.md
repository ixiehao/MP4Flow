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
swift build -c release
./Scripts/validate-localizations.sh
python3 -m unittest discover -s Scripts/tests -v
swift test
./Scripts/run-media-regression.sh
```

Run media regression after its documented dependencies are available. To create the local app bundle:

```sh
./Scripts/build-app.sh
```

The script rebuilds its configured `.app` output; it is not a test or a notarized release. Check existing output before running it.

## Local build cache

After confirming that no Swift or Xcode build or test is using this checkout, run `swift package clean` from the repository root to remove regenerable build products in `.build/`. The next build recompiles the package. Preserve installers and release records in `dist/` and all user media; these are retained outputs rather than cache. Limit cleanup to this checkout, leaving global caches and other projects untouched.

## Behavioral checks

Inspect all supported languages, narrow windows, invalid input, output-folder failures, cancellation and retry. Continuously drain child-process output to avoid pipe deadlocks; test probe output and conversion completion rather than only command construction. Keep progress associated with the current attempt.

For website-only or documentation-only edits, use [website checks](WEBSITE.md) and link review. Application packaging is unnecessary unless application resources or behavior change.

## Release

Use [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) and [INSTALLER-BUILD.md](INSTALLER-BUILD.md). Keep version, architecture, signing state and download messaging consistent; publication requires separate approval.
