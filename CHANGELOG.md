# Changelog

## 1.2.0 — 2026-10-16

### English

- Added a complete Japanese experience: app language selection and system-language detection, bundled Japanese resources, a Japanese website view, Japanese documentation, and Japanese release-note coverage. Existing English and Simplified Chinese choices and video-processing behaviour are unchanged.

### 日本語

- 日本語での利用体験を追加しました。アプリの言語選択とシステム言語の検出、日本語リソースの同梱、日本語の公式サイト、日本語ドキュメント、日本語のリリースノートを含みます。既存の英語・簡体字中国語の選択肢と動画処理の動作は変わりません。

### 中文

- 新增完整日文支持：应用语言选择与系统语言识别、日文资源随应用打包、官网日文页面、日文文档与日文版本说明；原有英语、简体中文选择和视频处理行为保持不变。

## 1.1.2 — 2026-10-15

### English

- Refined update reminders: the first launch stays offline, automatic checks are persisted and limited to once per day, and Settings can disable them. New releases now have a dismissible in-app banner, while manual checks consistently report available, current, or failed status.
- Added update-check regression coverage for semantic versions, trusted release URLs, draft/prerelease filtering, daily backoff, HTTP failures, and timeouts. Updates remain a user-approved visit to the GitHub Release page; they are never downloaded or installed automatically.
- Standardised interface symbols on the bundled Tabler Icons Outline set and refined shared controls for a more consistent macOS experience.

### 日本語

- 更新通知を改善しました。初回起動時はネットワークに接続せず、自動確認は永続化されて1日1回までに制限され、設定から無効にもできます。新しいリリースがある場合は閉じられるアプリ内バナーを表示し、手動確認では更新あり、最新、失敗を一貫して知らせます。
- セマンティックバージョン、信頼できるリリース URL、ドラフト/プレリリースの除外、日次の間隔制御、HTTP 失敗、タイムアウトを対象に更新確認の回帰テストを追加しました。更新は GitHub Releases をユーザーが承認して開く方式であり、自動ダウンロードや自動インストールは行いません。
- 同梱の Tabler Icons Outline セットにインターフェース記号を統一し、共通コントロールを整えて macOS らしい一貫性を高めました。

### 中文

- 完善更新提醒：首次启动不联网，自动检查会持久化并限制为每天最多一次，也可在“设置”中关闭。发现新版本时显示可隐藏的应用内提示；手动检查会一致地反馈有更新、已是最新或检查失败。
- 新增更新检查回归测试，覆盖版本比较、受信任发布链接、草稿/预发布过滤、每日节流、HTTP 失败和超时。更新仍需用户确认后打开 GitHub Release 页面，不会自动下载或安装。
- 统一使用随应用内置的 Tabler Icons Outline 图标，并优化共享控件的视觉一致性。

## 1.1.1 — 2026-09-29

### English

- Added an Environment Check that reports the local FFmpeg/ffprobe installation and available VideoToolbox hardware encoders. Output-folder checks are deferred until a video or a custom destination is known, so launch stays quiet and responsive.
- Made conversion progress explain its current route—inspection, direct remuxing, hardware transcoding, software fallback, and output verification. Added stall timeouts, safe cancellation cleanup, output validation, and recovery guidance for common failures.
- Makes media handling explicit before conversion: MP4Flow reports multi-audio, subtitle, and HDR handling instead of silently implying they were preserved. Added a reproducible 28-case synthetic media regression gate.
- Refined the Environment Check layout, original icon system, centered checking state, and compact action buttons.

### 日本語

- ローカルの FFmpeg、ffprobe、利用可能な VideoToolbox ハードウェアエンコーダを表示する「環境チェック」を追加しました。出力先の確認は動画の追加またはカスタム出力先の選択後まで遅らせ、起動時の静かさと応答性を保ちます。
- 変換の状態で、素材の検査、直接再格納、ハードウェアエンコード、ソフトウェア互換エンコード、出力検証を明示するようにしました。進行停止のタイムアウト、安全なキャンセル後の清掃、出力検証、よくある失敗の回復案内を追加しました。
- 変換前に複数音声、字幕、HDR の扱いを明示し、保持されたと誤解させる表示をしないようにしました。再現可能な28件の合成メディア回帰ゲートも追加しました。
- 環境チェックのレイアウト、独自アイコンシステム、中央揃えの確認状態、コンパクトな操作ボタンを改善しました。

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

### 日本語

- Appleシリコンかつ macOS 27 以降向けに、実験的な「スマート高画質拡大」を追加しました。対応する元解像度と目標解像度の組み合わせでは、システムの VideoToolbox 機能により最大2倍まで拡大できます。
- 解像度の選択肢を元動画に応じて変化させました。音声と映像の同時書き込みに加え、エンコーダ、フレーム処理、終了処理のタイムアウトにより、書き出しが無期限に待機するのを防ぎます。
- 実際の GitHub 更新確認、リンク付きの「情報」パネル、操作に集中したヘルプ画面、明確な復旧案内を追加しました。更新確認は公開リリース情報のみを読み取り、動画や利用データをアップロードしません。

### 中文

- 新增实验性「智能增强放大（macOS 27+）」：在 Apple 芯片 Mac 上调用系统 VideoToolbox 能力，符合条件的源视频最高可放大 2 倍。
- 分辨率选项会随原视频动态调整；音视频并发写入，以及编码器、帧处理、收尾超时保护，可避免任务无限等待。
- 新增真实 GitHub 更新检查、带链接的“关于”页、聚焦操作与排障的帮助窗口。更新检查只读取公开版本信息，不上传视频或使用数据。

## 1.0.1 — 2026-09-23

### English

- Added `−5` and `+5` trim controls for frame-accurate navigation while selecting a clip range.
- Widened trim time fields so start and end timecodes remain fully visible.
- Improved frame stepping by using the source frame rate, cancelling stale preview seeks, and clearly disabling controls at range boundaries.

### 日本語

- クリップ範囲を選ぶ際のフレーム単位の移動のため、トリミング操作に `−5` と `+5` を追加しました。
- 開始と終了のタイムコードが最後まで見えるよう、トリミングの時刻フィールドを広げました。
- 元動画のフレームレートを使い、古いプレビューシークを取り消し、範囲の端では操作を明確に無効化することで、フレーム移動を改善しました。

### 中文

- 剪辑范围选择中新增 `−5` 与 `+5` 帧操作，帮助更精确地定位画面。
- 加宽剪辑时间栏，确保起止时间码完整显示。
- 使用源视频帧率、取消过期预览跳转，并在范围边界清晰禁用控件，优化逐帧定位。

## 1.0.0 — 2026-09-22

### English

- Added English and Simplified Chinese application language support.
- Added a reproducible DMG installer workflow with a Finder installation layout.
- Added open-source documentation, privacy, security, attribution, and contribution guidance.
- Improved queue, conversion, merge, and error text for concise, understandable wording.
- Hardened lossless merge with line-break filename rejection and atomic temporary output publishing.
- Added a release checklist covering FFmpeg trust boundaries, privacy disclosures, asset provenance, signing, notarization, and GitHub release hygiene.

### 日本語

- 英語と簡体字中国語のアプリ言語サポートを追加しました。
- Finder でのインストール配置を含む、再現可能な DMG インストーラのワークフローを追加しました。
- オープンソース向けのドキュメント、プライバシー、セキュリティ、帰属表示、貢献ガイドを追加しました。
- キュー、変換、結合、エラーの文言を、簡潔で分かりやすい表現に改善しました。
- 改行を含むファイル名を拒否し、原子的な一時出力公開を使うことで、ロスレス結合を強化しました。
- FFmpeg の信頼境界、プライバシー開示、アセットの出所、署名、公証、GitHub リリースの運用を確認するリリースチェックリストを追加しました。

### 中文

- 新增中英文应用语言支持。
- 新增可重复执行的 DMG 安装包流程与 Finder 安装布局。
- 新增开源文档、隐私、安全、署名与贡献说明。
- 优化队列、转换、合并与报错文案，使其更简洁易懂。
- 拒绝含换行符的文件名，并使用原子临时输出发布，增强无损合并的可靠性。
- 新增发布检查清单，覆盖 FFmpeg 信任边界、隐私披露、资产来源、签名、公证和 GitHub 发布规范。

## Earlier versions

Earlier development changes are intentionally not retroactively reconstructed. Future release notes follow the Keep a Changelog style.
