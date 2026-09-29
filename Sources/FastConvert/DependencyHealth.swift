import AppKit
import CoreMedia
import Darwin
import Foundation
import SwiftUI
import VideoToolbox

/// A lightweight preflight for the local tools and folders MP4Flow needs.
///
/// This intentionally runs outside `ConverterStore`: checking an executable or
/// a network-mounted output folder must never delay queue editing or conversion.
@MainActor
final class DependencyHealthMonitor: ObservableObject {
    @Published private(set) var report = DependencyHealthReport.checking
    @Published private(set) var isChecking = false

    private var refreshTask: Task<Void, Never>?

    func refresh(outputDirectory: URL?, sourceDirectories: [URL]) {
        refreshTask?.cancel()
        isChecking = true

        let request = DependencyHealthRequest(
            outputDirectory: outputDirectory,
            sourceDirectories: sourceDirectories
        )
        refreshTask = Task { [weak self] in
            let report = await DependencyHealthProbe.inspect(request)
            guard !Task.isCancelled else { return }
            self?.report = report
            self?.isChecking = false
        }
    }

    deinit { refreshTask?.cancel() }
}

private struct DependencyHealthRequest: Sendable {
    let outputDirectory: URL?
    let sourceDirectories: [URL]
}

enum DependencyHealthLevel: Sendable {
    case checking
    case ready
    case warning
    case failed
}

struct ExecutableHealth: Sendable {
    let level: DependencyHealthLevel
    let name: String
    let path: String?
    let version: String?
}

struct VideoToolboxHealth: Sendable {
    let level: DependencyHealthLevel
    let h264Available: Bool
    let hevcAvailable: Bool
}

struct OutputDirectoryHealth: Sendable {
    let level: DependencyHealthLevel
    let checkedDirectoryCount: Int
    let unavailableDirectoryNames: [String]
    let availableBytes: Int64?
    let usesSourceDirectories: Bool
}

struct DependencyHealthReport: Sendable {
    let ffmpeg: ExecutableHealth
    let ffprobe: ExecutableHealth
    let videoToolbox: VideoToolboxHealth
    let output: OutputDirectoryHealth

    static let checking = DependencyHealthReport(
        ffmpeg: ExecutableHealth(level: .checking, name: "FFmpeg", path: nil, version: nil),
        ffprobe: ExecutableHealth(level: .checking, name: "FFprobe", path: nil, version: nil),
        videoToolbox: VideoToolboxHealth(level: .checking, h264Available: false, hevcAvailable: false),
        output: OutputDirectoryHealth(level: .checking, checkedDirectoryCount: 0, unavailableDirectoryNames: [], availableBytes: nil, usesSourceDirectories: true)
    )

    var overallLevel: DependencyHealthLevel {
        if ffmpeg.level == .failed || ffprobe.level == .failed || output.level == .failed { return .failed }
        if ffmpeg.level == .warning || ffprobe.level == .warning || videoToolbox.level == .warning || output.level == .warning { return .warning }
        if ffmpeg.level == .checking || ffprobe.level == .checking || videoToolbox.level == .checking || output.level == .checking { return .checking }
        return .ready
    }

    var needsFFmpegInstall: Bool { ffmpeg.level == .failed || ffprobe.level == .failed }
}

private enum DependencyHealthProbe {
    /// Keep this list in lockstep with the conversion store. A diagnostic must
    /// never report a binary available when the actual converter cannot use it.
    private static let executableDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        "/usr/bin"
    ]

    static func inspect(_ request: DependencyHealthRequest) async -> DependencyHealthReport {
        await Task.detached(priority: .utility) {
            let ffmpeg = inspectExecutable(named: "ffmpeg")
            let ffprobe = inspectExecutable(named: "ffprobe")
            let encoders = ffmpeg.path.flatMap { path in
                let result = run(URL(fileURLWithPath: path), arguments: ["-hide_banner", "-encoders"], timeout: 4)
                return result.succeeded ? result.output.lowercased() : nil
            }

            // A system codec alone is not enough: FFmpeg must also expose the
            // matching encoder before MP4Flow can use the hardware path.
            let h264System = isHardwareEncoderAvailable(codec: kCMVideoCodecType_H264)
            let hevcSystem = isHardwareEncoderAvailable(codec: kCMVideoCodecType_HEVC)
            let h264Available = h264System && (encoders?.contains("h264_videotoolbox") == true)
            let hevcAvailable = hevcSystem && (encoders?.contains("hevc_videotoolbox") == true)
            let hardware = VideoToolboxHealth(
                level: h264Available || hevcAvailable ? .ready : .warning,
                h264Available: h264Available,
                hevcAvailable: hevcAvailable
            )

            return DependencyHealthReport(
                ffmpeg: ffmpeg,
                ffprobe: ffprobe,
                videoToolbox: hardware,
                output: inspectOutput(request)
            )
        }.value
    }

    private static func inspectExecutable(named name: String) -> ExecutableHealth {
        guard let executable = executableDirectories
            .map({ URL(fileURLWithPath: $0).appendingPathComponent(name) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            return ExecutableHealth(level: .failed, name: name == "ffprobe" ? "FFprobe" : "FFmpeg", path: nil, version: nil)
        }

        let result = run(executable, arguments: ["-version"], timeout: 3)
        guard result.succeeded else {
            return ExecutableHealth(level: .failed, name: name == "ffprobe" ? "FFprobe" : "FFmpeg", path: executable.path, version: nil)
        }

        return ExecutableHealth(
            level: .ready,
            name: name == "ffprobe" ? "FFprobe" : "FFmpeg",
            path: executable.path,
            version: version(in: result.output, toolName: name)
        )
    }

    private static func version(in output: String, toolName: String) -> String? {
        guard let firstLine = output.split(whereSeparator: \.isNewline).first else { return nil }
        let marker = "\(toolName) version "
        guard let range = firstLine.range(of: marker) else { return String(firstLine) }
        return firstLine[range.upperBound...].split(separator: " ").first.map(String.init)
    }

    private static func inspectOutput(_ request: DependencyHealthRequest) -> OutputDirectoryHealth {
        let directories: [URL]
        if let outputDirectory = request.outputDirectory {
            directories = [outputDirectory]
        } else {
            directories = Array(Set(request.sourceDirectories.map {
                $0.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            })).sorted { $0.path < $1.path }
        }

        guard !directories.isEmpty else {
            // The source-folder destination is not known until the user adds
            // media. Treat this as deferred rather than a warning: probing an
            // empty or network-backed location at launch adds noise and can
            // make the app feel stalled.
            return OutputDirectoryHealth(
                level: .ready,
                checkedDirectoryCount: 0,
                unavailableDirectoryNames: [],
                availableBytes: nil,
                usesSourceDirectories: request.outputDirectory == nil
            )
        }

        var unavailable: [String] = []
        var minimumAvailable: Int64?
        for directory in directories {
            let result = inspectDirectory(directory)
            if !result.isWritable { unavailable.append(directory.lastPathComponent) }
            if let bytes = result.availableBytes {
                minimumAvailable = min(minimumAvailable ?? bytes, bytes)
            }
        }

        if !unavailable.isEmpty {
            return OutputDirectoryHealth(
                level: .failed,
                checkedDirectoryCount: directories.count,
                unavailableDirectoryNames: unavailable,
                availableBytes: minimumAvailable,
                usesSourceDirectories: request.outputDirectory == nil
            )
        }

        // We cannot accurately estimate every codec's final file size here.
        // Half a GB is enough to flag likely failures without blocking a user.
        let level: DependencyHealthLevel = (minimumAvailable ?? Int64.max) < 512 * 1_024 * 1_024 ? .warning : .ready
        return OutputDirectoryHealth(
            level: level,
            checkedDirectoryCount: directories.count,
            unavailableDirectoryNames: [],
            availableBytes: minimumAvailable,
            usesSourceDirectories: request.outputDirectory == nil
        )
    }

    private static func inspectDirectory(_ directory: URL) -> (isWritable: Bool, availableBytes: Int64?) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (false, nil)
        }

        let testFile = directory.appendingPathComponent(".mp4flow-write-check-\(UUID().uuidString)")
        let isWritable = fileManager.createFile(atPath: testFile.path, contents: Data(), attributes: nil)
        if isWritable { try? fileManager.removeItem(at: testFile) }

        let attributes = try? fileManager.attributesOfFileSystem(forPath: directory.path)
        let available = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
        return (isWritable, available)
    }

    /// Creating a tiny, hardware-required VideoToolbox session verifies the
    /// system encoder rather than inferring support from a Mac model name.
    private static func isHardwareEncoderAvailable(codec: CMVideoCodecType) -> Bool {
        let specification: CFDictionary = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
        ] as CFDictionary
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: 640,
            height: 360,
            codecType: codec,
            encoderSpecification: specification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr else { return false }
        if let session { VTCompressionSessionInvalidate(session) }
        return true
    }

    private static func run(_ executable: URL, arguments: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            return CommandResult(succeeded: false, output: "")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.025)
        }
        if process.isRunning {
            process.terminate()
            let graceDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.025)
            }
        }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
            + standardError.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            succeeded: process.terminationStatus == 0,
            output: String(data: output, encoding: .utf8) ?? ""
        )
    }
}

private struct CommandResult: Sendable {
    let succeeded: Bool
    let output: String
}

struct DependencyHealthStatusBar: View {
    @ObservedObject var monitor: DependencyHealthMonitor
    let refresh: () -> Void
    let copyFFmpegInstallCommand: () -> Void
    let openHomebrewWebsite: () -> Void
    @State private var isShowingDetails = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color(for: monitor.report.overallLevel))
                .frame(width: 8, height: 8)
            Text(compactSummary)
                .font(AppFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Button {
                isShowingDetails = true
            } label: {
                healthActionMark(.healthCheck)
            }
            .buttonStyle(.plain)
            .help(L10n.text("环境体检"))
            .accessibilityLabel(L10n.text("环境体检"))
            Button {
                refresh()
            } label: {
                healthActionMark(.refresh)
                    .opacity(monitor.isChecking ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(monitor.isChecking)
            .help(L10n.text("重新检查"))
            .accessibilityLabel(L10n.text("重新检查"))
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color(for: monitor.report.overallLevel).opacity(0.24), lineWidth: 1)
        }
        .sheet(isPresented: $isShowingDetails) {
            DependencyHealthSheet(
                monitor: monitor,
                refresh: refresh,
                copyFFmpegInstallCommand: copyFFmpegInstallCommand,
                openHomebrewWebsite: openHomebrewWebsite
            )
        }
    }

    private var compactSummary: String {
        let report = monitor.report
        if monitor.isChecking { return L10n.text("正在检查转换环境…") }
        if report.ffmpeg.level == .failed { return L10n.text("需要安装 FFmpeg") }
        if report.ffprobe.level == .failed { return L10n.text("FFprobe 不可用") }
        if report.output.level == .failed { return L10n.text("输出位置不可写") }
        if report.output.level == .warning && report.output.checkedDirectoryCount == 0 {
            return L10n.text("添加视频后检查输出位置。")
        }
        if report.output.level == .warning { return L10n.text("可用空间较少") }
        if report.videoToolbox.level == .warning { return L10n.text("将使用软件编码") }
        return L10n.format("FFmpeg %@ 已就绪", report.ffmpeg.version ?? "—")
    }

    private var backgroundColor: Color {
        switch monitor.report.overallLevel {
        case .failed: BrandColor.warningBackground
        case .warning: BrandColor.warningBackground.opacity(0.62)
        case .ready, .checking: BrandColor.surface
        }
    }

    private func healthActionMark(_ kind: MarkKind) -> some View {
        Mark(kind: kind, color: BrandColor.blue)
            .frame(width: 15, height: 15)
            .frame(width: 29, height: 28)
            .background(BrandColor.blue.opacity(0.075), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct DependencyHealthSheet: View {
    @ObservedObject var monitor: DependencyHealthMonitor
    let refresh: () -> Void
    let copyFFmpegInstallCommand: () -> Void
    let openHomebrewWebsite: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Mark(kind: .healthCheck, color: color(for: monitor.report.overallLevel))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("环境体检"))
                        .font(.system(size: 18, weight: .bold))
                    Text(L10n.text("检查本机转换依赖与硬件编码；输出位置在添加视频后检查。"))
                        .font(AppFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                Spacer()
                Button { refresh() } label: {
                    HStack(spacing: 6) {
                        Mark(kind: .refresh, color: BrandColor.blue).frame(width: 13, height: 13)
                        Text(L10n.text("重新检查"))
                    }
                }
                    .buttonStyle(HealthSheetActionButtonStyle(primary: false))
                    .disabled(monitor.isChecking)
            }

            if monitor.isChecking {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.text("正在检查…"))
                        .font(AppFont.captionMedium)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
            }

            healthRow(
                title: "FFmpeg",
                level: monitor.report.ffmpeg.level,
                detail: executableDetail(monitor.report.ffmpeg),
                fix: monitor.report.ffmpeg.level == .failed ? L10n.text("请在终端执行 brew install ffmpeg，然后重新检查。") : nil
            )
            healthRow(
                title: "FFprobe",
                level: monitor.report.ffprobe.level,
                detail: executableDetail(monitor.report.ffprobe),
                fix: monitor.report.ffprobe.level == .failed ? L10n.text("请重新安装 FFmpeg：brew reinstall ffmpeg。") : nil
            )
            healthRow(
                title: "VideoToolbox",
                level: monitor.report.videoToolbox.level,
                detail: hardwareDetail,
                fix: monitor.report.videoToolbox.level == .warning ? L10n.text("将使用软件编码；速度可能较慢。") : nil
            )
            if monitor.report.output.checkedDirectoryCount > 0 || monitor.report.output.level == .failed {
                healthRow(
                    title: L10n.text("输出位置"),
                    level: monitor.report.output.level,
                    detail: outputDetail,
                    fix: outputFix
                )
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("处理策略"))
                    .font(AppFont.captionMedium)
                Text(L10n.text("默认仅输出第一路视频和音频，并移除容器元数据和章节。开始转换时会检测多音轨、字幕和 HDR，并在队列中提示。"))
                    .font(AppFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(BrandColor.selectSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack(spacing: 8) {
                if monitor.report.needsFFmpegInstall {
                    Button(L10n.text("复制安装命令")) { copyFFmpegInstallCommand() }
                        .buttonStyle(HealthSheetActionButtonStyle(primary: true))
                    Button(L10n.text("打开 Homebrew 官网")) { openHomebrewWebsite() }
                        .buttonStyle(HealthSheetActionButtonStyle(primary: false))
                }
                Spacer()
                Button(L10n.text("完成")) { dismiss() }
                    .buttonStyle(HealthSheetActionButtonStyle(primary: true))
            }
        }
        .padding(22)
        .frame(width: 540)
    }

    @ViewBuilder
    private func healthRow(title: String, level: DependencyHealthLevel, detail: String, fix: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color(for: level)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppFont.captionMedium)
                Text(detail).font(AppFont.caption).foregroundStyle(BrandColor.textSecondary)
                if let fix {
                    Text(fix).font(AppFont.caption).foregroundStyle(level == .failed ? .red : BrandColor.warning)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(BrandColor.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func executableDetail(_ executable: ExecutableHealth) -> String {
        guard let path = executable.path else { return L10n.text("未找到") }
        if let version = executable.version { return L10n.format("版本：%@ · %@", version, path) }
        return L10n.format("路径：%@", path)
    }

    private var hardwareDetail: String {
        let health = monitor.report.videoToolbox
        let codecs = [
            health.h264Available ? "H.264" : nil,
            health.hevcAvailable ? "HEVC" : nil
        ].compactMap { $0 }
        if codecs.isEmpty { return L10n.text("未检测到可用的 FFmpeg VideoToolbox 编码器。") }
        return L10n.format("可用硬件编码：%@。", codecs.joined(separator: " / "))
    }

    private var outputDetail: String {
        let output = monitor.report.output
        if output.checkedDirectoryCount == 0 { return L10n.text("将输出到原视频所在文件夹；添加视频后检查。") }
        if output.level == .failed {
            let names = output.unavailableDirectoryNames.prefix(2).joined(separator: "、")
            return L10n.format("已检查 %d 个文件夹；无法写入：%@", output.checkedDirectoryCount, names)
        }
        var result = L10n.format("已检查 %d 个输出文件夹，可写。", output.checkedDirectoryCount)
        if let bytes = output.availableBytes {
            result += " " + L10n.format("可用空间：%@", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        return result
    }

    private var outputFix: String? {
        switch monitor.report.output.level {
        case .failed: return L10n.text("请选择可写的文件夹或检查磁盘权限。")
        case .warning where monitor.report.output.checkedDirectoryCount > 0:
            return L10n.text("可用空间较少；建议至少保留 1 GB。")
        default: return nil
        }
    }
}

/// Matches the compact visual language used by MP4Flow's editor actions,
/// without inheriting AppKit's mismatched bordered-button metrics.
private struct HealthSheetActionButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.captionMedium)
            .foregroundStyle(primary ? Color.white : BrandColor.blue)
            .lineLimit(1)
            .padding(.horizontal, primary ? 14 : 12)
            .frame(minHeight: 32)
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(primary ? Color.clear : BrandColor.selectStroke, lineWidth: 1)
            }
            .shadow(color: primary ? BrandColor.blue.opacity(configuration.isPressed ? 0 : 0.16) : .black.opacity(0.035), radius: primary ? 4 : 1.5, y: primary ? 2 : 1)
            .opacity(isEnabled ? 1 : 0.46)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func background(pressed: Bool) -> Color {
        if primary { return pressed ? BrandColor.blue.opacity(0.82) : BrandColor.blue }
        return pressed ? BrandColor.selectHover : BrandColor.surface
    }
}

private func color(for level: DependencyHealthLevel) -> Color {
    switch level {
    case .ready: BrandColor.success
    case .warning: BrandColor.warning
    case .failed: .red
    case .checking: BrandColor.blue
    }
}
