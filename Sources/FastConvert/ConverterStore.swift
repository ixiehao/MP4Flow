import AppKit
import AVFoundation
import Darwin
import SwiftUI
import UniformTypeIdentifiers

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

/// Explicitly documents what a conversion will and will not carry forward.
/// This prevents the current first-video/first-audio mapping from silently
/// surprising users, and gives the UI one value to present before start.
struct MediaHandlingNotice: Equatable, Sendable {
    enum Issue: Equatable, Sendable {
        case extraVideo(Int)
        case extraAudio(Int)
        case subtitles(Int)
        case chapters(Int)
        case hdrReencoding
        case nonstandardRotation
        case unconfirmed

        var warning: String {
            switch self {
            case .extraVideo(let count): L10n.format("检测到 %d 路视频；仅保留第一路。", count)
            case .extraAudio(let count): L10n.format("检测到 %d 路音频；仅保留第一路。", count)
            case .subtitles(let count): L10n.format("检测到 %d 条字幕；输出不保留字幕。", count)
            case .chapters(let count): L10n.format("检测到 %d 个章节；输出不保留章节。", count)
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
    var warnings: [String] { issues.map(\.warning) }

    var detail: String {
        ([summary] + warnings).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct VideoPresentation: Equatable {
    let duration: Double
    let fileSize: Int64?
    let thumbnail: NSImage?
    let width: Int?
    let height: Int?

    // Keep facts, not a string frozen in the language used when adding the file.
    var summary: String? {
        var parts: [String] = []
        if let width, let height { parts.append("\(width) × \(height)") }
        if duration.isFinite, duration > 0 { parts.append(Self.formattedDuration(duration)) }
        if let fileSize { parts.append(L10n.byteCount(fileSize)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // NSImage itself is not Equatable; compare the source facts.
    static func == (lhs: VideoPresentation, rhs: VideoPresentation) -> Bool {
        lhs.duration == rhs.duration && lhs.fileSize == rhs.fileSize && lhs.width == rhs.width && lhs.height == rhs.height
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
        let width = naturalSize.map { Int(abs($0.width).rounded()) }.flatMap { $0 > 0 ? $0 : nil }
        let height = naturalSize.map { Int(abs($0.height).rounded()) }.flatMap { $0 > 0 ? $0 : nil }
        return VideoPresentation(
            duration: duration.isFinite ? duration : 0,
            fileSize: fileSize.map(Int64.init),
            thumbnail: image,
            width: width,
            height: height
        )
    }

    private static func formattedDuration(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        if seconds >= 3_600 { return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct ConversionItem: Identifiable, Equatable {
    let id = UUID()
    let source: URL
    var state: ConversionState = .waiting
    var presentation: VideoPresentation?
    var trimRange: ClipRange?
    var rotation: VideoRotation?
    var crop: CropRect?
    var aspectRatio: DisplayAspectRatio?
    var imageAdjustment = ImageAdjustment()
    var phase: ConversionPhase?
    var failure: ConversionFailure?
    var mediaHandling: MediaHandlingNotice?

    static func == (lhs: ConversionItem, rhs: ConversionItem) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.state == rhs.state && lhs.presentation == rhs.presentation && lhs.trimRange == rhs.trimRange && lhs.rotation == rhs.rotation && lhs.crop == rhs.crop && lhs.aspectRatio == rhs.aspectRatio && lhs.imageAdjustment == rhs.imageAdjustment && lhs.phase == rhs.phase && lhs.failure == rhs.failure && lhs.mediaHandling == rhs.mediaHandling
    }
}

struct ClipRange: Equatable, Sendable {
    let start: Double
    let end: Double
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
        canCopyVideoToMP4 && (audioCodec == nil || audioCodec?.lowercased() == "aac")
    }
    var canCopyVideoToMP4: Bool { ["h264", "hevc"].contains(videoCodec?.lowercased() ?? "") }
    fileprivate var mergeSignature: MergeSignature? {
        guard let videoCodec, let width, let height, let frameRate, let pixelFormat,
              let timeBase = encodingTimeBase else { return nil }
        let angle = displayRotation ?? 0
        guard angle.isFinite else { return nil }
        let rotation = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return MergeSignature(videoCodec: videoCodec.lowercased(), width: width, height: height, frameRate: frameRate, pixelFormat: pixelFormat, timeBase: timeBase, sampleAspectRatio: sampleAspectRatio, displayRotation: rotation, audioCodec: audioCodec?.lowercased(), audioSampleRate: audioSampleRate, audioChannels: audioChannels, streamLayout: streamLayout)
    }
    fileprivate var mergePixelAspectRatio: Double {
        guard let sampleAspectRatio else { return 1 }
        let fields = sampleAspectRatio.split(whereSeparator: { $0 == ":" || $0 == "/" })
        guard fields.count == 2, let numerator = Double(fields[0]), let denominator = Double(fields[1]),
              numerator > 0, denominator > 0 else { return 1 }
        let value = numerator / denominator
        return value.isFinite ? value : 1
    }
    var fallbackRate: Int {
        switch (width ?? 1920) * (height ?? 1080) {
        case ..<1_000_000: 2_000_000
        case ..<2_100_000: 4_000_000
        case ..<4_100_000: 6_000_000
        default: 10_000_000
        }
    }
    var matchedRate: Int { videoRate ?? fallbackRate }
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

private struct MergeSignature: Hashable, Sendable {
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
}

private struct CompatibleMergeTarget: Sendable {
    let width: Int
    let height: Int
    let frameRate: String

    var summary: String { "\(width) × \(height)" }
}

private struct ProbeResponse: Decodable, Sendable { let streams: [ProbeStream]; let format: ProbeFormat?; let chapters: [ProbeChapter]? }
private struct ProbeChapter: Decodable, Sendable {}
private struct ProbeStream: Decodable, Sendable {
    let index: Int?, id: String?, disposition: MediaStreamDisposition?
    let codecType: String?, codecName: String?, bitRate: String?, width: Int?, height: Int?
    let rFrameRate: String?, avgFrameRate: String?, pixelFormat: String?, sampleRate: String?, channels: Int?, colorTransfer: String?
    let colorSpace: String?, colorPrimaries: String?, colorRange: String?
    let sampleAspectRatio: String?, timeBase: String?, sideDataList: [ProbeSideData]?, tags: [String: String]?
    enum CodingKeys: String, CodingKey {
        case index, id, disposition
        case codecType = "codec_type", codecName = "codec_name", bitRate = "bit_rate"
        case rFrameRate = "r_frame_rate", pixelFormat = "pix_fmt", sampleRate = "sample_rate", channels, width, height
        case avgFrameRate = "avg_frame_rate"
        case colorTransfer = "color_transfer", colorSpace = "color_space", colorPrimaries = "color_primaries", colorRange = "color_range"
        case sampleAspectRatio = "sample_aspect_ratio", timeBase = "time_base", sideDataList = "side_data_list", tags
    }

    var isMovieVideo: Bool { codecType == "video" && disposition?.isAuxiliaryImage != true }

    var nativeTrackID: Int32? {
        guard let id else { return nil }
        let value = id.lowercased()
        let parsed = value.hasPrefix("0x") ? UInt32(value.dropFirst(2), radix: 16) : UInt32(value)
        return parsed.flatMap { $0 != 0 ? Int32(bitPattern: $0) : nil }
    }
}
private struct ProbeSideData: Decodable, Sendable { let rotation: Double? }
private struct ProbeFormat: Decodable, Sendable {
    let duration: String?, bitRate: String?, name: String?
    enum CodingKeys: String, CodingKey { case duration, bitRate = "bit_rate", name = "format_name" }

    // MPEG-TS IDs are PIDs, not AVFoundation persistent track IDs. Only the
    // MOV/MP4 family guarantees that these identifiers refer to the same track.
    var usesNativeTrackIDs: Bool { name?.split(separator: ",").contains("mov") == true }
}

/// Only retry a full transcode when FFmpeg clearly identifies a VideoToolbox
/// component that can be replaced. Generic decode, mux, timeout, and I/O errors
/// are deliberately not retried: replaying a long file would waste time and
/// would not address the underlying failure.
enum FFmpegHardwareRetryHint: Equatable {
    case cpuDecodeAndFilter
    case softwareEncoder
}

enum FFmpegHardwareRetryClassifier {
    static func hint(stderr: String, usedHardwarePipeline: Bool, usedHardwareEncoder: Bool) -> FFmpegHardwareRetryHint? {
        guard usedHardwarePipeline || usedHardwareEncoder else { return nil }
        let lines = stderr.lowercased().components(separatedBy: .newlines)
        let terminalFailure = [
            "no space left", "disk full", "permission denied", "operation not permitted",
            "could not write header", "error opening output", "error writing output", "muxer",
            "invalid data found when processing input", "moov atom not found", "broken pipe",
            "out of memory", "cannot allocate memory", "not enough memory", "timed out", "timeout",
            "terminated by signal", "received signal"
        ].contains { marker in lines.contains(where: { $0.contains(marker) }) }
        guard !terminalFailure else { return nil }

        if usedHardwarePipeline {
            if lines.contains(where: { $0.contains("display_rotation") && ($0.contains("unrecognized option") || $0.contains("option not found")) }) {
                return .cpuDecodeAndFilter
            }
            let filterMarkers = ["scale_vt", "transpose_vt"]
            let filterFailurePhrases = [
                "no such filter", "not found", "not supported", "failed", "error",
                "impossible to convert", "cannot convert"
            ]
            if lines.contains(where: { line in
                filterMarkers.contains(where: line.contains) && filterFailurePhrases.contains(where: line.contains)
            }) {
                return .cpuDecodeAndFilter
            }

            let decoderMarkers = ["videotoolbox_vld", "vtdecompressionsession", "kvtvideodecoder", "hwaccel", "hwcontext"]
            let decoderFailurePhrases = [
                "failed to create", "device setup failed", "failed to initialize", "failed to initialise",
                "failed to get format", "no device available", "no hardware device", "unsupported pixel format",
                "error creating device", "decoder initialization failed", "decoder initialisation failed"
            ]
            if lines.contains(where: { line in
                (decoderMarkers.contains(where: line.contains) || line.contains("device setup failed for decoder"))
                    && decoderFailurePhrases.contains(where: line.contains)
            }) {
                return .cpuDecodeAndFilter
            }
        }

        guard usedHardwareEncoder else { return nil }
        let encoderMarkers = ["h264_videotoolbox", "hevc_videotoolbox", "vtcompressionsession", "kvtvideoencoder"]
        let encoderFailurePhrases = [
            "unknown encoder", "failed", "failure", "error", "not available",
            "could not open", "cannot create", "unable to open"
        ]
        guard lines.contains(where: { line in
            encoderMarkers.contains(where: line.contains) && encoderFailurePhrases.contains(where: line.contains)
        }) else { return nil }
        return .softwareEncoder
    }
}

@MainActor
final class ConverterStore: ObservableObject {
    @Published var items: [ConversionItem] = []
    @Published var preset: ConversionPreset = .smartMP4
    @Published var quality: ConversionQuality = .balanced
    @Published var outputResolution: OutputResolution = .original
    @Published var smartEnhanceTarget: SmartEnhanceTarget = .p720
    @Published var outputDirectory: URL?
    @Published var isRunning = false
    @Published var overallProgress: Double?
    @Published var statusText = ""
    @Published var showFFmpegSetup = false
    @Published private(set) var isMerging = false
    @Published private(set) var isVerifyingMerge = false
    @Published var showMergeNotice = false
    @Published var showCompatibleMergePrompt = false
    @Published private(set) var mergeNotice = ""
    @Published private(set) var mergeOutput: URL?
    @Published private(set) var mergeProgress: Double?

    private let ffmpegOverride: URL?
    private var ffmpegURL: URL?
    private var activeProcesses: [UUID: FFmpegProcessRunner] = [:]
    private var cancellationRequested = false
    // Queue order is held by convertQueue's snapshot; membership checks happen
    // on every progress update and must stay constant-time for large batches.
    private var queueIDs: Set<UUID> = []
    private var progressTimes: [UUID: Double] = [:]
    private var progressBuffers: [UUID: String] = [:]
    private var progressGeneration: [UUID: UUID] = [:]
    private var lastProgressUpdate: [UUID: Date] = [:]
    private var mergeItemIDs: [UUID] = []
    private var mergeDurations: [Double?] = []
    private var mergeProgressBuffer = ""
    private var mergeProgressTime: Double?
    private var mergeProgressGeneration: UUID?
    private var compatibleMergeIDs: [UUID] = []
    private var isCompatibleMerging = false
    /// FFmpeg emits a machine-readable progress packet roughly twice a second
    /// while it is healthy. A generous limit avoids mistaking a slow decoder
    /// startup for a hang while still recovering from blocked network volumes,
    /// broken inputs, or wedged hardware sessions.
    private let ffmpegNoProgressTimeout: TimeInterval = 90
    private let ffmpegTerminationGrace: UInt64 = 3_000_000_000
    private var processConfiguration: FFmpegProcessRunner.Configuration {
        FFmpegProcessRunner.Configuration(
            inactivityTimeout: ffmpegNoProgressTimeout,
            terminationGrace: Double(ffmpegTerminationGrace) / 1_000_000_000,
            activityPolicy: .advancingFFmpegProgress,
            maximumOutputBytes: 0
        )
    }
    private let presentationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.ixiehao.mp4flow.media-inspection"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    /// A local tool override lets integration tests exercise the real queue
    /// through a controlled FFmpeg executable; normal app launches use the
    /// existing installation search below.
    init(ffmpegOverride: URL? = nil) {
        self.ffmpegOverride = ffmpegOverride
    }

    var hasWaiting: Bool { items.contains { if case .waiting = $0.state { return true }; return false } }
    var hasCompleted: Bool { items.contains { if case .complete = $0.state { return true }; return false } }
    var hasIncomplete: Bool { items.contains { if case .failed = $0.state { return true }; if case .cancelled = $0.state { return true }; return false } }
    var mergeCandidateCount: Int { items.reduce(into: 0) { if case .waiting = $1.state, $1.trimRange == nil, $1.rotation == nil, $1.crop == nil, $1.aspectRatio == nil, $1.imageAdjustment.isIdentity { $0 += 1 } } }
    var mergeDisplayCount: Int { isMerging ? mergeItemIDs.count : mergeCandidateCount }
    var canMerge: Bool { !isBusy && mergeCandidateCount >= 2 }
    var isBusy: Bool { isRunning || isMerging }
    var isCancelling: Bool { isBusy && cancellationRequested }
    var mergeModeTitle: String { isCompatibleMerging ? L10n.text("兼容合并") : L10n.text("无损合并") }
    var isFFmpegAvailable: Bool { locateFFmpeg() != nil }
    /// Only items still in the queue are counted. Removing completed rows must
    /// immediately change both the header count and this footer count.
    var activeBatchProgressLabel: String? {
        let activeItems = items.filter { queueIDs.contains($0.id) }
        guard !activeItems.isEmpty else { return nil }
        let processed = activeItems.reduce(into: 0) { count, item in
            switch item.state {
            case .complete, .failed, .cancelled: count += 1
            case .waiting, .running, .merging: break
            }
        }
        return L10n.format("已处理 %d/%d", processed, activeItems.count)
    }
    var qualityDescription: String {
        switch preset {
        case .qualityTop:
            return L10n.text("当前方式已设定画质。")
        case .h264Cap8:
            return L10n.text("当前方式已设定画质。")
        case .remux:
            return L10n.text("只换格式，不压缩画面。")
        case .smartMP4, .h264Hardware, .hevcHardware, .h264Software, .smartEnhanceUpscale:
            break
        }
        return quality.detail
    }

    var smartEnhanceTargets: [SmartEnhanceTarget] {
        guard #available(macOS 27.0, *),
              let presentation = items.first?.presentation,
              let width = presentation.width,
              let height = presentation.height else { return [] }
        return SmartEnhancePlan.availableTargets(sourceWidth: width, sourceHeight: height)
    }

    func reconcileSmartEnhanceTarget() {
        let targets = smartEnhanceTargets
        guard !targets.isEmpty else { return }
        if !targets.contains(smartEnhanceTarget) {
            smartEnhanceTarget = targets[0]
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true; panel.prompt = L10n.text("添加视频")
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = L10n.text("选择输出位置")
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }

    func useSourceDirectories() { outputDirectory = nil }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                guard let store = self else { return }
                Task { @MainActor [store] in store.add([url]) }
            }
        }
        return true
    }

    /// Completed rows can be removed while another item is running. Remove their
    /// IDs from the active batch as well so every visible count stays in sync.
    func clearCompleted() {
        let completedIDs = Set(items.compactMap { item -> UUID? in
            if case .complete = item.state { return item.id }
            return nil
        })
        guard !completedIDs.isEmpty else { return }
        items.removeAll {
            if case .complete = $0.state { return true }
            return false
        }
        queueIDs.subtract(completedIDs)
        if isRunning { refreshProgress(queueIDs.count) }
    }
    /// Removes queue records only. Source files and generated outputs remain untouched.
    func clearQueue() {
        guard !isBusy else { return }
        presentationQueue.cancelAllOperations()
        items.removeAll()
        statusText = ""
    }
    func retryIncomplete() {
        guard !isBusy else { return }
        for index in items.indices {
            if case .failed = items[index].state {
                items[index].state = .waiting
                items[index].failure = nil
                items[index].phase = nil
            }
            if case .cancelled = items[index].state {
                items[index].state = .waiting
                items[index].failure = nil
                items[index].phase = nil
            }
        }
    }

    func start() {
        guard !isBusy else { return }
        guard let binary = locateFFmpeg() else { showFFmpegSetup = true; return }
        guard locateFFprobe(for: binary) != nil else {
            statusText = L10n.text("未检测到 ffprobe，请安装完整的 FFmpeg 后重试。")
            showFFmpegSetup = true
            return
        }
        let pendingIDs = items.compactMap { if case .waiting = $0.state { return $0.id }; return nil }
        guard !pendingIDs.isEmpty else { return }
        ffmpegURL = binary; cancellationRequested = false; isVerifyingMerge = false; queueIDs = Set(pendingIDs); isRunning = true; overallProgress = 0
        // Thumbnail extraction is useful for review, but it decodes video and
        // competes with FFmpeg for CPU, I/O, and hardware-decoder resources.
        presentationQueue.isSuspended = true
        Task { await convertQueue(ids: pendingIDs) }
    }

    /// Merges every waiting item in queue order. No stream is re-encoded: any
    /// mismatch is reported instead of silently producing a lower-quality file.
    func mergeWaitingItems() {
        guard canMerge else { return }
        guard let binary = locateFFmpeg() else { showFFmpegSetup = true; return }
        let sources = items.compactMap { item -> URL? in if case .waiting = item.state, item.trimRange == nil, item.rotation == nil, item.crop == nil, item.aspectRatio == nil, item.imageAdjustment.isIdentity { return item.source }; return nil }
        mergeItemIDs = items.compactMap { item -> UUID? in if case .waiting = item.state, item.trimRange == nil, item.rotation == nil, item.crop == nil, item.aspectRatio == nil, item.imageAdjustment.isIdentity { return item.id }; return nil }
        for index in items.indices where mergeItemIDs.contains(items[index].id) { items[index].state = .merging(nil) }
        cancellationRequested = false
        isVerifyingMerge = false
        presentationQueue.isSuspended = true
        isMerging = true
        mergeProgress = nil
        mergeOutput = nil
        statusText = L10n.format("正在检查 %d 个片段是否可无损合并", sources.count)
        Task { await merge(sources: sources, ffmpegURL: binary) }
    }

    /// Begins the user-confirmed fallback when lossless stream concatenation is
    /// impossible. It normalizes every source to one H.264/AAC MP4 timeline.
    func startCompatibleMerge() {
        guard !isBusy, compatibleMergeIDs.count >= 2, let binary = locateFFmpeg() else {
            if locateFFmpeg() == nil { showFFmpegSetup = true }
            return
        }
        let candidates = items.filter { item in
            guard compatibleMergeIDs.contains(item.id), item.trimRange == nil, item.rotation == nil, item.crop == nil, item.aspectRatio == nil, item.imageAdjustment.isIdentity else { return false }
            if case .waiting = item.state { return true }
            return false
        }
        guard candidates.count >= 2 else { return }
        cancellationRequested = false
        isVerifyingMerge = false
        presentationQueue.isSuspended = true
        mergeItemIDs = candidates.map(\.id)
        for index in items.indices where mergeItemIDs.contains(items[index].id) { items[index].state = .merging(nil) }
        isCompatibleMerging = true
        isMerging = true
        mergeProgress = nil
        mergeOutput = nil
        statusText = L10n.format("正在兼容合并 %d 个片段（重新编码）", candidates.count)
        Task { await mergeCompatible(sources: candidates.map(\.source), ffmpegURL: binary) }
    }

    func cancelCompatibleMerge() {
        compatibleMergeIDs.removeAll()
    }

    func copyFFmpegInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
    }

    func openHomebrewWebsite() {
        guard let url = URL(string: "https://brew.sh/zh-cn/") else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ item: ConversionItem) {
        if case .complete(let output) = item.state {
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([item.source])
        }
    }

    /// Only the process currently owned by FFmpeg is immutable. Waiting rows
    /// have not started yet, so removing them simply makes their worker skip the
    /// identifier. Completed rows are likewise safe to remove independently.
    func remove(_ item: ConversionItem) {
        guard canRemove(item) else { return }
        items.removeAll { $0.id == item.id }
        queueIDs.remove(item.id)
        if isRunning { refreshProgress(queueIDs.count) }
    }

    func canRemove(_ item: ConversionItem) -> Bool {
        if case .running = item.state { return false }
        if case .merging = item.state { return false }
        return true
    }

    func cancel() {
        guard isBusy else { return }
        cancellationRequested = true
        statusText = L10n.text("正在停止转换并清理临时文件")
        activeProcesses.values.forEach { $0.cancel() }
    }

    func revealMergeOutput() {
        guard let mergeOutput else { return }
        NSWorkspace.shared.activateFileViewerSelecting([mergeOutput])
    }

    func scheduleTrim(_ item: ConversionItem, start: Double, end: Double) {
        guard start.isFinite, end.isFinite, start >= 0, end > start else { return }
        scheduleEdit(item) { $0.trimRange = ClipRange(start: start, end: end) }
    }

    func scheduleRotation(_ item: ConversionItem, rotation: VideoRotation?) {
        scheduleEdit(item) { $0.rotation = rotation }
    }

    func scheduleCrop(_ item: ConversionItem, crop: CropRect?) {
        scheduleEdit(item) { $0.crop = crop }
    }

    func scheduleGeometry(_ item: ConversionItem, crop: CropRect?, aspectRatio: DisplayAspectRatio?) {
        scheduleEdit(item) { $0.crop = crop; $0.aspectRatio = aspectRatio }
    }

    func scheduleFrameEdits(_ item: ConversionItem, crop: CropRect?, aspectRatio: DisplayAspectRatio?, imageAdjustment: ImageAdjustment) {
        scheduleEdit(item) { $0.crop = crop; $0.aspectRatio = aspectRatio; $0.imageAdjustment = imageAdjustment }
    }

    /// Editing a finished or failed row creates new work from the original
    /// source. Keep the existing output on disk and discard only stale results.
    /// Confirming unchanged settings must not unnecessarily requeue a video.
    private func scheduleEdit(_ item: ConversionItem, update: (inout ConversionItem) -> Void) {
        guard !isBusy, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = items[index]
        var edited = previous
        update(&edited)
        guard edited.trimRange != previous.trimRange || edited.rotation != previous.rotation || edited.crop != previous.crop || edited.aspectRatio != previous.aspectRatio || edited.imageAdjustment != previous.imageAdjustment else { return }
        edited.state = .waiting
        edited.phase = nil
        edited.failure = nil
        edited.mediaHandling = nil
        items[index] = edited
    }

    private func add(_ urls: [URL]) {
        var knownSources = Set(items.map { canonicalURL($0.source) })
        let additions = urls.compactMap { rawURL -> ConversionItem? in
            let source = canonicalURL(rawURL)
            guard !source.hasDirectoryPath, knownSources.insert(source).inserted else { return nil }
            return ConversionItem(source: source)
        }
        items.append(contentsOf: additions)
        for item in additions { loadPresentation(for: item) }
    }

    private func loadPresentation(for item: ConversionItem) {
        presentationQueue.addOperation { [weak self] in
            // Keep the queue's bounded concurrency while loading modern
            // AVFoundation properties asynchronously.
            let completed = DispatchSemaphore(value: 0)
            Task { [weak self] in
                defer { completed.signal() }
                guard await MainActor.run(body: { [weak self] in
                    self?.items.contains(where: { $0.id == item.id }) == true
                }) else { return }
                let presentation = await VideoPresentation.load(from: item.source)
                await MainActor.run { [weak self] in
                    guard let store = self,
                          let index = store.items.firstIndex(where: { $0.id == item.id }) else { return }
                    store.items[index].presentation = presentation
                    store.reconcileSmartEnhanceTarget()
                }
            }
            completed.wait()
        }
    }

    private func merge(sources: [URL], ffmpegURL: URL) async {
        // The concat demuxer reads a line-oriented manifest. A newline in a
        // filename would change that manifest's structure, so reject it rather
        // than attempting to quote an ambiguous path.
        guard sources.allSatisfy({ !$0.path.contains("\n") && !$0.path.contains("\r") }) else {
            finishMerge(message: L10n.text("无损合并不支持文件名中的换行符。"), output: nil)
            return
        }
        var infos: [VideoInfo] = []
        for source in sources {
            guard !cancellationRequested else { break }
            infos.append(await probe(source, ffmpegURL: ffmpegURL))
        }
        guard !cancellationRequested else {
            finishMerge(message: L10n.text("合并已取消。"), output: nil)
            return
        }
        guard infos.allSatisfy({ $0.canDirectRemuxToMP4 }),
              let signature = infos.first?.mergeSignature,
              infos.dropFirst().allSatisfy({ $0.mergeSignature == signature }) else {
            offerCompatibleMerge()
            return
        }
        mergeDurations = infos.map(\.duration)
        updateMergeProgress(seconds: 0)

        let output = uniqueMergeOutput(for: sources[0])
        // Write beside the intended result, then publish with a move. This
        // keeps incomplete media out of the user's output list and avoids
        // overwriting a file that appears after the unique-name check.
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".MP4Flow-\(UUID().uuidString).partial.mp4")
        let listURL = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-concat-\(UUID().uuidString).txt")
        do {
            let list = sources.map { "file '\($0.path.replacingOccurrences(of: "'", with: "\\\\'"))'" }.joined(separator: "\n") + "\n"
            try list.write(to: listURL, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            finishMerge(message: L10n.format("无法创建合并清单：%@", error.localizedDescription), output: nil)
            return
        }

        var result = await runMergeFFmpeg(ffmpegURL: ffmpegURL, listURL: listURL, info: infos[0], output: temporary)
        try? FileManager.default.removeItem(at: listURL)
        if case .success = result, !cancellationRequested {
            isVerifyingMerge = true
            statusText = L10n.text("正在验证输出")
            if let failure = await verifyOutput(temporary, ffmpegURL: ffmpegURL) {
                result = .failure(failure.legacyMessage)
            }
        }
        if cancellationRequested { result = .cancelled }
        switch result {
        case .success:
            do {
                try FileManager.default.moveItem(at: temporary, to: output)
                finishMerge(message: L10n.format("已无损合并 %d 个片段：%@", sources.count, output.lastPathComponent), output: output)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                finishMerge(message: L10n.format("无法无损合并：%@", error.localizedDescription), output: nil)
            }
        case .failure(let message), .retryableFailure(let message, _):
            try? FileManager.default.removeItem(at: temporary)
            let displayMessage = message.hasPrefix("MP4Flow:") ? Self.failure(from: message).legacyMessage : message
            finishMerge(message: L10n.format("无法无损合并：%@", displayMessage), output: nil)
        case .cancelled:
            try? FileManager.default.removeItem(at: temporary)
            finishMerge(message: L10n.text("合并已取消。"), output: nil)
        }
    }

    private func finishMerge(message: String, output: URL?) {
        let completedMode = isCompatibleMerging ? L10n.text("兼容合并") : L10n.text("无损合并")
        for index in items.indices {
            if case .merging = items[index].state { items[index].state = .waiting }
        }
        isMerging = false
        isVerifyingMerge = false
        mergeNotice = message
        mergeOutput = output
        mergeProgress = nil
        mergeItemIDs.removeAll()
        mergeDurations.removeAll()
        mergeProgressBuffer = ""
        mergeProgressTime = nil
        mergeProgressGeneration = nil
        compatibleMergeIDs.removeAll()
        isCompatibleMerging = false
        presentationQueue.isSuspended = false
        statusText = output == nil ? L10n.format("%@未完成", completedMode) : L10n.format("%@完成", completedMode)
        showMergeNotice = true
    }

    private func offerCompatibleMerge() {
        for index in items.indices where mergeItemIDs.contains(items[index].id) { items[index].state = .waiting }
        compatibleMergeIDs = mergeItemIDs
        mergeItemIDs.removeAll()
        mergeDurations.removeAll()
        mergeProgress = nil
        mergeProgressBuffer = ""
        mergeProgressTime = nil
        mergeProgressGeneration = nil
        isMerging = false
        isVerifyingMerge = false
        presentationQueue.isSuspended = false
        statusText = L10n.text("请先统一规格转码，再合并；也可使用兼容合并。")
        showCompatibleMergePrompt = true
    }

    private func runMergeFFmpeg(ffmpegURL: URL, listURL: URL, info: VideoInfo, output: URL) async -> ProcessResult {
        await runMergeProcess(
            ffmpegURL: ffmpegURL,
            arguments: ["-hide_banner", "-nostdin", "-y", "-f", "concat", "-safe", "0", "-i", listURL.path, "-map", "0:\(info.videoStreamSpecifier)", "-map", "0:a:0?", "-map_metadata", "-1", "-map_chapters", "-1", "-c", "copy", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path],
            usesHardwareEncoder: false
        )
    }

    private func mergeCompatible(sources: [URL], ffmpegURL: URL) async {
        var infos: [VideoInfo] = []
        for source in sources {
            guard !cancellationRequested else { break }
            infos.append(await probe(source, ffmpegURL: ffmpegURL))
        }
        guard !cancellationRequested else {
            finishMerge(message: L10n.text("兼容合并已取消。"), output: nil)
            return
        }
        guard infos.allSatisfy(\.hasVideo) else {
            finishMerge(message: L10n.text("兼容合并失败：存在无法读取的视频流。"), output: nil)
            return
        }
        let target = compatibleMergeTarget(infos)
        mergeDurations = infos.map(\.duration)
        updateMergeProgress(seconds: 0)
        let output = uniqueMergeOutput(for: sources[0])
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".MP4Flow-\(UUID().uuidString).partial.mp4")
        statusText = L10n.format("正在兼容合并 %d 个片段 · 统一为 %@", sources.count, target.summary)
        var result = await runCompatibleMergeFFmpeg(ffmpegURL: ffmpegURL, sources: sources, infos: infos, target: target, output: temporary)
        // Compatible Merge intentionally normalizes every clip through a CPU
        // filter graph. The encoder can still be hardware accelerated; when a
        // VideoToolbox session cannot be created, retry once with libx264 and
        // the exact same target size, rate limits, and AAC settings.
        if case .retryableFailure(_, .softwareEncoder) = result, !cancellationRequested {
            statusText = L10n.text("硬件编码不可用，正在使用兼容编码重试")
            resetCompatibleMergeProgress()
            result = await runCompatibleMergeFFmpeg(ffmpegURL: ffmpegURL, sources: sources, infos: infos, target: target, output: temporary, preferHardwareEncoder: false)
        }
        if case .success = result, !cancellationRequested {
            isVerifyingMerge = true
            statusText = L10n.text("正在验证输出")
            if let failure = await verifyOutput(temporary, ffmpegURL: ffmpegURL) {
                result = .failure(failure.legacyMessage)
            }
        }
        if cancellationRequested { result = .cancelled }
        switch result {
        case .success:
            do {
                try FileManager.default.moveItem(at: temporary, to: output)
                finishMerge(message: L10n.format("已兼容合并 %d 个片段（统一为 %@）：%@", sources.count, target.summary, output.lastPathComponent), output: output)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                finishMerge(message: L10n.format("兼容合并失败：%@", error.localizedDescription), output: nil)
            }
        case .failure(let message), .retryableFailure(let message, _):
            try? FileManager.default.removeItem(at: temporary)
            let displayMessage = message.hasPrefix("MP4Flow:") ? Self.failure(from: message).legacyMessage : message
            finishMerge(message: L10n.format("兼容合并失败：%@", displayMessage), output: nil)
        case .cancelled:
            try? FileManager.default.removeItem(at: temporary)
            finishMerge(message: L10n.text("兼容合并已取消。"), output: nil)
        }
    }

    private func resetCompatibleMergeProgress() {
        mergeProgressBuffer = ""
        mergeProgressTime = 0
        updateMergeProgress(seconds: 0)
    }

    private func runCompatibleMergeFFmpeg(ffmpegURL: URL, sources: [URL], infos: [VideoInfo], target: CompatibleMergeTarget, output: URL, preferHardwareEncoder: Bool = true) async -> ProcessResult {
        await runMergeProcess(
            ffmpegURL: ffmpegURL,
            arguments: compatibleMergeArguments(sources: sources, infos: infos, target: target, output: output, preferHardwareEncoder: preferHardwareEncoder),
            usesHardwareEncoder: preferHardwareEncoder
        )
    }

    private func runMergeProcess(ffmpegURL: URL, arguments: [String], usesHardwareEncoder: Bool) async -> ProcessResult {
        guard !cancellationRequested else { return .cancelled }
        let id = UUID(), generation = UUID()
        let runner = FFmpegProcessRunner(executable: ffmpegURL, arguments: arguments, configuration: processConfiguration)
        activeProcesses[id] = runner
        mergeProgressGeneration = generation
        defer {
            activeProcesses.removeValue(forKey: id)
            if mergeProgressGeneration == generation { mergeProgressGeneration = nil }
        }
        let result = await runner.run { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self, self.isMerging, !self.cancellationRequested,
                      self.mergeProgressGeneration == generation else { return }
                self.consumeMergeProgress(String(decoding: data, as: UTF8.self))
            }
        }
        if cancellationRequested || result.wasCancelled { return .cancelled }
        if result.timedOut { return .failure("MP4Flow:stalled") }
        if result.launchError != nil { return .failure("MP4Flow:launch-failed") }
        if result.succeeded { return .success }
        let message = friendlyMergeError(result.standardError)
        if let hint = FFmpegHardwareRetryClassifier.hint(stderr: result.standardError, usedHardwarePipeline: false, usedHardwareEncoder: usesHardwareEncoder) {
            return .retryableFailure(message, hint)
        }
        return .failure(message)
    }

    /// Normalize to the largest displayed square-pixel frame rather than to the first file in
    /// queue. Smaller clips are scaled up proportionally; differing aspect
    /// ratios are centered on a black canvas, never stretched or cropped.
    private func compatibleMergeTarget(_ infos: [VideoInfo]) -> CompatibleMergeTarget {
        let displayed = infos.map { info -> (info: VideoInfo, width: Int, height: Int) in
            let width = info.width ?? 1920, height = info.height ?? 1080
            let scaledWidth = Double(width) * info.mergePixelAspectRatio
            let normalizedWidth = scaledWidth.isFinite && scaledWidth >= 2 && scaledWidth < Double(Int.max)
                ? even(Int(scaledWidth)) : even(width)
            let geometry = VideoGeometry.displayed(width: normalizedWidth, height: height, sampleAspectRatio: "1:1", rotation: info.displayRotation)
            return (info, even(geometry?.width ?? normalizedWidth), even(geometry?.height ?? height))
        }
        // Keep tuple comparison simple enough for the older Swift toolchain
        // used by CI; area is calculated in Double to avoid Int overflow.
        let largest = displayed.max { left, right in
            let leftArea = Double(left.width) * Double(left.height)
            let rightArea = Double(right.width) * Double(right.height)
            return leftArea < rightArea
        }!
        return CompatibleMergeTarget(
            width: largest.width,
            height: largest.height,
            frameRate: largest.info.frameRate ?? "30"
        )
    }

    private func compatibleMergeArguments(sources: [URL], infos: [VideoInfo], target: CompatibleMergeTarget, output: URL, preferHardwareEncoder: Bool) -> [String] {
        var args = ["-hide_banner", "-nostdin", "-y"]
        for source in sources { args += ["-i", source.path] }

        var filters: [String] = []
        for (index, info) in infos.enumerated() {
            // Fit/pad works in encoded pixels. Normalize each autorotated
            // input's pixel aspect ratio first so setsar=1 cannot stretch it.
            // The explicit scale expression also works with older FFmpeg.
            filters.append("[\(index):\(info.videoStreamSpecifier)]scale=w='max(2,trunc(iw*if(gt(sar,0),sar,1)/2)*2)':h=ih,setsar=1,scale=\(target.width):\(target.height):force_original_aspect_ratio=decrease:force_divisible_by=2,pad=\(target.width):\(target.height):(ow-iw)/2:(oh-ih)/2:color=black,fps=\(target.frameRate),setsar=1,format=yuv420p[v\(index)]")
            if info.audioCodec != nil {
                filters.append("[\(index):a:0]aresample=48000,aformat=channel_layouts=stereo[a\(index)]")
            } else {
                let duration = ffmpegTime(max(info.duration ?? 0, 0.01))
                filters.append("anullsrc=r=48000:cl=stereo,atrim=duration=\(duration),asetpts=N/SR/TB[a\(index)]")
            }
        }
        let concatInputs = infos.indices.map { "[v\($0)][a\($0)]" }.joined()
        filters.append("\(concatInputs)concat=n=\(infos.count):v=1:a=1[vout][aout]")
        let videoRate = infos.map(\.fallbackRate).max() ?? 4_000_000
        args += ["-filter_complex", filters.joined(separator: ";"), "-map", "[vout]", "-map", "[aout]", "-map_metadata", "-1", "-map_chapters", "-1"]
        if preferHardwareEncoder {
            args += ["-c:v", "h264_videotoolbox", "-prio_speed", "1"]
        } else {
            args += ["-c:v", "libx264", "-preset", "veryfast"]
        }
        args += ["-b:v", rate(videoRate), "-maxrate", rate(Int(Double(videoRate) * 1.25)), "-bufsize", rate(videoRate * 2), "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
        return args
    }

    private func even(_ value: Int) -> Int { max(2, value - value % 2) }

    private func consumeMergeProgress(_ text: String) {
        let combined = mergeProgressBuffer + text
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        mergeProgressBuffer = combined.hasSuffix("\n") ? "" : String(lines.last ?? "")
        for line in (combined.hasSuffix("\n") ? lines : lines.dropLast()) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "out_time_us", "out_time_ms":
                if let value = Double(parts[1]) { mergeProgressTime = value / 1_000_000 }
            case "out_time":
                if let seconds = parseTimestamp(String(parts[1])) { mergeProgressTime = seconds }
            case "progress":
                if let seconds = mergeProgressTime { updateMergeProgress(seconds: seconds) }
            default: continue
            }
        }
    }

    private func updateMergeProgress(seconds: Double) {
        let knownDurations = mergeDurations.compactMap { $0 }
        guard knownDurations.count == mergeDurations.count else {
            mergeProgress = nil
            return
        }
        let total = knownDurations.reduce(0, +)
        guard total > 0 else { mergeProgress = nil; return }
        let clampedSeconds = min(max(seconds, 0), total)
        // FFmpeg finishing its packets is not publication. Keep the final
        // fraction reserved for validation and the atomic output move.
        mergeProgress = min(clampedSeconds / total, 0.999)
        var elapsed = 0.0
        for (offset, id) in mergeItemIDs.enumerated() {
            guard let index = items.firstIndex(where: { $0.id == id }), let duration = mergeDurations[offset] else { continue }
            let localProgress = (clampedSeconds - elapsed) / duration
            let displayedProgress: Double? = localProgress < 0 ? nil : min(max(localProgress, 0), 0.999)
            items[index].state = .merging(displayedProgress)
            elapsed += duration
        }
    }

    private func convertQueue(ids: [UUID]) async {
        guard let binary = ffmpegURL, !ids.isEmpty else { isRunning = false; return }
        let options = (preset, quality, outputResolution, smartEnhanceTarget)
        for id in ids {
            guard shouldContinue else { break }
            await convert(id: id, ffmpegURL: binary, preset: options.0, quality: options.1, resolution: options.2, smartEnhanceTarget: options.3, count: ids.count)
        }
        if cancellationRequested {
            for index in items.indices where queueIDs.contains(items[index].id) {
                if case .waiting = items[index].state {
                    items[index].state = .cancelled
                    items[index].phase = nil
                }
            }
            statusText = L10n.text("转换已取消；可重新排队未完成项目。")
        } else {
            overallProgress = 1
            let failures = items.filter { item in
                guard queueIDs.contains(item.id) else { return false }
                if case .failed = item.state { return true }
                return false
            }.count
            statusText = failures == 0 ? L10n.text("转换完成") : L10n.format("队列处理结束，%d 项失败。", failures)
        }
        activeProcesses.removeAll(); progressBuffers.removeAll(); progressGeneration.removeAll(); progressTimes.removeAll(); lastProgressUpdate.removeAll(); queueIDs.removeAll(); isRunning = false
        presentationQueue.isSuspended = false
    }

    private var shouldContinue: Bool { !cancellationRequested }

    private func convert(id: UUID, ffmpegURL: URL, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, smartEnhanceTarget: SmartEnhanceTarget, count: Int) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let source = item.source
        let trim = item.trimRange
        let rotation = item.rotation
        let crop = item.crop
        let aspectRatio = item.aspectRatio
        let imageAdjustment = item.imageAdjustment
        setPhase(.inspecting, for: id, progress: nil, count: count)
        var info = await probe(source, ffmpegURL: ffmpegURL)
        // A transient file-provider or network-volume read may make ffprobe
        // fail once before the same source is readable. Retry inspection once,
        // without launching an encoder against unknown stream metadata.
        if !info.probeSucceeded && !cancellationRequested && shouldRetryProbe(for: source) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !cancellationRequested { info = await probe(source, ffmpegURL: ffmpegURL) }
        }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !cancellationRequested else {
            items[index].state = .cancelled
            items[index].phase = nil
            return
        }
        guard info.probeSucceeded else {
            markFailed(id, failure: ConversionFailure(
                reasonKey: "无法读取此视频的媒体数据",
                solutionKey: "请确认文件可播放，或使用「智能转换」生成新文件后重试。",
                diagnostic: "probe:unavailable"
            ), count: count)
            return
        }
        guard info.hasVideo else {
            markFailed(id, failure: ConversionFailure(
                reasonKey: "未检测到可用视频流",
                solutionKey: "请确认文件可播放，或重新导出后再试。",
                diagnostic: "probe:no-video"
            ), count: count)
            return
        }
        // A trim should not silently become a full re-encode. When the source
        // streams are safe in MP4, use lossless stream copy regardless of the
        // selected conversion preset. This is the same fast path as “极速直封装”.
        // Unsupported streams fall back to the user's normal hardware/software
        // conversion choice so the output remains a playable MP4.
        let editedGeometry = info.geometry(crop: crop, rotation: rotation)
        let unchangedHeight = editedGeometry?.canSkipUnchangedSize == true ? editedGeometry?.height : nil
        let resizeRequiresEncoding = resolution.requiresReencode(sourceHeight: unchangedHeight)
        // In automatic mode an incompatible audio codec should not force a
        // perfectly compatible video through a full decode/encode cycle.
        // Restrict this route to complete, unedited source timelines.
        let copyVideoAndEncodeAudio = preset == .smartMP4
            && trim == nil && rotation == nil && crop == nil && aspectRatio == nil && imageAdjustment.isIdentity && !resizeRequiresEncoding
            && info.canCopyVideoToMP4 && info.audioCodec != nil && info.audioCodec?.lowercased() != "aac"
        let effectivePreset: ConversionPreset
        if preset == .smartEnhanceUpscale {
            effectivePreset = preset
        } else if rotation != nil || crop != nil || aspectRatio != nil || !imageAdjustment.isIdentity || resizeRequiresEncoding {
            // Edits require re-encoding, but retain an explicitly selected
            // software or HEVC encoder. Only copy/automatic presets need a
            // concrete H.264 encoding path here.
            effectivePreset = (preset == .remux || preset == .smartMP4) ? .h264Hardware : preset
        } else if trim != nil, info.canDirectRemuxToMP4 {
            effectivePreset = .remux
        } else if preset == .smartMP4 {
            effectivePreset = info.canDirectRemuxToMP4 || copyVideoAndEncodeAudio ? .remux : .h264Hardware
        } else {
            effectivePreset = preset
        }
        items[index].failure = nil
        items[index].mediaHandling = Self.mediaHandlingNotice(for: info, preset: effectivePreset)
        setPhase(copyVideoAndEncodeAudio ? .audioTranscoding : phase(for: effectivePreset, preferHardwareEncoder: true), for: id, progress: info.duration == nil ? nil : 0, count: count, detail: copyVideoAndEncodeAudio ? nil : outputSummary(info, preset: effectivePreset, quality: quality, resolution: resolution, sourceHeight: editedGeometry?.height))
        if let aspectRatio, aspectRatio.outputSize(height: resolution.targetHeight ?? editedGeometry?.height ?? 0) == nil {
            markFailed(id, failure: ConversionFailure(reasonKey: "目标比例或尺寸超出支持范围", solutionKey: "请选择较小分辨率或接近原画的比例。", diagnostic: "geometry:unsupported-size"), count: count)
            return
        }
        guard imageAdjustment.isIdentity || !info.isHDR else {
            markFailed(id, failure: ConversionFailure(reasonKey: "HDR 视频暂不支持画面调整", solutionKey: "请先导出 SDR 视频，再调整亮度。", diagnostic: "adjustment:hdr"), count: count)
            return
        }
        let final = uniqueOutput(for: source, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment)
        let temporary = final.deletingLastPathComponent().appendingPathComponent(".MP4Flow-\(UUID().uuidString).partial.mp4")
        // The worker owns only its partial file; a successful move leaves the
        // published output untouched, while every early return also cleans up.
        defer { try? FileManager.default.removeItem(at: temporary) }
        var result: ProcessResult
        if effectivePreset == .smartEnhanceUpscale {
            guard rotation == nil, crop == nil, aspectRatio == nil, imageAdjustment.isIdentity else {
                markFailed(id, failure: ConversionFailure(
                    reasonKey: "智能增强不支持画面编辑",
                    solutionKey: "请先完成画面编辑，再添加新文件增强。",
                    diagnostic: "enhance:unsupported-edit"
                ), count: count)
                return
            }
            guard #available(macOS 27.0, *), let plan = SmartEnhancePlan.make(info: info, target: smartEnhanceTarget) else {
                markFailed(id, failure: ConversionFailure(
                    reasonKey: "此视频暂不支持智能增强",
                    solutionKey: "请使用「智能转换」先转换为新文件，然后添加新文件重试。",
                    diagnostic: "enhance:unsupported-source"
                ), count: count)
                return
            }
            setPhase(.hardwareTranscoding, for: id, progress: info.duration == nil ? nil : 0, count: count, detail: L10n.format("智能增强放大至 %@", plan.outputSummary))
            statusText = L10n.format("智能增强放大至 %@", plan.outputSummary)
            result = await runSmartEnhance(source: source, output: temporary, info: info, plan: plan, trim: trim, quality: quality, id: id, count: count)
        } else {
            result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment, id: id, count: count, copyVideoAndEncodeAudio: copyVideoAndEncodeAudio)
        }
        // Keep the fast VideoToolbox path as the default. Retry only when the
        // stderr allowlist identifies a specific VideoToolbox component: a
        // decoder/filter failure gets one CPU-pipeline attempt, while an
        // encoder failure goes directly to libx264. Generic media, mux, I/O,
        // and timeout failures never replay the whole video automatically.
        if case .retryableFailure(_, .cpuDecodeAndFilter) = result,
           !cancellationRequested,
           effectivePreset != .smartEnhanceUpscale {
            setPhase(.softwareTranscoding, for: id, progress: nil, count: count, detail: L10n.text("硬件处理失败，正在使用兼容方式重试"))
            result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment, id: id, count: count, preferHardwarePipeline: false)
        }
        if case .retryableFailure(_, .softwareEncoder) = result,
           !cancellationRequested,
           effectivePreset != .smartEnhanceUpscale,
           usesVideoToolboxEncoder(effectivePreset) {
            setPhase(.softwareTranscoding, for: id, progress: nil, count: count, detail: L10n.text("硬件编码不可用，正在使用兼容编码重试"))
            result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment, id: id, count: count, preferHardwarePipeline: false, preferHardwareEncoder: false)
        }
        if case .success = result, !cancellationRequested {
            setPhase(.verifying, for: id, progress: 0.999, count: count)
            if let verificationFailure = await verifyOutput(temporary, ffmpegURL: ffmpegURL, expectedAspectRatio: aspectRatio?.value ?? info.displayAspectRatio(crop: crop, rotation: rotation), requiresSquarePixels: aspectRatio != nil) {
                result = .failure(verificationFailure.reason)
                if let current = items.firstIndex(where: { $0.id == id }) {
                    items[current].failure = verificationFailure
                }
            }
        }
        // Cancellation can arrive after FFmpeg exits or while ffprobe verifies
        // the temporary result. Never publish an unchecked output in that gap.
        if cancellationRequested { result = .cancelled }
        guard let current = items.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .success:
            do {
                try FileManager.default.moveItem(at: temporary, to: final)
                items[current].state = .complete(final)
                items[current].phase = nil
            } catch {
                markFailed(id, failure: ConversionFailure(
                    reasonKey: "无法保存输出文件",
                    solutionKey: "请检查输出文件夹权限和可用空间后重试。",
                    diagnostic: "publish:\(error._code)"
                ), count: count)
            }
        case .cancelled:
            items[current].state = .cancelled
            items[current].phase = nil
            items[current].failure = nil
        case .failure(let message), .retryableFailure(let message, _):
            let existingFailure = items[current].failure
            markFailed(id, failure: existingFailure ?? Self.failure(from: message), count: count)
        }
        refreshProgress(count)
    }

    private enum ProcessResult {
        case success, cancelled, failure(String), retryableFailure(String, FFmpegHardwareRetryHint)
    }

    private func shouldRetryProbe(for source: URL) -> Bool {
        guard let values = try? source.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsLocalKey]) else { return false }
        return values.isUbiquitousItem == true || values.volumeIsLocal == false
    }

    private func setPhase(_ phase: ConversionPhase, for id: UUID, progress: Double?, count: Int, detail: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].phase = phase
        items[index].state = .running(progress)
        let phaseText = phase.title
        statusText = detail.map { "\(phaseText) · \($0)" } ?? phaseText
        refreshProgress(count)
    }

    private func phase(for preset: ConversionPreset, preferHardwareEncoder: Bool) -> ConversionPhase {
        if preset == .remux { return .directRemux }
        if preset == .h264Software || !preferHardwareEncoder { return .softwareTranscoding }
        return .hardwareTranscoding
    }

    private func markFailed(_ id: UUID, failure: ConversionFailure, count: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].failure = failure
        items[index].phase = nil
        items[index].state = .failed(failure.legacyMessage)
        refreshProgress(count)
    }

    /// Queue notices describe changes to this material, not the default policy.
    /// Ordinary files need no disclaimer; policy remains in Help/Environment.
    nonisolated static func mediaHandlingNotice(for info: VideoInfo, preset: ConversionPreset) -> MediaHandlingNotice? {
        guard info.probeSucceeded, info.hasVideo, info.videoTrackCount > 0 else {
            return MediaHandlingNotice(issues: [.unconfirmed])
        }
        var issues: [MediaHandlingNotice.Issue] = []
        if info.videoTrackCount > 1 {
            issues.append(.extraVideo(info.videoTrackCount))
        }
        if info.audioTrackCount > 1 {
            issues.append(.extraAudio(info.audioTrackCount))
        }
        if info.subtitleTrackCount > 0 {
            issues.append(.subtitles(info.subtitleTrackCount))
        }
        if info.chapterCount > 0 {
            issues.append(.chapters(info.chapterCount))
        }
        if info.isHDR, preset != .remux {
            issues.append(.hdrReencoding)
        }
        if preset != .remux, let angle = info.displayRotation, angle.isFinite,
           abs(angle / 90 - (angle / 90).rounded()) > 0.0001 {
            issues.append(.nonstandardRotation)
        }
        return issues.isEmpty ? nil : MediaHandlingNotice(issues: issues)
    }

    nonisolated static func failure(from message: String) -> ConversionFailure {
        if message == "MP4Flow:aspect-mismatch" {
            return ConversionFailure(reasonKey: "输出画面比例异常", solutionKey: "请使用「最稳妥转换」重试，或检查比例设置。", diagnostic: "MP4Flow:aspect-mismatch")
        }
        if message == "MP4Flow:stalled" {
            return ConversionFailure(
                reasonKey: "转换长时间无进度，已安全停止",
                solutionKey: "请确认视频可播放、磁盘可用后重试；仍失败请使用「最稳妥转换」。",
                diagnostic: "ffmpeg:stalled"
            )
        }
        if message == "MP4Flow:hardware-encoder" {
            return ConversionFailure(
                reasonKey: "硬件编码不可用",
                solutionKey: "请重试；仍失败请使用「最稳妥转换」。",
                diagnostic: "ffmpeg:hardware-encoder"
            )
        }
        if message == "MP4Flow:software-encoder" {
            return ConversionFailure(
                reasonKey: "软件编码器不可用",
                solutionKey: "请更新或重新安装 FFmpeg，或改用「智能转换」后重试。",
                diagnostic: "ffmpeg:software-encoder"
            )
        }
        if message == "MP4Flow:unreadable-media" {
            return ConversionFailure(
                reasonKey: "无法读取此视频的媒体数据",
                solutionKey: "请确认文件可播放，或使用「智能转换」生成新文件后重试。",
                diagnostic: "ffmpeg:unreadable-media"
            )
        }
        if message == "MP4Flow:container-incompatible" {
            return ConversionFailure(
                reasonKey: "此视频流无法直接写入 MP4",
                solutionKey: "请使用「智能转换」重新编码后重试；仍失败请使用「最稳妥转换」。",
                diagnostic: "ffmpeg:container-incompatible"
            )
        }
        if message == "MP4Flow:launch-failed" {
            return ConversionFailure(
                reasonKey: "无法启动转换工具",
                solutionKey: "请在「环境体检」检查 FFmpeg，修复安装或权限后重试。",
                diagnostic: "ffmpeg:launch-failed"
            )
        }
        if message == "MP4Flow:disk-full" {
            return ConversionFailure(reasonKey: "输出磁盘空间不足", solutionKey: "请释放空间或选择其他输出位置后重试。", diagnostic: "ffmpeg:disk-full")
        }
        if message == "MP4Flow:missing-source" {
            return ConversionFailure(reasonKey: "源文件已移动、删除或无法访问", solutionKey: "请在访达中确认源文件仍存在，重新添加后再试。", diagnostic: "ffmpeg:missing-source")
        }
        if message == "MP4Flow:permission" {
            return ConversionFailure(reasonKey: "没有读取或写入文件的权限", solutionKey: "请检查文件和输出文件夹权限后重试。", diagnostic: "ffmpeg:permission")
        }
        let text = message.lowercased()
        if text.contains("无进度") || text.contains("未响应") || text.contains("timed out") || text.contains("timeout") {
            return ConversionFailure(
                reasonKey: "转换长时间无进度，已安全停止",
                solutionKey: "请确认视频可播放、磁盘可用后重试；仍失败请使用「最稳妥转换」。",
                diagnostic: "ffmpeg:stalled"
            )
        }
        if text.contains("no space left") || text.contains("disk full") {
            return ConversionFailure(
                reasonKey: "输出磁盘空间不足",
                solutionKey: "请释放空间或选择其他输出位置后重试。",
                diagnostic: "ffmpeg:disk-full"
            )
        }
        if text.contains("permission denied") || text.contains("operation not permitted") {
            return ConversionFailure(
                reasonKey: "没有读取或写入文件的权限",
                solutionKey: "请检查文件和输出文件夹权限后重试。",
                diagnostic: "ffmpeg:permission"
            )
        }
        if text.contains("unknown encoder") || text.contains("videotoolbox") {
            return ConversionFailure(
                reasonKey: "硬件编码不可用",
                solutionKey: "请重试；仍失败请使用「最稳妥转换」。",
                diagnostic: "ffmpeg:hardware-encoder"
            )
        }
        if text.contains("invalid data") || text.contains("moov atom") || text.contains("could not find codec") {
            return ConversionFailure(
                reasonKey: "无法读取此视频的媒体数据",
                solutionKey: "请确认文件可播放，或使用「智能转换」生成新文件后重试。",
                diagnostic: "ffmpeg:unreadable-media"
            )
        }
        return ConversionFailure(
            reasonKey: "转换未完成",
            solutionKey: "请重试；仍失败请使用「最稳妥转换」。",
            diagnostic: "ffmpeg:failed"
        )
    }

    /// Validate the temporary result before atomically publishing it. This is
    /// deliberately metadata-only: it catches a zero-byte/truncated output
    /// without decoding a long video for a second time.
    private func verifyOutput(_ output: URL, ffmpegURL: URL, expectedAspectRatio: Double? = nil, requiresSquarePixels: Bool = false) async -> ConversionFailure? {
        guard let values = try? output.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size > 0 else {
            return ConversionFailure(
                reasonKey: "输出文件为空或未写完整",
                solutionKey: "请检查磁盘空间后重试。",
                diagnostic: "verify:empty-output"
            )
        }
        guard locateFFprobe(for: ffmpegURL) != nil else {
            return ConversionFailure(
                reasonKey: "FFprobe 不可用，无法验证输出",
                solutionKey: "请在「环境体检」修复 FFprobe 后重新转换。",
                diagnostic: "verify:ffprobe-unavailable"
            )
        }
        var info = await probe(output, ffmpegURL: ffmpegURL)
        if !info.probeSucceeded && !cancellationRequested {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !cancellationRequested { info = await probe(output, ffmpegURL: ffmpegURL) }
        }
        guard info.probeSucceeded else {
            return ConversionFailure(
                reasonKey: "输出文件未通过媒体检查",
                solutionKey: "请重新转换；仍失败请在「环境体检」检查 FFprobe，并确认磁盘可用。",
                diagnostic: "verify:unreadable-output"
            )
        }
        guard info.hasVideo, (info.width ?? 0) > 0, (info.height ?? 0) > 0 else {
            return ConversionFailure(
                reasonKey: "输出文件缺少视频流",
                solutionKey: "请使用「最稳妥转换」重试。",
                diagnostic: "verify:no-video-stream"
            )
        }
        if let expectedAspectRatio, let actual = info.displayAspectRatio() {
            let tolerance = max(0.01, 2 / Double(min(info.width ?? 2, info.height ?? 2)))
            if abs(actual / expectedAspectRatio - 1) > tolerance || (requiresSquarePixels && abs(AspectGeometry.pixelRatio(info.sampleAspectRatio) - 1) > 0.0001) {
                return Self.failure(from: "MP4Flow:aspect-mismatch")
            }
        }
        return nil
    }

    private func runSmartEnhance(source: URL, output: URL, info: VideoInfo, plan: SmartEnhancePlan, trim: ClipRange?, quality: ConversionQuality, id: UUID, count: Int) async -> ProcessResult {
        guard #available(macOS 27.0, *) else {
            return .failure(L10n.text("智能增强放大需要 macOS 27 或更高版本。"))
        }
        do {
            let exporter = SmartEnhanceExporter()
            try await exporter.export(
                source: source,
                output: output,
                plan: plan,
                trim: trim,
                videoBitRate: info.outputRate(preset: .smartEnhanceUpscale, quality: quality, resolution: .original),
                videoTrackID: info.selectedVideoTrackID,
                shouldCancel: { [weak self] in self?.cancellationRequested ?? true },
                onProgress: { [weak self] seconds in
                    guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                    let duration = trim.map { $0.end - $0.start } ?? info.duration
                    guard let duration, duration > 0 else { return }
                    let progress = min(max(seconds / duration, 0), 0.999)
                    self.items[index].state = .running(progress)
                    self.refreshProgress(count)
                }
            )
            return cancellationRequested ? .cancelled : .success
        } catch is CancellationError {
            return .cancelled
        } catch {
#if compiler(>=6.4)
            if let exportError = error as? SmartEnhanceExporter.ExportError {
                let failure = Self.enhancementFailure(for: exportError)
                if let index = items.firstIndex(where: { $0.id == id }) { items[index].failure = failure }
                return .failure(failure.reason)
            }
#endif
            return .failure(L10n.format("智能增强放大失败：%@", error.localizedDescription))
        }
    }

#if compiler(>=6.4)
    /// Classify framework failures before localization; associated framework
    /// messages can contain source paths and must not become public reports.
    @available(macOS 27.0, *)
    nonisolated static func enhancementFailure(for error: SmartEnhanceExporter.ExportError) -> ConversionFailure {
        switch error {
        case .unavailable:
            return ConversionFailure(reasonKey: "此 Mac 不支持智能增强放大。", solutionKey: "请改用「智能转换」；智能增强需要受支持的 Apple 芯片与 macOS 27+。", diagnostic: "enhance:unavailable")
        case .invalidSource, .reader:
            return ConversionFailure(reasonKey: "无法读取用于智能增强的视频。", solutionKey: "请使用「智能转换」先转换为新文件，然后添加新文件重试。", diagnostic: "enhance:unreadable-source")
        case .writer:
            return ConversionFailure(reasonKey: "无法写入智能增强输出文件。", solutionKey: "请检查剩余空间和输出文件夹权限，或改用本地文件夹后重试。", diagnostic: "enhance:write-failed")
        case .pixelBuffer:
            return ConversionFailure(reasonKey: "无法准备智能增强的视频帧。", solutionKey: "请降低增强目标分辨率，关闭其他视频任务后重试。", diagnostic: "enhance:frame-resources")
        case .pixelTransfer:
            return ConversionFailure(reasonKey: "无法调整智能增强输出尺寸。", solutionKey: "请降低增强目标分辨率后重试。", diagnostic: "enhance:resize-failed")
        case .processingTimeout:
            return ConversionFailure(reasonKey: "智能增强处理超时", solutionKey: "请降低增强目标分辨率后重试。", diagnostic: "enhance:processing-timeout")
        case .finalizationTimeout:
            return ConversionFailure(reasonKey: "输出收尾超时", solutionKey: "请检查磁盘空间与连接，改用本地输出文件夹后重试。", diagnostic: "enhance:finalization-timeout")
        }
    }
#endif

    private func runFFmpeg(ffmpegURL: URL, source: URL, output: URL, info: VideoInfo, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, trim: ClipRange?, rotation: VideoRotation?, crop: CropRect?, aspectRatio: DisplayAspectRatio?, imageAdjustment: ImageAdjustment, id: UUID, count: Int, copyVideoAndEncodeAudio: Bool = false, preferHardwarePipeline: Bool = true, preferHardwareEncoder: Bool = true) async -> ProcessResult {
        guard !cancellationRequested else { return .cancelled }
        let generation = UUID()
        let usedHardwarePipeline = preferHardwarePipeline && canUseVideoToolboxPipeline(info: info, preset: preset, crop: crop, imageAdjustment: imageAdjustment)
        let usedHardwareEncoder = preferHardwareEncoder && usesVideoToolboxEncoder(preset)
        progressGeneration[id] = generation
        progressBuffers[id] = nil
        progressTimes[id] = nil
        lastProgressUpdate[id] = nil
        let runner = FFmpegProcessRunner(
            executable: ffmpegURL,
            arguments: ffmpegArguments(source: source, output: output, info: info, preset: preset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment, copyVideoAndEncodeAudio: copyVideoAndEncodeAudio, preferHardwarePipeline: preferHardwarePipeline, preferHardwareEncoder: preferHardwareEncoder),
            configuration: processConfiguration
        )
        activeProcesses[id] = runner
        defer {
            activeProcesses.removeValue(forKey: id)
            if progressGeneration[id] == generation {
                progressGeneration[id] = nil
                progressBuffers[id] = nil
                progressTimes[id] = nil
                lastProgressUpdate[id] = nil
            }
        }
        let result = await runner.run { [weak self] data in
            Task { @MainActor [weak self] in
                self?.consumeProgress(String(decoding: data, as: UTF8.self), duration: trim.map { $0.end - $0.start } ?? info.duration, id: id, count: count, generation: generation)
            }
        }
        if cancellationRequested || result.wasCancelled { return .cancelled }
        if result.timedOut { return .failure("MP4Flow:stalled") }
        if result.launchError != nil { return .failure("MP4Flow:launch-failed") }
        if result.succeeded { return .success }
        let message = Self.ffmpegFailureMessage(result.standardError)
        if let hint = FFmpegHardwareRetryClassifier.hint(
            stderr: result.standardError,
            usedHardwarePipeline: usedHardwarePipeline,
            usedHardwareEncoder: usedHardwareEncoder
        ) {
            return .retryableFailure(message, hint)
        }
        return .failure(message)
    }

    private func ffmpegArguments(source: URL, output: URL, info: VideoInfo, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, trim: ClipRange?, rotation: VideoRotation?, crop: CropRect?, aspectRatio: DisplayAspectRatio?, imageAdjustment: ImageAdjustment, copyVideoAndEncodeAudio: Bool, preferHardwarePipeline: Bool, preferHardwareEncoder: Bool) -> [String] {
        // Privacy-first default: never copy source metadata or chapters, which
        // may contain title, author, device, location, or editing information.
        var args = ["-hide_banner", "-nostdin", "-y", "-thread_queue_size", "1024"]
        let hardwarePipeline = preferHardwarePipeline && canUseVideoToolboxPipeline(info: info, preset: preset, crop: crop, imageAdjustment: imageAdjustment)
        // For H.264/HEVC without CPU-only edits, keep decoded frames inside
        // VideoToolbox all the way to the encoder. This also benefits an
        // original-size conversion: not just resizes.
        if hardwarePipeline {
            args += ["-init_hw_device", "videotoolbox=vt", "-filter_hw_device", "vt", "-hwaccel", "videotoolbox", "-hwaccel_output_format", "videotoolbox_vld"]
            if info.hardwareDisplayRotation != nil {
                // Hardware decoding does not reliably apply display matrices.
                // Clear the input matrix and apply its known transform below;
                // otherwise pixels can stay sideways or the matrix applies twice.
                args += ["-display_rotation:v", "0"]
            }
        }
        // Input seeking decodes only from the preceding keyframe, including
        // accurate discarding during re-encoding. Output seeking would decode
        // the entire prefix of a long video before producing the first frame.
        // Stream-copy cuts still begin near a keyframe, as the editor explains.
        if let trim {
            args += ["-ss", ffmpegTime(trim.start), "-i", source.path]
        } else {
            args += ["-i", source.path]
        }
        args += ["-map", "0:\(info.videoStreamSpecifier)", "-map", "0:a:0?", "-map_metadata", "-1", "-map_chapters", "-1"]
        if let trim {
            args += ["-t", ffmpegTime(trim.end - trim.start)]
        }
        if copyVideoAndEncodeAudio {
            args += ["-c:v", "copy"] + audioArguments(inputAudioCodec: info.audioCodec, audioRate: info.safeAudioRate, forceAAC: true)
            if info.videoCodec?.lowercased() == "hevc" { args += ["-tag:v", "hvc1"] }
            return args + ["-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
        }
        // Crop coordinates are chosen in the source orientation; rotate before
        // resizing so a selected output height always applies to the final
        // orientation. `transpose_vt` leaves a non-square input SAR unchanged,
        // unlike the CPU transpose filter, so invert it after a 90° turn.
        let editedGeometry = info.geometry(crop: crop, rotation: rotation)
        let rotatedSourceHeight = editedGeometry?.height
        var filters = [crop?.filter].compactMap { $0 }
        if hardwarePipeline, let displayRotation = info.hardwareDisplayRotation {
            filters.append(displayRotation.videoToolboxFilter)
            if displayRotation.swapsDimensions { filters.append("setsar=1/sar") }
        }
        if preset != .remux, let trim, trim.start > 0, let firstFrameFilter = info.trimmedFirstFrameFilter {
            filters.append(firstFrameFilter)
        }
        if let rotation {
            filters.append(hardwarePipeline ? rotation.videoToolboxFilter : rotation.filter)
            if hardwarePipeline && rotation.swapsDimensions {
                filters.append("setsar=1/sar")
            }
        }
        if let aspectRatio, let size = aspectRatio.outputSize(height: resolution.targetHeight ?? rotatedSourceHeight ?? 0) {
            // A correction intentionally reshapes the complete edited frame.
            // Export square pixels so players agree on the corrected geometry.
            filters.append(hardwarePipeline
                ? "scale_vt=w=\(size.width):h=\(size.height)"
                : "scale=\(size.width):\(size.height):flags=bicubic")
            filters.append("setsar=1")
        } else if let resolutionFilter = resolution.filter(sourceHeight: rotatedSourceHeight, quality: quality, useVideoToolbox: hardwarePipeline, canSkipUnchangedSize: editedGeometry?.canSkipUnchangedSize == true) {
            filters.append(resolutionFilter)
        }
        if let adjustmentFilter = imageAdjustment.ffmpegFilter {
            filters.append(info.imageAdjustmentColorNormalization)
            filters.append(adjustmentFilter)
        }
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
        if preset != .remux, let timeBase = info.encodingTimeBase {
            args += ["-enc_time_base:v", timeBase]
        }
        let videoRate = info.outputRate(preset: preset, quality: quality, resolution: resolution, sourceHeight: rotatedSourceHeight), audioRate = info.safeAudioRate
        switch preset {
        case .qualityTop:
            args += preferHardwareEncoder
                ? hardware(codec: "h264_videotoolbox", videoRate: videoRate, audioRate: audioRate, inputAudioCodec: info.audioCodec, keepsVideoToolboxFrames: hardwarePipeline)
                : softwareBitrate(videoRate: videoRate, audioRate: audioRate, inputAudioCodec: info.audioCodec)
        case .h264Cap8:
            args += preferHardwareEncoder
                ? hardware(codec: "h264_videotoolbox", videoRate: videoRate, audioRate: 192_000, inputAudioCodec: info.audioCodec, forceAAC: true, keepsVideoToolboxFrames: hardwarePipeline)
                : softwareBitrate(videoRate: videoRate, audioRate: 192_000, inputAudioCodec: info.audioCodec, forceAAC: true)
        case .smartMP4, .smartEnhanceUpscale: preconditionFailure("智能预设必须在探测后解析为具体编码路径")
        case .h264Hardware:
            args += preferHardwareEncoder
                ? hardware(codec: "h264_videotoolbox", videoRate: videoRate, audioRate: audioRate, inputAudioCodec: info.audioCodec, keepsVideoToolboxFrames: hardwarePipeline)
                : softwareBitrate(videoRate: videoRate, audioRate: audioRate, inputAudioCodec: info.audioCodec)
        case .hevcHardware:
            args += preferHardwareEncoder
                ? hardware(codec: "hevc_videotoolbox", videoRate: videoRate, audioRate: audioRate, inputAudioCodec: info.audioCodec, keepsVideoToolboxFrames: hardwarePipeline) + ["-tag:v", "hvc1"]
                : softwareBitrate(videoRate: videoRate, audioRate: audioRate, inputAudioCodec: info.audioCodec)
        case .h264Software:
            args += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "\(quality.crf)", "-pix_fmt", "yuv420p"]
            args += audioArguments(inputAudioCodec: info.audioCodec, audioRate: audioRate)
        case .remux: args += ["-c", "copy"]
        }
        return args + ["-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
    }

    private func usesVideoToolboxEncoder(_ preset: ConversionPreset) -> Bool {
        preset == .qualityTop || preset == .h264Cap8 || preset == .h264Hardware || preset == .hevcHardware
    }

    private func canUseVideoToolboxPipeline(info: VideoInfo, preset: ConversionPreset, crop: CropRect?, imageAdjustment: ImageAdjustment) -> Bool {
        usesVideoToolboxEncoder(preset)
            && crop == nil && imageAdjustment.isIdentity
            && (info.displayRotation == nil || info.displayGeometry != nil)
            && ["h264", "hevc"].contains(info.videoCodec?.lowercased() ?? "")
    }

    private func hardware(codec: String, videoRate: Int, audioRate: Int, inputAudioCodec: String?, forceAAC: Bool = false, keepsVideoToolboxFrames: Bool = false) -> [String] {
        var args = ["-c:v", codec, "-prio_speed", "1", "-b:v", rate(videoRate), "-maxrate", rate(Int(Double(videoRate) * 1.25)), "-bufsize", rate(videoRate * 2)]
        if !keepsVideoToolboxFrames { args += ["-pix_fmt", "yuv420p"] }
        args += audioArguments(inputAudioCodec: inputAudioCodec, audioRate: audioRate, forceAAC: forceAAC)
        return args
    }
    private func softwareBitrate(videoRate: Int, audioRate: Int, inputAudioCodec: String?, forceAAC: Bool = false) -> [String] {
        ["-c:v", "libx264", "-preset", "veryfast", "-b:v", rate(videoRate), "-maxrate", rate(Int(Double(videoRate) * 1.25)), "-bufsize", rate(videoRate * 2), "-pix_fmt", "yuv420p"]
            + audioArguments(inputAudioCodec: inputAudioCodec, audioRate: audioRate, forceAAC: forceAAC)
    }
    private func audioArguments(inputAudioCodec: String?, audioRate: Int, forceAAC: Bool = false) -> [String] {
        !forceAAC && inputAudioCodec?.lowercased() == "aac" ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", rate(audioRate)]
    }
    private func rate(_ bits: Int) -> String { "\(max(64, bits / 1_000))k" }
    private func outputSummary(_ info: VideoInfo, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, sourceHeight: Int? = nil) -> String {
        let sizeLabel = resolution.targetHeight.map { " · \($0)P" } ?? ""
        let videoRate = Double(info.outputRate(preset: preset, quality: quality, resolution: resolution, sourceHeight: sourceHeight)) / 1_000_000
        if preset == .qualityTop {
            return L10n.format("保留源码率 %.1f Mbps%@", videoRate, sizeLabel)
        }
        if preset == .h264Cap8 { return "H.264 \(String(format: "%.1f", videoRate)) Mbps · AAC 192k\(sizeLabel)" }
        if preset == .h264Software { return "H.264 · CRF \(quality.crf)\(sizeLabel)" }
        if preset == .smartEnhanceUpscale { return L10n.text("智能增强放大（实验性）") + sizeLabel }
        if preset == .remux { return L10n.text("不重新编码") }
        return L10n.format("目标码率 %.1f Mbps", videoRate) + sizeLabel
    }

    private func consumeProgress(_ text: String, duration: Double?, id: UUID, count: Int, generation: UUID) {
        guard progressGeneration[id] == generation else { return }
        let combined = (progressBuffers[id] ?? "") + text
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        progressBuffers[id] = combined.hasSuffix("\n") ? "" : String(lines.last ?? "")
        for line in (combined.hasSuffix("\n") ? lines : lines.dropLast()) {
            let parts = line.split(separator: "=", maxSplits: 1); guard parts.count == 2 else { continue }
            switch parts[0] {
            case "out_time_us", "out_time_ms":
                if let value = Double(parts[1]) { progressTimes[id] = value / 1_000_000 }
            case "out_time":
                if let seconds = parseTimestamp(String(parts[1])) { progressTimes[id] = seconds }
            case "progress":
                guard let duration, duration > 0, let seconds = progressTimes[id], let index = items.firstIndex(where: { $0.id == id }) else { continue }
                let isFinal = parts[1] == "end"
                let now = Date()
                guard isFinal || now.timeIntervalSince(lastProgressUpdate[id] ?? .distantPast) >= 0.15 else { continue }
                lastProgressUpdate[id] = now
                items[index].state = .running(isFinal ? 0.999 : min(max(seconds / duration, 0), 0.999))
                refreshProgress(count)
            default:
                continue
            }
        }
    }

    private func parseTimestamp(_ value: String) -> Double? {
        let fields = value.split(separator: ":").compactMap { Double($0) }
        guard fields.count == 3 else { return nil }
        return fields[0] * 3_600 + fields[1] * 60 + fields[2]
    }

    private func refreshProgress(_ count: Int) {
        guard count > 0 else { overallProgress = nil; return }
        let jobs = items.filter { queueIDs.contains($0.id) }
        guard !jobs.isEmpty else { overallProgress = nil; return }
        if jobs.contains(where: { if case .running(nil) = $0.state { return true }; return false }) { overallProgress = nil; return }
        // Completed or waiting rows can be removed during a batch. Base the
        // denominator on the remaining snapshot rather than the original size.
        overallProgress = jobs.reduce(0.0) { sum, item in switch item.state { case .complete, .failed, .cancelled: sum + 1; case .running(let progress), .merging(let progress): sum + (progress ?? 0); case .waiting: sum } } / Double(jobs.count)
    }

    private func probe(_ source: URL, ffmpegURL: URL) async -> VideoInfo {
        guard let probe = locateFFprobe(for: ffmpegURL) else {
            return Self.unavailableProbeInfo()
        }
        guard !cancellationRequested else { return Self.unavailableProbeInfo() }
        let id = UUID()
        let runner = FFmpegProcessRunner(
            executable: probe,
            arguments: Self.probeArguments(for: source),
            configuration: FFmpegProcessRunner.Configuration(inactivityTimeout: 30)
        )
        activeProcesses[id] = runner
        defer { activeProcesses.removeValue(forKey: id) }
        return await Self.inspectMedia(at: source, using: probe, runner: runner)
    }

    /// Keep process I/O independent of the store so media inspection can be
    /// exercised with a stream-rich ffprobe response in integration tests.
    nonisolated static func inspectMedia(at source: URL, using probe: URL, runner suppliedRunner: FFmpegProcessRunner? = nil) async -> VideoInfo {
        let runner = suppliedRunner ?? FFmpegProcessRunner(
            executable: probe,
            arguments: probeArguments(for: source),
            configuration: FFmpegProcessRunner.Configuration(inactivityTimeout: 30)
        )
        let result = await runner.run()
        return result.succeeded
            ? (decodeProbe(result.standardOutput) ?? unavailableProbeInfo())
            : unavailableProbeInfo()
    }

    nonisolated private static func probeArguments(for source: URL) -> [String] {
        ["-v", "error", "-show_entries", "stream=index,id,codec_type,codec_name,bit_rate,width,height,r_frame_rate,avg_frame_rate,time_base,pix_fmt,sample_rate,channels,color_transfer,color_space,color_primaries,color_range,sample_aspect_ratio:stream_disposition=attached_pic,timed_thumbnails:stream_side_data=rotation:stream_tags=rotate:chapter=id:format=duration,bit_rate,format_name", "-of", "json", source.path]
    }

    nonisolated private static func unavailableProbeInfo() -> VideoInfo {
        VideoInfo(duration: nil, videoRate: nil, audioRate: nil, width: nil, height: nil, hasVideo: false, videoCodec: nil, audioCodec: nil, frameRate: nil, pixelFormat: nil, audioSampleRate: nil, audioChannels: nil, audioTrackCount: 0, subtitleTrackCount: 0, colorTransfer: nil, probeSucceeded: false)
    }

    nonisolated private static func decodeProbe(_ data: Data) -> VideoInfo? {
        guard let response = try? JSONDecoder().decode(ProbeResponse.self, from: data) else { return nil }
        let videoStreams = response.streams.filter(\.isMovieVideo)
        let video = videoStreams.first
        let audioStreams = response.streams.filter { $0.codecType == "audio" }
        let subtitleStreams = response.streams.filter { $0.codecType == "subtitle" }
        let audio = audioStreams.first
        let videoRate = Int(video?.bitRate ?? "") ?? response.format.flatMap {
            guard let total = Int($0.bitRate ?? "") else { return nil }
            return max(total - (Int(audio?.bitRate ?? "") ?? 0), 1)
        }
        var info = VideoInfo(duration: Double(response.format?.duration ?? ""), videoRate: videoRate, audioRate: Int(audio?.bitRate ?? ""), width: video?.width, height: video?.height, hasVideo: video != nil, videoCodec: video?.codecName, audioCodec: audio?.codecName, frameRate: video?.rFrameRate, pixelFormat: video?.pixelFormat, audioSampleRate: audio?.sampleRate, audioChannels: audio?.channels, audioTrackCount: audioStreams.count, subtitleTrackCount: subtitleStreams.count, colorTransfer: video?.colorTransfer, probeSucceeded: true)
        info.colorSpace = video?.colorSpace
        info.colorPrimaries = video?.colorPrimaries
        info.colorRange = video?.colorRange
        info.averageFrameRate = video?.avgFrameRate
        let rotationTag = video?.tags?["rotate"]
        let rotation = video?.sideDataList?.compactMap(\.rotation).first ?? rotationTag.flatMap(Double.init)
        if rotationTag == nil || rotation != nil {
            info.displayGeometry = VideoGeometry.displayed(width: video?.width, height: video?.height, sampleAspectRatio: video?.sampleAspectRatio, rotation: rotation)
        }
        info.timeBase = video?.timeBase
        info.sampleAspectRatio = video?.sampleAspectRatio
        info.displayRotation = rotation
        info.videoTrackCount = videoStreams.count
        info.selectedVideoStreamIndex = video?.index.flatMap { $0 >= 0 ? $0 : nil }
        info.selectedVideoTrackID = response.format?.usesNativeTrackIDs == true ? video?.nativeTrackID : nil
        info.streamLayout = response.streams.map {
            MediaStreamLayout(index: $0.index, type: $0.codecType, codec: $0.codecName, isAuxiliaryImage: $0.disposition?.isAuxiliaryImage == true)
        }
        info.chapterCount = response.chapters?.count ?? 0
        return info
    }

    private func locateFFmpeg() -> URL? {
        if let ffmpegOverride {
            return FileManager.default.isExecutableFile(atPath: ffmpegOverride.path) ? ffmpegOverride : nil
        }
        return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    private func locateFFprobe(for ffmpeg: URL) -> URL? {
        let sibling = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }
    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
    private func uniqueOutput(for source: URL, trim: ClipRange?, rotation: VideoRotation?, crop: CropRect?, aspectRatio: DisplayAspectRatio?, imageAdjustment: ImageAdjustment) -> URL {
        let directory = outputDirectory ?? source.deletingLastPathComponent(), stem = source.deletingPathExtension().lastPathComponent
        var suffix = trim.map { "-trim-\(fileNameTime($0.start))-\(fileNameTime($0.end))" } ?? "-MP4FlowConverted"
        if crop != nil { suffix += "-cropped" }
        if let aspectRatio { suffix += "-aspect-\(aspectRatio.width)x\(aspectRatio.height)" }
        if let rotation { suffix += "-\(rotation.fileSuffix)" }
        if !imageAdjustment.isIdentity { suffix += "-adjusted" }
        var result = directory.appendingPathComponent("\(stem)\(suffix).mp4"), number = 2
        while FileManager.default.fileExists(atPath: result.path) { result = directory.appendingPathComponent("\(stem)\(suffix)-\(number).mp4"); number += 1 }
        return result
    }
    private func uniqueMergeOutput(for firstSource: URL) -> URL {
        let directory = outputDirectory ?? firstSource.deletingLastPathComponent()
        let stem = "\(firstSource.deletingPathExtension().lastPathComponent)-merge"
        var result = directory.appendingPathComponent("\(stem).mp4"), number = 2
        while FileManager.default.fileExists(atPath: result.path) {
            result = directory.appendingPathComponent("\(stem)-\(number).mp4")
            number += 1
        }
        return result
    }
    private func ffmpegTime(_ seconds: Double) -> String { String(format: "%.3f", seconds) }
    private func fileNameTime(_ seconds: Double) -> String { String(format: "%02d%02d%02d", Int(seconds) / 3600, (Int(seconds) % 3600) / 60, Int(seconds) % 60) }
    nonisolated static func ffmpegFailureMessage(_ stderr: String) -> String {
        let text = stderr.lowercased()
        if text.contains("no space left") || text.contains("disk full") { return "MP4Flow:disk-full" }
        if text.contains("permission denied") || text.contains("operation not permitted") { return "MP4Flow:permission" }
        if text.contains("no such file") { return "MP4Flow:missing-source" }
        if text.contains("invalid data found when processing input") || text.contains("moov atom not found") || text.contains("could not find codec parameters") {
            return "MP4Flow:unreadable-media"
        }
        if FFmpegHardwareRetryClassifier.hint(stderr: stderr, usedHardwarePipeline: false, usedHardwareEncoder: true) == .softwareEncoder {
            return "MP4Flow:hardware-encoder"
        }
        if text.contains("unknown encoder") { return "MP4Flow:software-encoder" }
        let containerFailures = [
            "could not find tag for codec", "codec not currently supported in container",
            "codec not supported in container", "muxer does not support"
        ]
        if containerFailures.contains(where: text.contains) { return "MP4Flow:container-incompatible" }
        return "MP4Flow:conversion-failed"
    }
    private func friendlyMergeError(_ stderr: String) -> String {
        let normalized = Self.ffmpegFailureMessage(stderr)
        guard normalized == "MP4Flow:conversion-failed" else { return normalized }
        let text = stderr.lowercased()
        if text.contains("non monotonous") || text.contains("invalid data") || text.contains("concat") {
            return L10n.text("片段时间轴或流参数不兼容。请先使用相同预设转换为 MP4 后再合并。")
        }
        return normalized
    }
}
