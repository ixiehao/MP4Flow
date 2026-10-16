# MP4Flow

> **MP4 への変換を、とても簡単にする、無料・オープンソースのネイティブ macOS 動画変換アプリ。**

[![最新リリース](https://img.shields.io/github/v/release/ixiehao/MP4Flow?display_name=tag&sort=semver&label=release)](https://github.com/ixiehao/MP4Flow/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](https://github.com/ixiehao/MP4Flow/releases/latest)
[![ライセンス](https://img.shields.io/github/license/ixiehao/MP4Flow)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/ixiehao/MP4Flow?style=flat)](https://github.com/ixiehao/MP4Flow/stargazers)

[MP4Flow をダウンロード](https://github.com/ixiehao/MP4Flow/releases/latest) · [公式サイト](https://ixiehao.github.io/MP4Flow/?lang=ja) · [English](README.md) · [简体中文](README.zh-CN.md) · [問題を報告](https://github.com/ixiehao/MP4Flow/issues/new/choose)

MP4Flow は、一般的な動画ファイルを再生しやすい MP4 に変換し、すべての処理を **あなたの Mac 上で** 完結させます。複雑なコーデックの用語を、元の画質を保つ、容量を抑える、互換性を優先する、といった分かりやすい選択肢に置き換えました。トリミング、クロップ、回転、結合にも対応しています。アカウント登録も動画のアップロードも不要で、無料で使えます。

MP4 変換に加えて、動画の一部を切り出し、画面をクロップし、向きを回転できます。macOS に馴染む、速く、軽く、無料でオープンソースの動画変換ツールを目指しています。

![MP4Flow の機能デモ](docs/assets/mp4flow-demo.gif)

*動画を追加し、必要なら簡単に編集して、Mac 上で変換します。*

[ダウンロードとインストール](docs/DOWNLOAD.md) · [インストーラをビルド](docs/INSTALLER-BUILD.md) · [メディア回帰テスト](docs/MEDIA-REGRESSION.md) · [リリースチェックリスト](docs/RELEASE-CHECKLIST.md) · [プライバシー](PRIVACY.ja.md) · [セキュリティ](SECURITY.ja.md)

## ダウンロードとインストール

1. [GitHub の最新リリース](https://github.com/ixiehao/MP4Flow/releases/latest)を開き、`.dmg` と対応する `.sha256` ファイルをダウンロードします。
2. DMG を開き、**MP4Flow** を **Applications** にドラッグします。
3. FFmpeg と ffprobe を一度インストールしてから、アプリ内の **環境チェック** で準備ができていることを確認します。

   ```sh
   brew install ffmpeg
   ```

リリースページとこのリポジトリが公式の配布場所です。開く前にダウンロードを確認したい場合は、[チェックサムの手順](docs/DOWNLOAD.md)を参照してください。

**対応する Mac：** macOS 13 Ventura 以降、Appleシリコンおよび Intel Mac。ハードウェアアクセラレーションの可否は、Mac と元動画のコーデックにより異なります。

## MP4Flow でできること

| やりたいこと | MP4Flow の方法 |
| --- | --- |
| 動画を MP4 に変換 | スマート変換、H.264 互換、HEVC の容量節約、ソフトウェア互換モードを分かりやすく選べます。 |
| できるだけ速く処理 | MP4 を直接再格納できるときは再エンコードしません。対応するトリミングはストリームコピーを使います。 |
| すばやく編集 | 範囲をトリミング、画面をクロップ、90°/180° 回転、または複数の動画を結合してから書き出せます。 |
| 動画を手元に残す | メディア処理はすべて Mac 上で行います。アカウント、分析、動画アップロードサービスはありません。 |

## 主な特徴

- **日本語、英語、簡体字中国語の UI** — 初回起動時はシステム言語に従い、アプリ内で切り替えられます。
- **可能な限り高速** — MP4 の直接再格納とストリームコピーによるトリミングで再エンコードを回避。対応する H.264/HEVC の拡大縮小は Apple VideoToolbox を利用します。
- **分かりやすい変換方法** — スマート変換、明瞭でコンパクト、元の画質を維持、H.264 互換、容量を抑える HEVC、ソフトウェア互換モードを選べます。
- **解像度の制御** — 元の寸法を保つか、アスペクト比を維持したまま 1080p、720p、576p、480p に変換できます。拡大はキャンバスを大きくするもので、存在しない細部を復元するものではありません。
- **実験的なスマート高画質拡大** — Appleシリコンかつ macOS 27 以降では、システムが報告する正確な倍率で VideoToolbox の超解像を利用できます。明示的な選択が必要で、クロップや回転との同時使用にはまだ対応していません。初回利用時にシステムモデルのダウンロードが必要な場合があります。
- **シンプルな編集** — 範囲のトリミング、ドラッグと数値入力によるクロップ、90° または 180° の回転に対応します。
- **2つの結合方法** — ストリームが一致する場合はロスレス結合、異なる場合は表示比率を引き伸ばさず、最大の元解像度に合わせた互換結合を使えます。
- **信頼できるバッチ処理** — 進行状況、失敗項目の再試行、キャンセル、安全な一時出力、既存出力の非上書きを備えます。
- **プライバシーを重視** — 処理は Mac 上にとどまります。出力ではコンテナメタデータとチャプターをコピーしない設定です。機密情報の編集では、共有前に書き出し結果を確認してください。

## 動作環境

- macOS 13 Ventura 以降
- [FFmpeg](https://ffmpeg.org/) と `ffprobe` が `/opt/homebrew/bin`、`/usr/local/bin`、`/opt/local/bin`、または `/usr/bin` にインストール済み
- Appleシリコンまたは Intel Mac。ハードウェアアクセラレーションの可否は Mac と元動画のコーデックにより異なります
- **スマート高画質拡大（実験的）**：Appleシリコン、macOS 27 以降、かつ VideoToolbox が対応する元解像度と目標解像度の組み合わせが必要です。システムは初回使用時にモデルをダウンロードすることがあります。モデルは MP4Flow に同梱されず、MP4Flow が動画を開発者や第三者へ送信することもありません。

Homebrew で FFmpeg をインストールします。

```sh
brew install ffmpeg
```

## 使い方

1. MP4Flow を開き、動画ファイルを追加するかキューにドラッグします。
2. 変換方法、画質/容量、解像度、出力先を選びます。
3. 必要に応じて、待機中の項目でトリミング、クロップ、回転を行います。
4. **変換を開始** を選択します。完了したファイルは Finder で表示できます。

結合するには、編集していない待機中のファイルを少なくとも2つ追加し、**結合** を選びます。ストリームのパラメータが異なる場合は、**互換結合** を選択してください。

## ソースからビルド

```sh
git clone https://github.com/ixiehao/MP4Flow.git
cd MP4Flow
./Scripts/build-app.sh
open MP4Flow.app
```

生成されるアプリにはローカル開発用の ad-hoc 署名が付与されます。配布可能な DMG を作成するには、[インストーラ作成手順](docs/INSTALLER-BUILD.md)を参照してください。

## メディア回帰テスト

FFmpeg をインストールした後、リリース前に合成メディアのテストスイートを実行できます。

```sh
./Scripts/run-media-regression.sh
```

このスクリプトはプロジェクト専用の小さなテスト素材を作成・削除し、H.264、HEVC、可変フレームレート、縦長動画、音声/字幕のバリエーション、回転、HDR シグナル、特殊な寸法、長時間スケジューリング、特殊なファイル名、破損した入力を確認します。公開リリース前には、[メディア回帰ゲート](docs/MEDIA-REGRESSION.md)にある実機テストも完了してください。

## 依存関係とライセンス

- MP4Flow は Swift、SwiftUI、Apple のシステムフレームワークを使用します。
- FFmpeg は外部の実行時依存関係です。アプリは FFmpeg を同梱、ダウンロード、またはライセンスするものではありません。ライセンスはインストールするビルドによって決まります。
- スマート高画質拡大は、現在の Mac と macOS が対応するときに Apple のオンデバイス VideoToolbox フレームワークを使用します。利用可否、対応倍率、モデル配信はオペレーティングシステムによって管理されます。
- 同梱する Noto Sans SC フォントは [SIL Open Font License 1.1](AppResources/OFL.txt) で提供されています。
- アプリは、インターフェース用に [Tabler Icons Outline](https://github.com/tabler/tabler-icons) SVG の厳選した一部（v3.49.0）を同梱しています。実行時のネットワーク依存はなく、[MIT License](AppResources/ASSET_NOTICES.md)の下でローカル利用しています。

帰属表示は [NOTICE.ja.md](NOTICE.ja.md)、データの取り扱いは [PRIVACY.ja.md](PRIVACY.ja.md)、プロジェクトのライセンスは [LICENSE](LICENSE) を参照してください。
