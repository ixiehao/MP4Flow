# Suggested GitHub metadata

**Description:** MP4Flow — a free, open-source native macOS video-to-MP4 converter. Local processing, clear presets, trimming, cropping, rotation, and lossless or compatible merge.

**Topics:** `macos`, `swiftui`, `swift`, `ffmpeg`, `video-converter`, `mp4`, `videotoolbox`, `privacy`, `chinese`, `localization`

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
