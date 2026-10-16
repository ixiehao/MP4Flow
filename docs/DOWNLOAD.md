# Download and install / 下载与安装

## English

### Get MP4Flow

1. Download the current `.dmg` from [GitHub Releases](https://github.com/ixiehao/MP4Flow/releases/latest). The release also includes a matching `.sha256` file.
2. Open the DMG and drag **MP4Flow** to **Applications**.
3. Install the two local video tools the app needs:

   ```sh
   brew install ffmpeg
   ```

4. Open MP4Flow and use **Environment Check**. It confirms that both `ffmpeg` and `ffprobe` can be found and reports the available hardware encoders.

MP4Flow supports macOS 13 Ventura or later on Apple Silicon and Intel Macs. Processing is local: the app does not upload your videos or require an account.

### Verify a download (optional)

Run the following commands in Terminal after downloading a release. Replace the filename with the downloaded version.

```sh
cd ~/Downloads
shasum -a 256 MP4Flow-<version>.dmg
cat MP4Flow-<version>.dmg.sha256
```

The two SHA-256 values must match. If they do not, delete the DMG and download it again from the [official Releases page](https://github.com/ixiehao/MP4Flow/releases/latest).

## 中文

### 下载 MP4Flow

1. 从 [GitHub Releases](https://github.com/ixiehao/MP4Flow/releases/latest) 下载当前版本的 `.dmg`；同一页还有对应的 `.sha256` 校验文件。
2. 打开 DMG，把 **MP4Flow** 拖到 **Applications（应用程序）**。
3. 安装应用所需的两个本地视频工具：

   ```sh
   brew install ffmpeg
   ```

4. 打开 MP4Flow 后，点击「环境体检」。它会确认是否能找到 `ffmpeg` 和 `ffprobe`，并显示当前 Mac 可用的硬件编码器。

MP4Flow 支持 macOS 13 Ventura 或更高版本，并兼容 Apple 芯片与 Intel Mac。视频始终在本机处理：无需账户，也不会上传。

### 可选：校验下载文件

下载 Release 后，可在“终端”执行以下命令。将文件名替换为你实际下载的版本。

```sh
cd ~/Downloads
shasum -a 256 MP4Flow-<version>.dmg
cat MP4Flow-<version>.dmg.sha256
```

两处 SHA-256 值必须完全一致。如果不一致，请删除该 DMG，并从[官方 Release 页面](https://github.com/ixiehao/MP4Flow/releases/latest)重新下载。
