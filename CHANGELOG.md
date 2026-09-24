# Changelog

## 1.1.0 — 2026-09-24

### English

- Added experimental Smart Enhance Upscale on Apple silicon with macOS 27 or later. Supported source/target pairs can be enlarged by up to 2× through the system VideoToolbox capability.
- Resolution choices now adapt to the source. Audio/video writing is concurrent, and encoder, frame-processing, and finalisation timeouts prevent an export from waiting indefinitely.
- Added a real GitHub update check, a linked About panel, a focused Help window, and clear recovery guidance. Update checks read public release metadata only and never upload videos or usage data.

### 中文

- 新增实验性「智能增强放大（macOS 27+）」：在 Apple 芯片 Mac 上调用系统 VideoToolbox 能力，符合条件的源视频最高可放大 2 倍。
- 分辨率选项会随原视频动态调整；音视频并发写入，以及编码器、帧处理、收尾超时保护，可避免任务无限等待。
- 新增真实 GitHub 更新检查、带链接的“关于”页、聚焦操作与排障的帮助窗口。更新检查只读取公开版本信息，不上传视频或使用数据。

## 1.0.1 — 2026-09-23

- Added `−5` and `+5` trim controls for frame-accurate navigation while selecting a clip range.
- Widened trim time fields so start and end timecodes remain fully visible.
- Improved frame stepping by using the source frame rate, cancelling stale preview seeks, and clearly disabling controls at range boundaries.

## 1.0.0 — 2026-09-22

- Added English and Simplified Chinese application language support.
- Added a reproducible DMG installer workflow with a Finder installation layout.
- Added open-source documentation, privacy, security, attribution, and contribution guidance.
- Improved queue, conversion, merge, and error text for concise, understandable wording.
- Hardened lossless merge with line-break filename rejection and atomic temporary output publishing.
- Added a release checklist covering FFmpeg trust boundaries, privacy disclosures, asset provenance, signing, notarization, and GitHub release hygiene.

## Earlier versions

Earlier development changes are intentionally not retroactively reconstructed. Future release notes follow the Keep a Changelog style.
