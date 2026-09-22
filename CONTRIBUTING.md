# Contributing

Thank you for improving MP4Flow.

1. Discuss substantial changes in an issue before implementation.
2. Keep both English and Simplified Chinese user-facing text clear, short, and consistent. Do not machine-translate codec jargon literally.
3. Build with `swift build` and run `./Scripts/build-app.sh` before a pull request.
4. Do not add telemetry, network calls, or bundled FFmpeg binaries without explicit discussion.
5. Keep changes focused and document user-visible behaviour in `CHANGELOG.md`.

For UI work, test both app languages and narrow windows. For conversion changes, include a sample command or a repeatable description using non-private media.
