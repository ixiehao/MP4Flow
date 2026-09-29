# Synthetic media fixtures

MP4Flow intentionally does **not** commit video samples to the repository. The
fixtures are generated from FFmpeg `testsrc`, `sine`, and a short project-owned
subtitle string, so contributors do not download or redistribute third-party
video, audio, or captions.

Run the suite from the repository root:

```sh
./Scripts/run-media-regression.sh
```

It creates files only in a unique temporary directory and deletes that directory
afterwards. To inspect the generated files after a failure or while adding a
test, run:

```sh
./Scripts/run-media-regression.sh --keep-fixtures
```

The current fixture contracts are deliberately small but cover the input shapes
that have caused real-world conversion failures:

| Fixture | Contract |
| --- | --- |
| `h264-aac.mp4` | H.264 video and AAC audio baseline |
| `hevc-aac.mp4` | HEVC video and AAC audio baseline |
| `variable-frame-rate.mp4` | Unequal presentation-timestamp gaps |
| `portrait-9x16.mp4` | 180×320 portrait video |
| `no-audio.mp4` | Video-only input |
| `multiple-audio-tracks.mp4` | Two language-tagged AAC tracks |
| `subtitles.mp4` | MP4 timed-text subtitle track |
| `rotation-90.mp4` | Display matrix, rather than rotated encoded pixels |
| `odd-dimensions.mp4` | 319×179 dimensions |
| `hdr-signalled-hevc.mp4` | HEVC with BT.2020/PQ metadata; synthetic bars are not a visual HDR-quality test |
| `long-duration-simulated.mp4` | 12-second low-resolution scheduling sample |
| `spaces ' quote [中文] #1.mp4` | Unicode and shell-sensitive file name |
| `truncated-input.mp4` | Intentionally partial MP4 header |

This suite verifies the fixture contracts and a conservative FFmpeg remux. It
does not automate MP4Flow's SwiftUI workflow; the human release matrix in
[`docs/MEDIA-REGRESSION.md`](../../docs/MEDIA-REGRESSION.md) remains required.
