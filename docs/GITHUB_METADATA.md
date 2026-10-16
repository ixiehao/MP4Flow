# GitHub metadata and discovery

Keep these settings in sync with the repository's **About** panel. They are part
of the product's public download path, not optional decoration.

**Description:** `MP4Flow — Free, open-source macOS video converter to MP4. Process locally: convert, trim, crop, rotate, and merge. No upload. ローカル処理。`

**Homepage:** <https://ixiehao.github.io/MP4Flow/>

**Topics:** `macos`, `macos-app`, `apple-silicon`, `swift`, `swiftui`, `ffmpeg`, `video-converter`, `video-transcoder`, `video-editing`, `video-processing`, `mp4`, `h264`, `hevc`, `videotoolbox`, `local-first`, `privacy`, `open-source`, `chinese`, `japanese`

## Public project surfaces

- Keep the README's first screen focused on the value proposition, latest
  release, system requirement, and official download path.
- Keep [README.md](../README.md), [README.ja.md](../README.ja.md), and
  [README.zh-CN.md](../README.zh-CN.md) equivalent in scope. English aids
  global discovery; Japanese and Chinese serve native-language users.
- Link the latest release rather than a versioned DMG in README text. This
  avoids leaving visitors on a stale installer after the next release.
- Attach a `.dmg` and matching `.sha256` file to every stable release. Do not
  call a test, ad-hoc-signed, or unnotarized build a public release.
- Use the [issue chooser](https://github.com/ixiehao/MP4Flow/issues/new/choose)
  for reproducible bugs and feature requests. Keep security reports out of
  public issues.
- Keep the repository social preview and the website Open Graph image aligned;
  both should use the original project social card described below.

## Social preview

**Copy:** `MP4Flow · Video to MP4. Seriously simple.`

Use [`website/assets/social-preview.jpg`](../website/assets/social-preview.jpg) for
the repository social preview. It is a 1280 × 640 px JPEG (under GitHub's 1 MB
recommendation), uses the real English MP4Flow workspace, and contains only
original project artwork around that screenshot.

Regenerate it on macOS after changing the real workspace capture or app icon:

```sh
swift Scripts/create-social-preview.swift \
  website/assets/mp4flow-app-icon.png \
  website/assets/mp4flow-working-screen-en.png \
  website/assets/social-preview.jpg
```

The website publishes this same card through Open Graph and Twitter metadata.
Upload it in the repository's GitHub social-preview setting as well, so GitHub
links and the website share one recognisable visual identity.

Create GitHub releases from signed and notarized DMGs only. Attach the `.dmg` and its matching `.sha256` file, then include the matching section from `CHANGELOG.md` in the release notes. Complete [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) before publishing.
