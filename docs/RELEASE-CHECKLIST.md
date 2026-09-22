# Release checklist

Use this checklist for each public MP4Flow release. It is a release gate, not a claim that an unchecked item has been completed.

## Repository and disclosure

- [x] Create the canonical GitHub repository and replace the clone URL in both README files.
- [ ] Enable GitHub Private Vulnerability Reporting and replace the reporting instruction in [SECURITY.md](../SECURITY.md) with the repository's private reporting link.
- [ ] Confirm the repository description, topics, licence, default branch protection, and release notes follow [GITHUB_METADATA.md](GITHUB_METADATA.md).
- [ ] Check that `.gitignore` is effective and that the branch contains no signing certificates, provisioning profiles, private keys, `.env` files, test media, DMGs, or build products.
- [ ] Review issues, pull requests, screenshots, and logs for private file paths, personal data, or unlicensed media.

## Privacy and security

- [ ] Re-read [PRIVACY.md](../PRIVACY.md) against the release code. Update it before adding telemetry, updates, account features, a network client, persistence, or bundled tools.
- [ ] Verify all FFmpeg and ffprobe invocations use argument arrays, `-nostdin`, and the documented executable locations. Do not add shell interpolation for file paths.
- [ ] Test conversion, cancellation, lossless merge, compatible merge, and a denied output folder. Confirm source files remain unchanged and ordinary failures remove `.partial.mp4` files.
- [ ] Test files with spaces, quotes, Unicode, long names, and line breaks. Lossless Merge must reject line-break filenames; normal conversion must not use a shell.
- [ ] Run a clean-machine test with a trusted separately installed FFmpeg build. Record the FFmpeg version in release validation notes.

## Licences, copyright, and content

- [ ] Review [LICENSE](../LICENSE), [NOTICE.md](../NOTICE.md), and [AppResources/ASSET_NOTICES.md](../AppResources/ASSET_NOTICES.md). Retain the Noto Sans SC OFL notice in the app bundle.
- [ ] Confirm the shipped release does not contain FFmpeg or another binary that changes the project's dependency or licence obligations. If a tool is later bundled, perform a separate licence and source-offer review.
- [ ] Keep dated provenance records for `AppIcon.icns`, screenshots, the DMG background, the README GIF, and every new asset. Obtain permission before using third-party names, logos, screenshots, audio, or video.
- [ ] Do not present the app as granting rights to convert or distribute copyrighted content. Test only with media you are authorised to use.

## Build, signing, and distribution

- [ ] Run `swift build -c release` and `./Scripts/validate-localizations.sh`.
- [ ] Build the DMG with `./Scripts/package-dmg.sh`; it is ad-hoc signed and suitable only for internal testing until the next steps are complete.
- [ ] Re-sign the app and every nested executable with a Developer ID Application certificate. Verify with `codesign --verify --deep --strict --verbose=2 MP4Flow.app`.
- [ ] Submit the final DMG for Apple notarization, staple the ticket, then assess it on a clean Mac with `spctl --assess --type open --context context:primary-signature <DMG>`.
- [ ] Generate and publish the SHA-256 file for the exact notarized DMG. Treat a checksum as integrity information, not as a signing substitute.
- [ ] Install the final DMG on a clean Intel Mac and Apple-silicon Mac when both architectures are claimed. Test first launch, Gatekeeper, English, Simplified Chinese, FFmpeg missing, conversion, trim, crop, rotation, and both merge modes.

## Release notes and support

- [ ] Add an accurate dated section to [CHANGELOG.md](../CHANGELOG.md), including known limitations and upgrade notes.
- [ ] Attach only the notarized DMG and matching checksum to the GitHub release.
- [ ] Verify all README links, the demo GIF, support guidance, privacy policy, notices, and security reporting link after publishing.
- [ ] Keep a private release record with macOS version, Xcode/Swift version, FFmpeg version used for tests, signing identity, notarization submission ID, checksum, and validation results. Do not publish sensitive identifiers.
