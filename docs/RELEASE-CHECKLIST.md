# Release checklist

Use this checklist for each public MP4Flow release. It is a release gate, not a claim that an unchecked item has been completed.

## Repository and disclosure

- [x] Create the canonical GitHub repository and replace the clone URL in all three README files.
- [ ] Enable GitHub Private Vulnerability Reporting and replace the reporting instruction in [SECURITY.md](../SECURITY.md) with the repository's private reporting link.
- [ ] Confirm the repository description, topics, licence, default branch protection, and release notes follow [GITHUB_METADATA.md](GITHUB_METADATA.md).
- [ ] Confirm the repository homepage, trilingual README download links, issue chooser, and social preview still point to the current official project surfaces.
- [ ] Confirm the latest Release has a human-readable title, concise English, Simplified Chinese, Japanese and Korean user-facing notes, a DMG with its actual signing/notarization status disclosed, and a matching SHA-256 file.
- [ ] Check that `.gitignore` is effective and that the branch contains no signing certificates, provisioning profiles, private keys, `.env` files, test media, DMGs, or build products.
- [ ] Review issues, pull requests, screenshots, and logs for private file paths, personal data, or unlicensed media.

## Privacy and security

- [ ] Re-read [PRIVACY.md](../PRIVACY.md) against the release code. Update it before adding telemetry, updates, account features, a network client, persistence, or bundled tools.
- [ ] Verify all FFmpeg and ffprobe invocations use argument arrays, `-nostdin`, and the documented executable locations. Do not add shell interpolation for file paths.
- [ ] Test conversion, cancellation, lossless merge, compatible merge, and a denied output folder. Confirm source files remain unchanged and ordinary failures remove `.partial.mp4` files.
- [ ] Test files with spaces, quotes, Unicode, long names, and line breaks. Lossless Merge must reject line-break filenames; normal conversion must not use a shell.
- [ ] Run `./Scripts/run-media-regression.sh`; retain the command output with the private release record, not the generated media.
- [ ] Complete the real-device matrix in [MEDIA-REGRESSION.md](MEDIA-REGRESSION.md), including VFR, portrait/rotation metadata, audio/subtitle policies, HDR behaviour, long inputs, damaged inputs, unusual dimensions, and output-storage failures.
- [ ] Confirm the app names the planned conversion route and does not imply that secondary audio, subtitles, metadata, chapters, or HDR were retained when its selected route removes or changes them.
- [ ] Observe positive progress while FFmpeg is still running on a long-enough sample; small packets must not wait until EOF or cause a false inactivity timeout. Check cancelling, verification and completed states as well as final output.
- [ ] Check ordinary files have no redundant warning rows, actual loss notices remain readable after completion, policy details are keyboard accessible, and editor-load failures can be dismissed with recovery guidance in all seven App languages.
- [ ] Run a clean-machine test with a trusted separately installed FFmpeg build. Record the FFmpeg version in release validation notes.

## Licences, copyright, and content

- [ ] Review [LICENSE](../LICENSE), [NOTICE.md](../NOTICE.md), and [AppResources/ASSET_NOTICES.md](../AppResources/ASSET_NOTICES.md) for the assets included in the app bundle.
- [ ] Confirm the shipped release does not contain FFmpeg or another binary that changes the project's dependency or licence obligations. If a tool is later bundled, perform a separate licence and source-offer review.
- [ ] Keep dated provenance records for `AppIcon.icns`, screenshots, the DMG background, the social preview, and every new asset. Obtain permission before using third-party names, logos, screenshots, audio, or video.
- [ ] Do not present the app as granting rights to convert or distribute copyrighted content. Test only with media you are authorised to use.

## Build, signing, and distribution

- [ ] Run `swift build -c release` and `./Scripts/validate-localizations.sh`.
- [ ] Build the DMG with `./Scripts/package-dmg.sh`; use a dedicated `OUTPUT_DIR` for a local test build to preserve existing artifacts. The current workflow signs the app ad-hoc and requires no Developer ID certificate.
- [ ] Verify the mounted final app with `codesign --verify --deep --strict --verbose=2 MP4Flow.app`, confirm the claimed architectures and bundled resources, and disclose that the current build is not notarized.
- [ ] Test the downloaded app's Gatekeeper behaviour on a clean Mac and provide accurate macOS approval instructions. If a future release uses Developer ID, sign nested executable code and the app, notarize and staple the final distribution, and verify the resulting ticket before claiming notarization.
- [ ] Generate and publish the SHA-256 file for the exact final DMG. Treat a checksum as integrity information, not as a signing substitute.
- [ ] Install the final DMG on a clean Intel Mac and Apple-silicon Mac when both architectures are claimed. Test first launch, Gatekeeper, English, Simplified Chinese, French, Russian, Spanish, Japanese, Korean, FFmpeg missing, conversion, trim, crop, rotation, and both merge modes. Confirm English appears first in the language menu.

## Release notes and support

- [ ] Add an accurate dated section to [CHANGELOG.md](../CHANGELOG.md), including known limitations and upgrade notes.
- [ ] Attach the verified final DMG and matching checksum to the GitHub release, with accurate ad-hoc or Developer ID/notarization details.
- [ ] Verify all README links, localized screenshots, support guidance, privacy policy, notices, and security reporting link after publishing.
- [ ] Keep a private release record with macOS version, Xcode/Swift version, FFmpeg version used for tests, signing identity, notarization submission ID, checksum, and validation results. Do not publish sensitive identifiers.
