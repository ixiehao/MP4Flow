import AppKit
import AVFoundation
import SwiftUI

enum ConversionPreset: String, CaseIterable, Identifiable, Sendable {
    case qualityTop, h264Cap8, smartMP4, smartEnhanceUpscale, h264Hardware, hevcHardware, h264Software, remux
    var id: String { rawValue }

    /// The main menu answers a user's goal first. Encoding-specific fallbacks
    /// stay available, but never compete with the everyday choices.
    static let menuOrder: [ConversionPreset] = [
        .smartMP4, .smartEnhanceUpscale, .h264Cap8, .qualityTop, .h264Hardware,
        .hevcHardware, .h264Software, .remux
    ]

    var menuSection: String {
        switch self {
        case .smartMP4, .smartEnhanceUpscale, .h264Cap8, .qualityTop, .h264Hardware: L10n.text("常用选择")
        case .hevcHardware, .h264Software, .remux: L10n.text("更多选择")
        }
    }

    var title: String {
        switch self {
        case .smartMP4: L10n.text("智能转换（推荐）")
        case .smartEnhanceUpscale: L10n.text("智能增强放大（macOS 27+）")
        case .h264Cap8: L10n.text("清晰又省空间")
        case .qualityTop: L10n.text("尽量保留原画")
        case .h264Hardware: L10n.text("所有设备都能播放")
        case .hevcHardware: L10n.text("节省更多空间")
        case .h264Software: L10n.text("最稳妥转换（较慢）")
        case .remux: L10n.text("只换成 MP4（最快）")
        }
    }
    var detail: String {
        switch self {
        case .smartMP4: L10n.text("自动选择，能不压就不压。")
        case .smartEnhanceUpscale: L10n.text("支持 1280×1080 以下视频，最高 2 倍。")
        case .h264Cap8: L10n.text("清晰省空间，适合大文件。")
        case .qualityTop: L10n.text("保留更多细节，文件更大。")
        case .h264Hardware: L10n.text("旧设备和电视也能播放。")
        case .hevcHardware: L10n.text("文件更小，旧设备可能不支持。")
        case .h264Software: L10n.text("转换失败时使用，速度较慢。")
        case .remux: L10n.text("只换MP4，不压缩画面。")
        }
    }
    var efficiency: Double { self == .hevcHardware ? 0.65 : 1 }
    var usesFixedQuality: Bool { self == .qualityTop || self == .h264Cap8 || self == .remux }
}

enum ConversionQuality: String, CaseIterable, Identifiable, Sendable {
    case compact, balanced, high
    var id: String { rawValue }
    var title: String { switch self { case .compact: L10n.text("文件更小"); case .balanced: L10n.text("清晰刚好"); case .high: L10n.text("画质更好") } }
    var detail: String {
        switch self {
        case .compact: L10n.text("文件更小，细节会少一点。")
        case .balanced: L10n.text("画面和大小都合适。")
        case .high: L10n.text("保留更多细节，文件更大，速度更慢。")
        }
    }
    var multiplier: Double { switch self { case .compact: 0.75; case .balanced: 1; case .high: 1.25 } }
    var crf: Int { switch self { case .compact: 24; case .balanced: 20; case .high: 18 } }
    /// With a fixed byte budget, quality changes compression effort instead
    /// of pretending that more bits are available.
    var targetCompressionPreset: String { switch self { case .compact: "fast"; case .balanced: "medium"; case .high: "slow" } }
}

/// Output size is a separate choice from compression quality. A requested
/// height always preserves the source aspect ratio.
enum OutputResolution: String, CaseIterable, Identifiable, Sendable {
    case original, p1080, p720, p576, p480

    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: L10n.text("保持原画")
        case .p1080: L10n.text("转1080P")
        case .p720: L10n.text("转720P")
        case .p576: L10n.text("转576P")
        case .p480: L10n.text("转480P")
        }
    }
    var detail: String {
        switch self {
        case .original: L10n.text("保持原画尺寸。")
        case .p1080: L10n.text("输出1080P，放大不增细节。")
        case .p720: L10n.text("输出720P，节省空间。")
        case .p576: L10n.text("输出576P，适合宽屏。")
        case .p480: L10n.text("输出480P，最省空间。")
        }
    }
    var targetHeight: Int? {
        switch self {
        case .original: nil
        case .p1080: 1080
        case .p720: 720
        case .p576: 576
        case .p480: 480
        }
    }
    func requiresReencode(sourceHeight: Int?) -> Bool {
        guard let targetHeight else { return false }
        return targetHeight != sourceHeight
    }

    func filter(sourceHeight: Int?, quality: ConversionQuality, useVideoToolbox: Bool, canSkipUnchangedSize: Bool = false) -> String? {
        guard let targetHeight else { return nil }
        if canSkipUnchangedSize && targetHeight == sourceHeight { return nil }
        if useVideoToolbox { return "scale_vt=w=-2:h=\(targetHeight)" }

        // Upscaling cannot recover missing detail. Bicubic is visually stable
        // and much less costly than Lanczos for this common conversion path.
        if let sourceHeight, sourceHeight < targetHeight {
            return "scale=-2:\(targetHeight):flags=bicubic"
        }
        return quality == .high
            ? "scale=-2:\(targetHeight):flags=lanczos"
            : "scale=-2:\(targetHeight):flags=bicubic"
    }

    /// Downscaling needs fewer pixels, so lower the target bitrate too. Upscaling
    /// never raises it: a larger canvas cannot recreate missing image detail.
    func rateMultiplier(sourceHeight: Int?) -> Double {
        guard let targetHeight, let sourceHeight, sourceHeight > targetHeight else { return 1 }
        let ratio = Double(targetHeight) / Double(sourceHeight)
        return ratio * ratio
    }
}

/// A Smart Enhance target is an output height rather than a fixed multiplier.
/// The available choices are calculated per source video and must stay within
/// the native enhancer's practical 2× limit.
enum SmartEnhanceTarget: Int, CaseIterable, Identifiable, Sendable {
    case p480 = 480
    case p576 = 576
    case p720 = 720
    case p1080 = 1080
    case p4K = 2160

    var id: Int { rawValue }
    var title: String { "\(rawValue)P" }
}

enum ConversionState: Equatable {
    case waiting, running(Double?), merging(Double?), complete(URL), failed(String), cancelled
    var color: Color { switch self { case .waiting, .cancelled: .secondary; case .running, .merging: .accentColor; case .complete: .green; case .failed: .red } }
    var label: String { switch self { case .waiting: L10n.text("等待中"); case .running: L10n.text("转换中"); case .merging: L10n.text("正在合并"); case .complete: L10n.text("已完成"); case .failed: L10n.text("失败"); case .cancelled: L10n.text("已取消") } }
    var message: String? {
        switch self {
        case .waiting: nil
        case .running(let value): value == nil ? L10n.text("正在编码（无法读取总时长）") : L10n.text("正在编码")
        case .merging(let value): value == nil ? L10n.text("等待合并") : L10n.text("正在无损合并")
        case .complete(let url): url.lastPathComponent
        case .failed(let message): message
        case .cancelled: L10n.text("已停止；可重新排队。")
        }
    }
}

/// A small, user-facing description of the work currently being performed.
/// It stays separate from `ConversionState` so existing views can keep their
/// simple progress matching while newer views can show the exact strategy.
enum ConversionPhase: Equatable, Sendable {
    case inspecting
    case directRemux
    case audioTranscoding
    case hardwareTranscoding
    case softwareTranscoding
    case verifying

    var title: String {
        switch self {
        case .inspecting: L10n.text("正在检测素材")
        case .directRemux: L10n.text("正在快速直封装")
        case .audioTranscoding: L10n.text("视频直接复制，音频转为 AAC")
        case .hardwareTranscoding: L10n.text("正在硬件转码")
        case .softwareTranscoding: L10n.text("正在兼容转码")
        case .verifying: L10n.text("正在验证输出")
        }
    }
}

/// The failure payload deliberately separates the concise reason shown in a
/// queue row from the next action. `diagnostic` contains no source path or
/// file name, so it is safe to copy into a support report only after the user
/// chooses to do so.
struct ConversionFailure: Equatable, Sendable {
    let reasonKey: String
    let solutionKey: String
    let diagnostic: String?

    var reason: String { L10n.text(reasonKey) }
    var solution: String { L10n.text(solutionKey) }
    var legacyMessage: String { reason }
}

/// Content-loss warnings and optional container details have different visual
/// urgency. Store facts so both remain available after a language change.
struct MediaHandlingNotice: Equatable, Codable, Sendable {
    enum Issue: Equatable, Codable, Sendable {
        case extraVideo(Int)
        case extraAudio(Int)
        case subtitles(Int)
        case chapters(Int)
        case hdrReencoding
        case nonstandardRotation
        case unconfirmed

        var isInformational: Bool {
            if case .chapters = self { return true }
            return false
        }
        var message: String {
            switch self {
            case .extraVideo(let count): L10n.format("检测到 %d 路视频；仅保留第一路。", count)
            case .extraAudio(let count): L10n.format("检测到 %d 路音频；仅保留第一路。", count)
            case .subtitles(let count): L10n.format("检测到 %d 条字幕；输出不保留字幕。", count)
            case .chapters(let count): L10n.format("未保留 %d 个分段书签（章节），不影响视频播放。", count)
            case .hdrReencoding: L10n.format("HDR 将重新编码，色彩或动态范围可能改变；如需保留，请保持原尺寸并使用「%@」。", ConversionPreset.remux.title)
            case .nonstandardRotation: L10n.text("非标准旋转角度将重绘画面；请核对输出方向与边缘。")
            case .unconfirmed: L10n.text("请确认文件可播放后重试；检测完成前不会开始转换。")
            }
        }
    }

    let issues: [Issue]

    // Persist facts, not translated snapshots: completed rows must follow a
    // later language switch just like live status and editor controls do.
    var summary: String { issues.contains(.unconfirmed) ? L10n.text("素材信息尚未确认") : "" }
    var warnings: [String] { issues.filter { !$0.isInformational }.map(\.message) }
    var information: [String] { issues.filter(\.isInformational).map(\.message) }

    var detail: String {
        ([summary] + issues.map(\.message)).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct VideoPresentation: Equatable {
    let duration: Double
    let fileSize: Int64?
    let thumbnail: NSImage?
    let width: Int?
    let height: Int?

    // Keep facts, not a string frozen in the language used when adding the file.
    var factFields: [String] {
        var parts: [String] = []
        if let width, let height { parts.append("\(width) × \(height)") }
        if Self.boundedDuration(duration) > 0 { parts.append(Self.formattedDuration(duration)) }
        if let fileSize { parts.append(L10n.byteCount(fileSize)) }
        return parts
    }
    var summary: String? { factFields.isEmpty ? nil : factFields.joined(separator: " · ") }

    // A restored record has facts but no bitmap. Include image identity so the
    // later thumbnail load is an observable change without comparing pixels.
    static func == (lhs: VideoPresentation, rhs: VideoPresentation) -> Bool {
        lhs.duration == rhs.duration && lhs.fileSize == rhs.fileSize && lhs.width == rhs.width && lhs.height == rhs.height && lhs.thumbnail === rhs.thumbnail
    }

    /// The worker already inspects the source. Reuse those facts after a retry
    /// instead of retaining a failed/older AVFoundation read or probing again.
    static func inspected(_ info: VideoInfo, previous: Self?) -> Self {
        let duration = boundedDuration(info.duration ?? 0)
        let sameFacts = previous?.duration == duration && previous?.fileSize == info.fileSize
            && previous?.width == info.width && previous?.height == info.height
        return Self(duration: duration, fileSize: info.fileSize,
                    thumbnail: sameFacts ? previous?.thumbnail : nil, width: info.width, height: info.height)
    }

    func replacingThumbnail(_ image: NSImage?) -> Self {
        Self(duration: duration, fileSize: fileSize, thumbnail: image, width: width, height: height)
    }

    static func load(from source: URL) async -> VideoPresentation {
        let fileSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let asset = AVURLAsset(url: source)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let naturalSize = try? await track?.load(.naturalSize)

        let image: NSImage?
        if duration.isFinite, duration > 0 {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 192, height: 108)
            let captureTime = CMTime(seconds: min(max(duration * 0.12, 0.1), 3), preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: captureTime, actualTime: nil) {
                image = NSImage(cgImage: cgImage, size: .zero)
            } else {
                image = nil
            }
        } else {
            image = nil
        }
        let width = naturalSize.flatMap { pixelDimension($0.width) }
        let height = naturalSize.flatMap { pixelDimension($0.height) }
        return VideoPresentation(
            duration: boundedDuration(duration),
            fileSize: fileSize.map(Int64.init),
            thumbnail: image,
            width: width,
            height: height
        )
    }

    /// Broken metadata must produce absent facts, never trap the queue while
    /// converting an untrusted framework dimension into an integer.
    static func pixelDimension(_ value: CGFloat) -> Int? {
        guard let pixels = Int(exactly: abs(value).rounded()), pixels > 0 else { return nil }
        return pixels
    }

    static func boundedDuration(_ value: Double) -> Double {
        value.isFinite && value > 0 && value < Double(Int.max / 2) ? value : 0
    }

    private static func formattedDuration(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        if seconds >= 3_600 { return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct ConversionItem: Identifiable, Equatable {
    let id: UUID
    let source: URL
    var state: ConversionState = .waiting
    var presentation: VideoPresentation?
    var trimRange: ClipRange?
    var rotation: VideoRotation?
    var crop: CropRect?
    var aspectRatio: DisplayAspectRatio?
    var imageAdjustment = ImageAdjustment()
    var exportOptions = ExportOptions()
    var outputFileSize: Int64?
    var phase: ConversionPhase?
    var failure: ConversionFailure?
    var mediaHandling: MediaHandlingNotice?

    init(id: UUID = UUID(), source: URL) {
        self.id = id
        self.source = source
    }

    /// Every changed export starts from the original file. The old output is
    /// left on disk, while all result-only fields are cleared together.
    mutating func prepareForExport() {
        state = .waiting
        phase = nil
        failure = nil
        mediaHandling = nil
        outputFileSize = nil
    }

    static func == (lhs: ConversionItem, rhs: ConversionItem) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.state == rhs.state && lhs.presentation == rhs.presentation && lhs.trimRange == rhs.trimRange && lhs.rotation == rhs.rotation && lhs.crop == rhs.crop && lhs.aspectRatio == rhs.aspectRatio && lhs.imageAdjustment == rhs.imageAdjustment && lhs.exportOptions == rhs.exportOptions && lhs.outputFileSize == rhs.outputFileSize && lhs.phase == rhs.phase && lhs.failure == rhs.failure && lhs.mediaHandling == rhs.mediaHandling
    }
}

struct ClipRange: Equatable, Sendable {
    let start: Double
    let end: Double
    var isValid: Bool { start.isFinite && end.isFinite && start >= 0 && end > start && end < Double(Int.max / 2) }
}

struct CropRect: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var filter: String { "crop=\(width):\(height):\(x):\(y)" }
    var summary: String { "\(width) × \(height)" }
}

enum VideoRotation: String, CaseIterable, Equatable, Sendable {
    case clockwise, counterclockwise, upsideDown

    var title: String {
        switch self {
        case .clockwise: L10n.text("顺时针 90°")
        case .counterclockwise: L10n.text("逆时针 90°")
        case .upsideDown: L10n.text("旋转 180°")
        }
    }

    var filter: String {
        switch self {
        case .clockwise: "transpose=1"
        case .counterclockwise: "transpose=2"
        case .upsideDown: "hflip,vflip"
        }
    }

    /// VideoToolbox keeps decoded frames in hardware memory while rotating.
    /// Callers retain the software filter as a compatibility fallback.
    var videoToolboxFilter: String {
        switch self {
        case .clockwise: "transpose_vt=clock"
        case .counterclockwise: "transpose_vt=cclock"
        case .upsideDown: "transpose_vt=reversal"
        }
    }

    /// A quarter turn swaps the encoded width and height. VideoToolbox does
    /// not invert non-square pixel aspect ratios for these transforms, so the
    /// caller must correct the display aspect ratio after the hardware filter.
    var swapsDimensions: Bool {
        switch self {
        case .clockwise, .counterclockwise: true
        case .upsideDown: false
        }
    }

    var fileSuffix: String {
        switch self {
        case .clockwise: "rotated-cw"
        case .counterclockwise: "rotated-ccw"
        case .upsideDown: "rotated-180"
        }
    }
}

/// Dimensions after FFmpeg's automatic orientation correction. Encoded dimensions
/// remain separate because native enhancement and compatible merge use them.
struct VideoGeometry: Equatable, Sendable {
    let width: Int
    let height: Int
    let hasSquarePixels: Bool

    var canSkipUnchangedSize: Bool {
        hasSquarePixels && width.isMultiple(of: 2) && height.isMultiple(of: 2)
    }

    static func displayed(width: Int?, height: Int?, sampleAspectRatio: String?, rotation: Double?) -> VideoGeometry? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        let angle = rotation ?? 0
        guard angle.isFinite else { return nil }
        let quarterTurns = (angle / 90).rounded()
        guard abs(angle - quarterTurns * 90) < 0.01 else { return nil }
        let swapsDimensions = abs(quarterTurns.truncatingRemainder(dividingBy: 2)) == 1
        let squarePixels = sampleAspectRatio == "1:1" || sampleAspectRatio == "1/1"
        return VideoGeometry(width: swapsDimensions ? height : width, height: swapsDimensions ? width : height, hasSquarePixels: squarePixels)
    }
}

struct VideoInfo: Sendable {
    let duration: Double?, videoRate: Int?, audioRate: Int?, width: Int?, height: Int?, hasVideo: Bool
    let videoCodec: String?
    let audioCodec: String?
    let frameRate: String?
    let pixelFormat: String?
    let audioSampleRate: String?
    let audioChannels: Int?
    let audioTrackCount: Int
    let subtitleTrackCount: Int
    let colorTransfer: String?
    let probeSucceeded: Bool
    var fileSize: Int64? = nil
    var colorSpace: String? = nil
    var colorPrimaries: String? = nil
    var colorRange: String? = nil
    var displayGeometry: VideoGeometry? = nil
    var timeBase: String? = nil
    var averageFrameRate: String? = nil
    var sampleAspectRatio: String? = nil
    var displayRotation: Double? = nil
    var videoTrackCount = 0
    var chapterCount = 0
    var selectedVideoStreamIndex: Int? = nil
    var selectedVideoTrackID: Int32? = nil
    var streamLayout: [MediaStreamLayout] = []
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []

    /// Use the exact stream inspected above. The fallback also excludes cover
    /// art, unlike the lowercase `v` selector.
    var videoStreamSpecifier: String {
        selectedVideoStreamIndex.map(String.init) ?? "V:0"
    }

    func geometry(crop: CropRect?, rotation: VideoRotation?) -> VideoGeometry? {
        let geometry: VideoGeometry
        if let crop, crop.width > 0, crop.height > 0 {
            geometry = VideoGeometry(width: crop.width, height: crop.height, hasSquarePixels: displayGeometry?.hasSquarePixels == true)
        } else if let displayGeometry {
            geometry = displayGeometry
        } else {
            return nil
        }
        guard rotation?.swapsDimensions == true else { return geometry }
        return VideoGeometry(width: geometry.height, height: geometry.width, hasSquarePixels: geometry.hasSquarePixels)
    }

    func displayAspectRatio(crop: CropRect? = nil, rotation: VideoRotation? = nil) -> Double? {
        guard let geometry = geometry(crop: crop, rotation: nil) else { return nil }
        let sar = AspectGeometry.pixelRatio(sampleAspectRatio)
        let swaps = abs(((displayRotation ?? 0) / 90).rounded().truncatingRemainder(dividingBy: 2)) == 1
        return AspectGeometry.displayRatio(width: geometry.width, height: geometry.height, pixelRatio: swaps ? 1 / sar : sar, rotation: rotation)
    }

    var hardwareDisplayRotation: VideoRotation? {
        guard let angle = displayRotation, angle.isFinite else { return nil }
        let normalized = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        if abs(normalized - 90) < 0.01 { return .counterclockwise }
        if abs(normalized - 270) < 0.01 { return .clockwise }
        if abs(normalized - 180) < 0.01 { return .upsideDown }
        return nil
    }

    /// Match the demuxer's clock so VFR timestamps are not rounded to the
    /// nominal frame-rate clock. A literal rational also supports older FFmpeg
    /// versions that do not accept the newer symbolic `demux` option.
    var encodingTimeBase: String? {
        guard let timeBase else { return nil }
        let fields = timeBase.split(separator: "/", omittingEmptySubsequences: false)
        guard fields.count == 2, let numerator = Int32(fields[0]), let denominator = Int32(fields[1]),
              numerator > 0, denominator > 0 else { return nil }
        return "\(numerator)/\(denominator)"
    }

    /// A precise cut can fall between frames. Hold the first selected frame
    /// back to zero only for that sub-frame gap, so Quick Look can draw its
    /// paused preview. Keep every later PTS and all audio timing unchanged;
    /// resetting the entire video clock would move it relative to copied AAC.
    /// Longer, intentional leading gaps remain intact.
    var trimmedFirstFrameFilter: String? {
        // VFR's r_frame_rate can describe a timestamp grid (e.g. 90000 Hz),
        // not its playback cadence. Prefer the measured average when valid.
        for rate in [averageFrameRate, frameRate].compactMap({ $0 }) {
            let fields = rate.split(separator: "/", omittingEmptySubsequences: false)
            guard fields.count == 2, let numerator = Int32(fields[0]), let denominator = Int32(fields[1]),
                  numerator > 0, denominator > 0 else { continue }
            return "setpts=if(eq(N\\,0)*between(PTS*TB\\,0\\,\(denominator)/\(numerator)+TB)\\,0\\,PTS)"
        }
        return nil
    }

    var isHDR: Bool {
        ["smpte2084", "arib-std-b67"].contains(colorTransfer?.lowercased() ?? "")
    }

    /// These elementary streams can be placed in MP4 without loss. Restricting
    /// audio to AAC keeps the automatic path broadly compatible with players.
    var canDirectRemuxToMP4: Bool {
        probeSucceeded && hasVideo && canCopyVideoToMP4 && AudioExportPlan(options: ExportOptions(), info: self, target: nil).canCopyAll
    }
    var canCopyVideoToMP4: Bool { ["h264", "hevc"].contains(videoCodec?.lowercased() ?? "") }
    var mergeSignature: MergeSignature? {
        guard let videoCodec, let width, let height, let frameRate, let pixelFormat,
              let timeBase = encodingTimeBase else { return nil }
        let angle = displayRotation ?? 0
        guard angle.isFinite else { return nil }
        let rotation = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return MergeSignature(videoCodec: videoCodec.lowercased(), width: width, height: height, frameRate: frameRate, pixelFormat: pixelFormat, timeBase: timeBase, sampleAspectRatio: sampleAspectRatio, displayRotation: rotation, audioCodec: audioCodec?.lowercased(), audioSampleRate: audioSampleRate, audioChannels: audioChannels, streamLayout: streamLayout, audioTracks: audioTracks.map(AudioStreamSignature.init), colorMetadata: [colorTransfer, colorPrimaries, colorSpace, colorRange])
    }
    var mergePixelAspectRatio: Double {
        guard let sampleAspectRatio else { return 1 }
        let fields = sampleAspectRatio.split(whereSeparator: { $0 == ":" || $0 == "/" })
        guard fields.count == 2, let numerator = Double(fields[0]), let denominator = Double(fields[1]),
              numerator > 0, denominator > 0 else { return 1 }
        let value = numerator / denominator
        return value.isFinite ? value : 1
    }
    var fallbackRate: Int {
        switch Double(width ?? 1920) * Double(height ?? 1080) {
        case ..<1_000_000: 2_000_000
        case ..<2_100_000: 4_000_000
        case ..<4_100_000: 6_000_000
        default: 10_000_000
        }
    }
    var matchedRate: Int { min(max(videoRate ?? fallbackRate, 1), 100_000_000) }
    var safeAudioRate: Int { min(max(audioRate ?? 128_000, 64_000), 192_000) }
    func outputRate(preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, sourceHeight: Int? = nil) -> Int {
        let baseRate: Int
        switch preset {
        case .qualityTop:
            baseRate = min(max(matchedRate, 500_000), 100_000_000)
        case .h264Cap8:
            baseRate = min(max(min(matchedRate, 8_000_000), 500_000), 8_000_000)
        case .smartMP4, .smartEnhanceUpscale, .h264Hardware, .hevcHardware, .h264Software, .remux:
            baseRate = min(max(Int((Double(matchedRate) * preset.efficiency * quality.multiplier).rounded()), 500_000), 100_000_000)
        }
        return min(max(Int((Double(baseRate) * resolution.rateMultiplier(sourceHeight: sourceHeight ?? height)).rounded()), 500_000), 100_000_000)
    }
}

struct MergeSignature: Hashable, Sendable {
    let videoCodec: String
    let width: Int
    let height: Int
    let frameRate: String
    let pixelFormat: String
    let timeBase: String
    let sampleAspectRatio: String?
    let displayRotation: Double
    let audioCodec: String?
    let audioSampleRate: String?
    let audioChannels: Int?
    let streamLayout: [MediaStreamLayout]
    let audioTracks: [AudioStreamSignature]
    let colorMetadata: [String?]
}

struct AudioStreamSignature: Hashable, Sendable {
    let codec: String
    let sampleRate: String?
    let channels: Int?
    let layout: String?
    let timeBase: String?
    let language: String?

    init(_ track: MediaTrack) {
        codec = track.codec.lowercased(); sampleRate = track.sampleRate
        channels = track.channels; layout = track.channelLayout
        timeBase = track.timeBase; language = track.language?.lowercased()
    }
}
