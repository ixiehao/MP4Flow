# Changelog

## 1.1.1 — 2026-09-29

### English

- Added an Environment Check that reports the local FFmpeg/ffprobe installation and available VideoToolbox hardware encoders. Output-folder checks are deferred until a video or a custom destination is known, so launch stays quiet and responsive.
- Made conversion progress explain its current route—inspection, direct remuxing, hardware transcoding, software fallback, and output verification. Added stall timeouts, safe cancellation cleanup, output validation, and recovery guidance for common failures.
- Makes media handling explicit before conversion: MP4Flow reports multi-audio, subtitle, and HDR handling instead of silently implying they were preserved. Added a reproducible 28-case synthetic media regression gate.
- Refined the Environment Check layout, original icon system, centered checking state, and compact action buttons.

### 中文

- 新增“环境体检”：检查本机 FFmpeg、ffprobe 与可用的 VideoToolbox 硬件编码器。输出位置仅在添加视频或选择自定义目录后检查，启动界面更安静、响应更快。
- 转换状态会明确显示检测素材、快速直封装、硬件转码、软件兼容转码与输出验证；新增无进度超时、安全取消清理、输出校验和常见故障恢复提示。
- 转换前会明确提示多音轨、字幕与 HDR 的处理策略，不再静默暗示它们被保留；新增可重复执行的 28 项合成媒体回归门槛。
- 优化环境体检布局、原创小图标、居中检查状态与紧凑操作按钮。

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
