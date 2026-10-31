# Changelog

## 1.4.0 — 2026-10-31

### English
- Added brightness and shadow controls, optional light denoise and live preview.
- Refined the editor; fixed first-open layout, playback progress and crop input sync.

### 中文
- 新增亮度、暗部提亮与可选轻度降噪，支持实时预览。
- 优化编辑界面，修复首次打开布局、播放进度和裁切参数同步。

### 日本語
- 明るさ・暗部補正と軽いノイズ低減を追加。リアルタイムプレビューに対応。
- 編集画面を改善し、初回表示、再生進捗、クロップ入力の不具合を修正。

### 한국어
- 실시간 미리보기로 밝기·어두운 영역을 조정하고 가벼운 노이즈 제거를 선택할 수 있습니다.
- 편집 화면을 개선하고 첫 표시, 재생 진행률, 자르기 입력 동기화 문제를 수정했습니다.

Image adjustments: SDR only; light denoise is off by default. macOS 13+ · FFmpeg/ffprobe required (`brew install ffmpeg`). Ad-hoc signed, not notarized. Apple Silicon tested; physical Intel/macOS 13 testing remains pending.

## 1.3.2 — 2026-10-29

### English
- Added aspect correction with live preview, presets and custom ratios.
- Fixed stretched output when hardware-converting some rotated videos.
- Improved update checks with a fallback and GitHub API rate-limit backoff.

### 中文
- 新增比例矫正，支持实时预览、常用比例和自定义比例。
- 修复部分旋转视频硬件转码后画面拉伸的问题。
- 优化更新检查，增加备用入口和 GitHub API 限流退避。

### 日本語
- 縦横比補正を追加。リアルタイムプレビュー、プリセット、カスタム比率に対応。
- 一部の回転動画で、ハードウェア変換後に画面が引き伸ばされる問題を修正。
- 更新確認に代替経路と GitHub API 制限時の待機処理を追加。

### 한국어
- 실시간 미리보기와 기본·사용자 지정 비율을 지원하는 화면 비율 보정을 추가했습니다.
- 일부 회전 영상의 하드웨어 변환 후 화면이 늘어나는 문제를 수정했습니다.
- 업데이트 확인에 대체 경로와 GitHub API 요청 제한 시 대기 처리를 추가했습니다.

## 1.3.1 — 2026-10-29

### English
- Fixed a blank queue after clearing completed items while scrolled to the bottom.
- Consistent feature names and clearer recovery guidance across seven languages.
- Clearer Homebrew / FFmpeg setup steps; fixed clipped Environment Check details.

### 中文
- 修复滚动到底部清理已完成项后，剩余队列显示空白的问题。
- 统一七语功能名称，优化失败后的操作指引。
- 补齐 Homebrew / FFmpeg 安装步骤，修复环境体检详情显示不全。

### 日本語
- 一覧の最下部で完了項目を削除すると、残りのキューが表示されなくなる問題を修正。
- 7言語の機能名を統一し、エラー時の案内を改善。
- Homebrew / FFmpeg の導入手順を補足し、環境チェックの文字切れを修正。

### 한국어
- 목록 맨 아래에서 완료 항목을 지운 뒤 남은 대기열이 보이지 않는 문제를 수정했습니다.
- 7개 언어의 기능명을 통일하고 오류 해결 안내를 개선했습니다.
- Homebrew / FFmpeg 설치 안내를 보완하고 환경 점검의 잘린 텍스트를 수정했습니다.

## 1.3.0 — 2026-10-26

### English
- Seven App languages: English, Simplified Chinese, French, Russian, Spanish, Japanese and Korean.
- Switch languages from the menu bar. Cleaner header and improved layouts.
- Fixed stalled environment checks, editing completed videos and crop boundaries.

macOS 13+ · Apple Silicon & Intel · FFmpeg/ffprobe required (`brew install ffmpeg`). Ad-hoc signed, not notarized. Tested on Apple Silicon; no physical Intel or macOS 13 testing.

### 中文
- App 支持英语、简体中文、法语、俄语、西班牙语、日语、韩语。
- 从菜单栏切换语言，主界面更简洁，多语言布局更协调。
- 修复环境体检卡住、完成项再次编辑及裁切边界问题。

macOS 13+ · Apple 芯片与 Intel · 需安装 FFmpeg/ffprobe（`brew install ffmpeg`）。沿用 ad-hoc 签名，未公证；已在 Apple 芯片实测，未做 Intel 或 macOS 13 实机测试。

### 日本語
- 英語・簡体字中国語・フランス語・ロシア語・スペイン語・日本語・韓国語に対応。
- 言語切替をメニューバーに集約し、画面をすっきり整理。
- 環境チェックの停止、完了後の再編集、クロップ範囲の不具合を修正。

macOS 13以降 · Appleシリコン／Intel · FFmpeg/ffprobe が必要（`brew install ffmpeg`）。アドホック署名・未公証。Appleシリコンで検証済み。Intel／macOS 13 の実機検証は未実施。

### 한국어
- 영어, 중국어 간체, 프랑스어, 러시아어, 스페인어, 일본어, 한국어를 지원합니다.
- 메뉴 막대에서 언어를 전환합니다. 화면을 간결하게 정리하고 레이아웃을 개선했습니다.
- 환경 검사 멈춤, 완료한 영상의 재편집, 자르기 영역 오류를 수정했습니다.

macOS 13 이상 · Apple Silicon 및 Intel · FFmpeg/ffprobe 필요 (`brew install ffmpeg`). Ad-hoc 서명, Apple 공증 없음. Apple Silicon에서 검증했으며 Intel 및 macOS 13 실기기 테스트는 수행하지 않았습니다.


## 1.2.5 — 2026-10-25

### English

- Fixed black first-frame previews in Finder after trimming and editing videos.
- Removed the bundled Noto Sans SC font and OFL file. MP4Flow now uses macOS system fonts and no longer redistributes font files; the app is substantially smaller.
- Improved conversion cleanup and queue responsiveness, preserved orientation during Smart Enhance, and hardened local packaging checks.

### 日本語

- トリミングや編集後の動画で、Finder のプレビューの最初の画面が黒くなる問題を修正しました。
- 同梱していた Noto Sans SC フォントと OFL ファイルを削除しました。macOS のシステムフォントを使用し、フォントファイルを再配布しない構成になり、アプリが大幅に軽量化しました。
- 変換後の一時ファイル処理とキューの応答性を改善し、スマート高画質拡大の回転方向を維持。ローカルパッケージの安全性チェックも強化しました。

### 中文

- 已修复 Finder 预览首屏黑屏的问题。
- 移除随包的 Noto Sans SC 字体及 OFL 文件，改用 macOS 系统字体，不再随应用分发字体文件，显著缩小应用体积。
- 优化转换任务清理和队列响应，修复智能增强放大后的方向保持问题，并加固本地打包检查。

## 1.2.4 — 2026-10-20

### English

- Important fix: skip embedded cover art and thumbnails when selecting video across conversion, editing, merging, and Smart Enhance.
- Correct multi-video notices and reject input or output that contains only cover art without a movie. Recommended for all users.

### 日本語

- 重要な修正：変換・編集・結合・スマート拡大で、映像の選択対象からカバー画像とサムネイルを除外します。
- 複数映像の通知を修正し、動画を含まずカバー画像しかない入力・出力を拒否します。すべてのユーザーに更新をおすすめします。

### 中文

- 重要修复：转换、编辑、合并和智能增强选取视频时，自动排除内嵌封面和缩略图。
- 修正多路视频提示；没有正片、只有封面的输入或输出将明确报错。建议所有用户更新。

## 1.2.3 — 2026-10-18

### English

- Check for updates once, about 60 seconds after each launch. The footer now shows an update link only when a new version is found, and the update banner follows language changes.
- Manual checks remain in Help; automatic checks can still be turned off in Settings. Updates are never downloaded or installed automatically.

### 日本語

- 起動から約60秒後に更新を1回確認します。新しいバージョンがある場合のみ画面左下にリンクを表示し、更新バナーも言語切替に対応します。
- 手動確認はヘルプから利用でき、自動確認は設定でオフにできます。更新のダウンロードやインストールは自動では行いません。

### 中文

- 每次启动约 60 秒后自动检查一次更新；仅在发现新版本时于左下角显示入口，更新横幅也会跟随语言切换。
- 仍可从“帮助”手动检查，也可在“设置”中关闭自动检查；不会自动下载或安装更新。

## 1.2.2 — 2026-10-18

### English

- Fixed progress displays that could stay at 0% and optimized 1080p-to-720p conversion, late clip seeking, and video copying with audio-only conversion.
- Improved cancellation, retries, and output verification, with fixes for rotation, aspect ratios, variable frame rates, and merging.
- Media warnings now focus on actual content changes, and errors provide clearer reasons and recovery steps. Refined English, Chinese, and Japanese layouts and language switching.

### 日本語

- 進捗が0%のままになる問題を修正。1080pから720pへの変換、後半位置のトリミング、映像をコピーして音声のみ変換する処理を最適化しました。
- キャンセル、再試行、出力検証を強化し、回転・縦横比・可変フレームレート・結合の不整合を修正しました。
- 実際の内容変更に応じた注意事項を表示し、失敗理由と対処方法を明確にしました。日・英・中のレイアウトと言語切替も改善しました。

### 中文

- 修复转换进度停在 0% 的问题，优化 1080p 转 720p、后段精确剪切，以及保留兼容视频、仅转换音频的处理路径。
- 加固取消、重试与输出校验，修复旋转、宽高比、可变帧率及合并中的一致性问题。
- 素材提示聚焦真实内容变化，失败时提供清楚的原因与处理办法；优化中、英、日三语的布局和语言切换。

## 1.2.1 — 2026-10-17

### English

- Improved conversion reliability for stream-rich and occasionally unavailable media. Inspection now drains `ffprobe` output while it runs, and only transient cloud or non-local read failures receive one bounded retry.
- Preserved an explicit software H.264 or HEVC choice when trimming, cropping, or rotating. Cancellation cannot publish an output before final verification; missing sources, permissions, and disk-space errors skip redundant fallback attempts.
- Hardened experimental Smart Enhance around cancellation, audio finalisation, slow frame processing, and late VideoToolbox callbacks. Dependency checks now coalesce and reuse recent results while the queue changes.
- Added generated-media regression coverage for real conversion, retry behaviour, trim/crop/rotation, high-output `ffprobe`, and native enhancement where supported.

### 日本語

- ストリーム数が多い素材や、一時的に読み取りに失敗する素材の変換信頼性を改善しました。検査中に `ffprobe` の出力を逐次読み取り、クラウドまたはローカルではない場所での一時的な読み取り失敗に限って、上限付きで1回だけ再試行します。
- トリミング、クロップ、回転時にも、明示したソフトウェア H.264/HEVC の選択を維持します。最終検証前の出力公開をキャンセル時に防ぎ、入力ファイルなし、権限、空き容量のエラーでは不要なフォールバックを繰り返しません。
- 実験的なスマート高画質拡大のキャンセル、音声の終了処理、遅いフレーム処理、遅延する VideoToolbox コールバックを堅牢化しました。キューの変更中は依存関係の確認を集約し、直近の結果を再利用します。
- 実変換、再試行、トリミング/クロップ/回転、大量出力の `ffprobe`、対応環境でのネイティブ拡大を対象とする生成メディア回帰テストを追加しました。

### 中文

- 提升多流素材和偶发读取失败素材的转换可靠性：检测阶段会持续读取 `ffprobe` 输出；仅对云盘或非本地位置的临时读取失败进行一次有上限的重试。
- 剪切、裁切或旋转时，会保留用户明确选择的软件 H.264/HEVC 编码；取消任务不会在最终校验前发布输出，源文件缺失、权限和磁盘空间错误也不会重复执行无效降级。
- 加固实验性智能增强放大的取消、音频收尾、慢帧处理与 VideoToolbox 延迟回调处理。转换队列变化时，环境检查会合并请求并复用近期结果。
- 新增生成媒体回归覆盖：真实转换、重试行为、剪切/裁切/旋转、大输出 `ffprobe`，以及支持环境下的原生智能增强。

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
