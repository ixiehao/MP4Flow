# Security policy

## Supported versions

Security fixes are applied to the latest release on the `main` branch. Development builds and unsigned or ad-hoc signed DMGs are not supported distribution artifacts.

## Reporting a vulnerability

Do not disclose an exploitable vulnerability in a public issue. Before the first public release, the maintainer must enable GitHub Private Vulnerability Reporting for the repository and publish its Security-tab reporting link here. Until that is available, use a private channel agreed with the maintainer and include the affected version, impact, reproduction steps, and a safe proof of concept. Do not send private media unless it is necessary and you are authorised to share it.

## Security boundaries

- MP4Flow launches only a locally installed `ffmpeg`/`ffprobe` found in its documented fixed locations. It passes media paths as process arguments and does not invoke a shell. The executable itself is outside this repository's trust boundary; install it from a source you trust.
- Generated outputs are first written to a UUID-named partial file and moved into place after a successful conversion or merge. Existing final output names are not intentionally overwritten.
- Lossless merge uses an FFmpeg concat manifest. Filenames containing line breaks are rejected for that mode so they cannot alter the manifest structure.
- The app is not sandboxed and needs the same filesystem access as the user who runs it. Treat untrusted media and untrusted FFmpeg builds with normal macOS caution.

## Release requirements

Before public distribution, build with a Developer ID Application certificate, sign all nested code, notarize the DMG, staple the notarization ticket, and test Gatekeeper behaviour on a clean Mac. See [docs/RELEASE-CHECKLIST.md](docs/RELEASE-CHECKLIST.md) for the full release gate.
