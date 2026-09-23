import AppKit
import AVFoundation
import Darwin
import SwiftUI
import UniformTypeIdentifiers

enum ConversionPreset: String, CaseIterable, Identifiable, Sendable {
    case qualityTop, h264Cap8, smartMP4, h264Hardware, hevcHardware, h264Software, remux
    var id: String { rawValue }

    /// The main menu answers a user's goal first. Encoding-specific fallbacks
    /// stay available, but never compete with the everyday choices.
    static let menuOrder: [ConversionPreset] = [
        .smartMP4, .h264Cap8, .qualityTop, .h264Hardware,
        .hevcHardware, .h264Software, .remux
    ]

    var menuSection: String {
        switch self {
        case .smartMP4, .h264Cap8, .qualityTop, .h264Hardware: L10n.text("常用选择")
        case .hevcHardware, .h264Software, .remux: L10n.text("更多选择")
        }
    }

    var title: String {
        switch self {
        case .smartMP4: L10n.text("智能转换（推荐）")
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
    var requiresReencode: Bool { targetHeight != nil }

    func filter(sourceHeight: Int?, quality: ConversionQuality, useVideoToolbox: Bool) -> String? {
        guard let targetHeight else { return nil }
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

struct VideoPresentation: Equatable {
    let summary: String?
    let thumbnail: NSImage?

    // NSImage itself is not Equatable; the textual summary is the state that
    // participates in SwiftUI's list updates.
    static func == (lhs: VideoPresentation, rhs: VideoPresentation) -> Bool {
        lhs.summary == rhs.summary
    }

    static func load(from source: URL) async -> VideoPresentation {
        let fileSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let asset = AVURLAsset(url: source)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let naturalSize = try? await track?.load(.naturalSize)

        var parts: [String] = []
        if let naturalSize, naturalSize.width > 0, naturalSize.height > 0 {
            parts.append("\(Int(abs(naturalSize.width).rounded())) × \(Int(abs(naturalSize.height).rounded()))")
        }
        if duration.isFinite, duration > 0 { parts.append(formattedDuration(duration)) }
        if let fileSize { parts.append(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)) }

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
        return VideoPresentation(summary: parts.isEmpty ? nil : parts.joined(separator: " · "), thumbnail: image)
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

    static func == (lhs: ConversionItem, rhs: ConversionItem) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.state == rhs.state && lhs.presentation == rhs.presentation && lhs.trimRange == rhs.trimRange && lhs.rotation == rhs.rotation && lhs.crop == rhs.crop
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

    var fileSuffix: String {
        switch self {
        case .clockwise: "rotated-cw"
        case .counterclockwise: "rotated-ccw"
        case .upsideDown: "rotated-180"
        }
    }
}

private struct VideoInfo: Sendable {
    let duration: Double?, videoRate: Int?, audioRate: Int?, width: Int?, height: Int?, hasVideo: Bool
    let videoCodec: String?
    let audioCodec: String?
    let frameRate: String?
    let pixelFormat: String?
    let audioSampleRate: String?
    let audioChannels: Int?

    /// These elementary streams can be placed in MP4 without loss. Restricting
    /// audio to AAC keeps the automatic path broadly compatible with players.
    var canDirectRemuxToMP4: Bool {
        ["h264", "hevc"].contains(videoCodec?.lowercased() ?? "")
            && (audioCodec == nil || audioCodec?.lowercased() == "aac")
    }
    var mergeSignature: MergeSignature? {
        guard let videoCodec, let width, let height, let frameRate, let pixelFormat else { return nil }
        return MergeSignature(videoCodec: videoCodec.lowercased(), width: width, height: height, frameRate: frameRate, pixelFormat: pixelFormat, audioCodec: audioCodec?.lowercased(), audioSampleRate: audioSampleRate, audioChannels: audioChannels)
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
    func outputRate(preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution) -> Int {
        let baseRate: Int
        switch preset {
        case .qualityTop:
            baseRate = min(max(matchedRate, 500_000), 100_000_000)
        case .h264Cap8:
            baseRate = min(max(min(matchedRate, 8_000_000), 500_000), 8_000_000)
        case .smartMP4, .h264Hardware, .hevcHardware, .h264Software, .remux:
            baseRate = min(max(Int((Double(matchedRate) * preset.efficiency * quality.multiplier).rounded()), 500_000), 100_000_000)
        }
        return min(max(Int((Double(baseRate) * resolution.rateMultiplier(sourceHeight: height)).rounded()), 500_000), 100_000_000)
    }
}

private struct MergeSignature: Hashable, Sendable {
    let videoCodec: String
    let width: Int
    let height: Int
    let frameRate: String
    let pixelFormat: String
    let audioCodec: String?
    let audioSampleRate: String?
    let audioChannels: Int?
}

private struct CompatibleMergeTarget: Sendable {
    let width: Int
    let height: Int
    let frameRate: String

    var summary: String { "\(width) × \(height)" }
}

private struct ProbeResponse: Decodable, Sendable { let streams: [ProbeStream]; let format: ProbeFormat? }
private struct ProbeStream: Decodable, Sendable {
    let codecType: String?, codecName: String?, bitRate: String?, width: Int?, height: Int?
    let rFrameRate: String?, pixelFormat: String?, sampleRate: String?, channels: Int?
    enum CodingKeys: String, CodingKey {
        case codecType = "codec_type", codecName = "codec_name", bitRate = "bit_rate"
        case rFrameRate = "r_frame_rate", pixelFormat = "pix_fmt", sampleRate = "sample_rate", channels, width, height
    }
}
private struct ProbeFormat: Decodable, Sendable {
    let duration: String?, bitRate: String?
    enum CodingKeys: String, CodingKey { case duration, bitRate = "bit_rate" }
}

private final class ErrorBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func append(_ text: String) { lock.lock(); value = String((value + text).suffix(4_000)); lock.unlock() }
    func read() -> String { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
final class ConverterStore: ObservableObject {
    @Published var items: [ConversionItem] = []
    @Published var preset: ConversionPreset = .smartMP4
    @Published var quality: ConversionQuality = .balanced
    @Published var outputResolution: OutputResolution = .original
    @Published var outputDirectory: URL?
    @Published var isRunning = false
    @Published var overallProgress: Double?
    @Published var statusText = ""
    @Published var showFFmpegSetup = false
    @Published private(set) var isMerging = false
    @Published var showMergeNotice = false
    @Published var showCompatibleMergePrompt = false
    @Published private(set) var mergeNotice = ""
    @Published private(set) var mergeOutput: URL?
    @Published private(set) var mergeProgress: Double?

    private var ffmpegURL: URL?
    private var activeProcesses: [UUID: Process] = [:]
    private var cancellationRequested = false
    private var queueIDs: [UUID] = []
    private var progressTimes: [UUID: Double] = [:]
    private var progressBuffers: [UUID: String] = [:]
    private var lastProgressUpdate: [UUID: Date] = [:]
    private var mergeItemIDs: [UUID] = []
    private var mergeDurations: [Double?] = []
    private var mergeProgressBuffer = ""
    private var mergeProgressTime: Double?
    private var compatibleMergeIDs: [UUID] = []
    private var isCompatibleMerging = false
    private let presentationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.ixiehao.mp4flow.media-inspection"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    var hasWaiting: Bool { items.contains { if case .waiting = $0.state { return true }; return false } }
    var hasCompleted: Bool { items.contains { if case .complete = $0.state { return true }; return false } }
    var hasIncomplete: Bool { items.contains { if case .failed = $0.state { return true }; if case .cancelled = $0.state { return true }; return false } }
    var mergeCandidateCount: Int { items.reduce(into: 0) { if case .waiting = $1.state, $1.trimRange == nil, $1.rotation == nil, $1.crop == nil { $0 += 1 } } }
    var mergeDisplayCount: Int { isMerging ? mergeItemIDs.count : mergeCandidateCount }
    var canMerge: Bool { !isBusy && mergeCandidateCount >= 2 }
    var isBusy: Bool { isRunning || isMerging }
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
        case .smartMP4, .h264Hardware, .hevcHardware, .h264Software:
            break
        }
        return quality.detail
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
        queueIDs.removeAll { completedIDs.contains($0) }
        if isRunning { refreshProgress(queueIDs.count) }
    }
    /// Removes queue records only. Source files and generated outputs remain untouched.
    func clearQueue() {
        guard !isBusy else { return }
        items.removeAll()
        statusText = ""
    }
    func retryIncomplete() {
        guard !isRunning else { return }
        for index in items.indices { if case .failed = items[index].state { items[index].state = .waiting }; if case .cancelled = items[index].state { items[index].state = .waiting } }
    }

    func start() {
        guard !isMerging else { return }
        guard let binary = locateFFmpeg() else { showFFmpegSetup = true; return }
        let pendingIDs = items.compactMap { if case .waiting = $0.state { return $0.id }; return nil }
        guard !pendingIDs.isEmpty else { return }
        ffmpegURL = binary; cancellationRequested = false; queueIDs = pendingIDs; isRunning = true; overallProgress = 0
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
        let sources = items.compactMap { item -> URL? in if case .waiting = item.state, item.trimRange == nil, item.rotation == nil, item.crop == nil { return item.source }; return nil }
        mergeItemIDs = items.compactMap { item -> UUID? in if case .waiting = item.state, item.trimRange == nil, item.rotation == nil, item.crop == nil { return item.id }; return nil }
        for index in items.indices where mergeItemIDs.contains(items[index].id) { items[index].state = .merging(nil) }
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
            guard compatibleMergeIDs.contains(item.id), item.trimRange == nil, item.rotation == nil, item.crop == nil else { return false }
            if case .waiting = item.state { return true }
            return false
        }
        guard candidates.count >= 2 else { return }
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
        if isRunning { refreshProgress(queueIDs.count) }
    }

    func canRemove(_ item: ConversionItem) -> Bool {
        if case .running = item.state { return false }
        if case .merging = item.state { return false }
        return true
    }

    func cancel() {
        guard isRunning else { return }
        cancellationRequested = true; statusText = L10n.text("正在停止转换")
        activeProcesses.values.forEach { $0.terminate() }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.isRunning, self.cancellationRequested else { return }
            self.activeProcesses.values.filter(\.isRunning).forEach { process in
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    func revealMergeOutput() {
        guard let mergeOutput else { return }
        NSWorkspace.shared.activateFileViewerSelecting([mergeOutput])
    }

    func scheduleTrim(_ item: ConversionItem, start: Double, end: Double) {
        guard !isBusy, end > start, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].trimRange = ClipRange(start: start, end: end)
    }

    func scheduleRotation(_ item: ConversionItem, rotation: VideoRotation?) {
        guard !isBusy, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].rotation = rotation
    }

    func scheduleCrop(_ item: ConversionItem, crop: CropRect?) {
        guard !isBusy, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].crop = crop
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
        let store = self
        presentationQueue.addOperation {
            // Keep the queue's bounded concurrency while loading modern
            // AVFoundation properties asynchronously.
            let completed = DispatchSemaphore(value: 0)
            Task {
                let presentation = await VideoPresentation.load(from: item.source)
                Task { @MainActor [store] in
                    defer { completed.signal() }
                    guard let index = store.items.firstIndex(where: { $0.id == item.id }) else { return }
                    store.items[index].presentation = presentation
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
        for source in sources { infos.append(await probe(source, ffmpegURL: ffmpegURL)) }
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

        let result = await runMergeFFmpeg(ffmpegURL: ffmpegURL, listURL: listURL, output: temporary)
        try? FileManager.default.removeItem(at: listURL)
        switch result {
        case .success:
            do {
                try FileManager.default.moveItem(at: temporary, to: output)
                finishMerge(message: L10n.format("已无损合并 %d 个片段：%@", sources.count, output.lastPathComponent), output: output)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                finishMerge(message: L10n.format("无法无损合并：%@", error.localizedDescription), output: nil)
            }
        case .failure(let message):
            try? FileManager.default.removeItem(at: temporary)
            finishMerge(message: L10n.format("无法无损合并：%@", message), output: nil)
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
        mergeNotice = message
        mergeOutput = output
        mergeProgress = nil
        mergeItemIDs.removeAll()
        mergeDurations.removeAll()
        mergeProgressBuffer = ""
        mergeProgressTime = nil
        compatibleMergeIDs.removeAll()
        isCompatibleMerging = false
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
        isMerging = false
        statusText = L10n.text("片段参数不同，可使用兼容合并。")
        showCompatibleMergePrompt = true
    }

    private func runMergeFFmpeg(ffmpegURL: URL, listURL: URL, output: URL) async -> ProcessResult {
        let process = Process(), progress = Pipe(), errors = Pipe(), stderr = ErrorBuffer()
        let store = self
        process.executableURL = ffmpegURL
        process.arguments = ["-hide_banner", "-nostdin", "-y", "-f", "concat", "-safe", "0", "-i", listURL.path, "-map", "0:v:0?", "-map", "0:a:0?", "-map_metadata", "-1", "-map_chapters", "-1", "-c", "copy", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
        process.standardOutput = progress
        process.standardError = errors
        progress.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [store] in store.consumeMergeProgress(String(decoding: data, as: UTF8.self)) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderr.append(String(decoding: data, as: UTF8.self))
        }
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                progress.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor [store] in
                    if finished.terminationStatus == 0 { continuation.resume(returning: .success) }
                    else { continuation.resume(returning: .failure(store.friendlyMergeError(stderr.read(), code: finished.terminationStatus))) }
                }
            }
            do { try process.run() }
            catch {
                progress.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: .failure("无法启动 FFmpeg：\(error.localizedDescription)"))
            }
        }
    }

    private func mergeCompatible(sources: [URL], ffmpegURL: URL) async {
        var infos: [VideoInfo] = []
        for source in sources { infos.append(await probe(source, ffmpegURL: ffmpegURL)) }
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
        if case .failure = result, !cancellationRequested {
            statusText = L10n.text("硬件编码不可用，正在使用兼容编码重试")
            resetCompatibleMergeProgress()
            result = await runCompatibleMergeFFmpeg(ffmpegURL: ffmpegURL, sources: sources, infos: infos, target: target, output: temporary, preferHardwareEncoder: false)
        }
        switch result {
        case .success:
            do {
                try FileManager.default.moveItem(at: temporary, to: output)
                finishMerge(message: L10n.format("已兼容合并 %d 个片段（统一为 %@）：%@", sources.count, target.summary, output.lastPathComponent), output: output)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                finishMerge(message: L10n.format("兼容合并失败：%@", error.localizedDescription), output: nil)
            }
        case .failure(let message):
            try? FileManager.default.removeItem(at: temporary)
            finishMerge(message: L10n.format("兼容合并失败：%@", message), output: nil)
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
        let process = Process(), progress = Pipe(), errors = Pipe(), stderr = ErrorBuffer()
        let store = self
        process.executableURL = ffmpegURL
        process.arguments = compatibleMergeArguments(sources: sources, infos: infos, target: target, output: output, preferHardwareEncoder: preferHardwareEncoder)
        process.standardOutput = progress
        process.standardError = errors
        progress.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [store] in store.consumeMergeProgress(String(decoding: data, as: UTF8.self)) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderr.append(String(decoding: data, as: UTF8.self))
        }
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                progress.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor [store] in
                    if finished.terminationStatus == 0 { continuation.resume(returning: .success) }
                    else { continuation.resume(returning: .failure(store.friendlyMergeError(stderr.read(), code: finished.terminationStatus))) }
                }
            }
            do { try process.run() }
            catch {
                progress.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: .failure("无法启动 FFmpeg：\(error.localizedDescription)"))
            }
        }
    }

    /// Normalize to the largest source frame rather than to the first file in
    /// queue. Smaller clips are scaled up proportionally; differing aspect
    /// ratios are centered on a black canvas, never stretched or cropped.
    private func compatibleMergeTarget(_ infos: [VideoInfo]) -> CompatibleMergeTarget {
        let largest = infos.max { lhs, rhs in
            let lhsPixels = max(lhs.width ?? 0, 0) * max(lhs.height ?? 0, 0)
            let rhsPixels = max(rhs.width ?? 0, 0) * max(rhs.height ?? 0, 0)
            return lhsPixels < rhsPixels
        } ?? infos[0]
        return CompatibleMergeTarget(
            width: even(largest.width ?? 1920),
            height: even(largest.height ?? 1080),
            frameRate: largest.frameRate ?? "30"
        )
    }

    private func compatibleMergeArguments(sources: [URL], infos: [VideoInfo], target: CompatibleMergeTarget, output: URL, preferHardwareEncoder: Bool) -> [String] {
        var args = ["-hide_banner", "-nostdin", "-y"]
        for source in sources { args += ["-i", source.path] }

        var filters: [String] = []
        for (index, info) in infos.enumerated() {
            filters.append("[\(index):v:0]scale=\(target.width):\(target.height):force_original_aspect_ratio=decrease,pad=\(target.width):\(target.height):(ow-iw)/2:(oh-ih)/2:color=black,fps=\(target.frameRate),setsar=1,format=yuv420p[v\(index)]")
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
        mergeProgress = clampedSeconds / total
        var elapsed = 0.0
        for (offset, id) in mergeItemIDs.enumerated() {
            guard let index = items.firstIndex(where: { $0.id == id }), let duration = mergeDurations[offset] else { continue }
            let localProgress = (clampedSeconds - elapsed) / duration
            let displayedProgress: Double? = localProgress < 0 ? nil : min(max(localProgress, 0), 1)
            items[index].state = .merging(displayedProgress)
            elapsed += duration
        }
    }

    private func convertQueue(ids: [UUID]) async {
        guard let binary = ffmpegURL, !ids.isEmpty else { isRunning = false; return }
        let options = (preset, quality, outputResolution)
        for id in ids {
            guard shouldContinue else { break }
            await convert(id: id, ffmpegURL: binary, preset: options.0, quality: options.1, resolution: options.2, count: ids.count)
        }
        if cancellationRequested {
            for index in items.indices where queueIDs.contains(items[index].id) { if case .waiting = items[index].state { items[index].state = .cancelled } }
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
        activeProcesses.removeAll(); progressBuffers.removeAll(); progressTimes.removeAll(); lastProgressUpdate.removeAll(); queueIDs.removeAll(); isRunning = false
        presentationQueue.isSuspended = false
    }

    private var shouldContinue: Bool { !cancellationRequested }

    private func convert(id: UUID, ffmpegURL: URL, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, count: Int) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let source = item.source
        let trim = item.trimRange
        let rotation = item.rotation
        let crop = item.crop
        let info = await probe(source, ffmpegURL: ffmpegURL)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !cancellationRequested else { items[index].state = .cancelled; return }
        guard info.hasVideo else { items[index].state = .failed(L10n.text("未检测到视频流，文件可能损坏或只是音频文件。")); refreshProgress(count); return }
        // A trim should not silently become a full re-encode. When the source
        // streams are safe in MP4, use lossless stream copy regardless of the
        // selected conversion preset. This is the same fast path as “极速直封装”.
        // Unsupported streams fall back to the user's normal hardware/software
        // conversion choice so the output remains a playable MP4.
        let effectivePreset: ConversionPreset
        if rotation != nil || crop != nil || resolution.requiresReencode {
            effectivePreset = (preset == .qualityTop || preset == .h264Cap8) ? preset : .h264Hardware
        } else if trim != nil, info.canDirectRemuxToMP4 {
            effectivePreset = .remux
        } else if preset == .smartMP4 {
            effectivePreset = info.canDirectRemuxToMP4 ? .remux : .h264Hardware
        } else {
            effectivePreset = preset
        }
        items[index].state = .running(info.duration == nil ? nil : 0)
        // The footer supplies the conversion state and current queue count.
        // Keep this text focused on the selected output characteristics.
        statusText = outputSummary(info, preset: effectivePreset, quality: quality, resolution: resolution)
        let final = uniqueOutput(for: source, trim: trim, rotation: rotation, crop: crop)
        let temporary = final.deletingLastPathComponent().appendingPathComponent(".MP4Flow-\(UUID().uuidString).partial.mp4")
        var result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, id: id, count: count)
        // Keep the fast VideoToolbox path as the default, but never make one
        // unavailable hardware session fail an otherwise healthy batch. The
        // first retry only moves decode/filtering back to the CPU; if the
        // hardware encoder itself is unavailable, the final retry uses libx264
        // at the same target bitrate. Retries are per-item and bounded.
        if case .failure = result,
           !cancellationRequested,
           canUseVideoToolboxPipeline(info: info, preset: effectivePreset, rotation: rotation, crop: crop) {
            statusText = L10n.text("硬件处理失败，正在使用兼容方式重试")
            result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, id: id, count: count, preferHardwarePipeline: false)
        }
        if case .failure = result,
           !cancellationRequested,
           usesVideoToolboxEncoder(effectivePreset) {
            statusText = L10n.text("硬件编码不可用，正在使用兼容编码重试")
            result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, id: id, count: count, preferHardwarePipeline: false, preferHardwareEncoder: false)
        }
        guard let current = items.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .success:
            do { try FileManager.default.moveItem(at: temporary, to: final); items[current].state = .complete(final) }
            catch { items[current].state = .failed("无法保存输出文件：\(error.localizedDescription)"); try? FileManager.default.removeItem(at: temporary) }
        case .cancelled: items[current].state = .cancelled; try? FileManager.default.removeItem(at: temporary)
        case .failure(let message): items[current].state = .failed(message); try? FileManager.default.removeItem(at: temporary)
        }
        refreshProgress(count)
    }

    private enum ProcessResult { case success, cancelled, failure(String) }

    private func runFFmpeg(ffmpegURL: URL, source: URL, output: URL, info: VideoInfo, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, trim: ClipRange?, rotation: VideoRotation?, crop: CropRect?, id: UUID, count: Int, preferHardwarePipeline: Bool = true, preferHardwareEncoder: Bool = true) async -> ProcessResult {
        let process = Process(), progress = Pipe(), errors = Pipe()
        let store = self
        process.executableURL = ffmpegURL
        process.arguments = ffmpegArguments(source: source, output: output, info: info, preset: preset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, preferHardwarePipeline: preferHardwarePipeline, preferHardwareEncoder: preferHardwareEncoder)
        process.standardOutput = progress; process.standardError = errors
        let stderr = ErrorBuffer()
        progress.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData; guard !data.isEmpty else { return }
            Task { @MainActor [store] in store.consumeProgress(String(decoding: data, as: UTF8.self), duration: trim.map { $0.end - $0.start } ?? info.duration, id: id, count: count) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData; guard !data.isEmpty else { return }
            stderr.append(String(decoding: data, as: UTF8.self))
        }
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                progress.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor [store] in
                    store.activeProcesses.removeValue(forKey: id)
                    if store.cancellationRequested { continuation.resume(returning: .cancelled) }
                    else if finished.terminationStatus == 0 { continuation.resume(returning: .success) }
                    else { continuation.resume(returning: .failure(store.friendlyError(stderr.read(), code: finished.terminationStatus))) }
                }
            }
            activeProcesses[id] = process
            do { try process.run() }
            catch {
                activeProcesses.removeValue(forKey: id)
                progress.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: .failure("无法启动 FFmpeg：\(error.localizedDescription)"))
            }
        }
    }

    private func ffmpegArguments(source: URL, output: URL, info: VideoInfo, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, trim: ClipRange?, rotation: VideoRotation?, crop: CropRect?, preferHardwarePipeline: Bool, preferHardwareEncoder: Bool) -> [String] {
        // Privacy-first default: never copy source metadata or chapters, which
        // may contain title, author, device, location, or editing information.
        var args = ["-hide_banner", "-nostdin", "-y", "-thread_queue_size", "1024"]
        let hardwarePipeline = preferHardwarePipeline && canUseVideoToolboxPipeline(info: info, preset: preset, rotation: rotation, crop: crop)
        // For H.264/HEVC without CPU-only edits, keep decoded frames inside
        // VideoToolbox all the way to the encoder. This also benefits an
        // original-size conversion: not just resizes.
        if hardwarePipeline {
            args += ["-init_hw_device", "videotoolbox=vt", "-filter_hw_device", "vt", "-hwaccel", "videotoolbox", "-hwaccel_output_format", "videotoolbox_vld"]
        }
        // For lossless trimming, seek before opening the input and copy only the
        // requested duration. This avoids decoding the preceding portion of a
        // long video and makes clipping effectively instantaneous. Stream-copy
        // cuts may begin at the nearest keyframe, as indicated by the editor.
        if let trim, preset == .remux {
            args += ["-ss", ffmpegTime(trim.start), "-i", source.path]
        } else {
            args += ["-i", source.path]
        }
        args += ["-map", "0:v:0?", "-map", "0:a:0?", "-map_metadata", "-1", "-map_chapters", "-1"]
        if let trim {
            if preset == .remux {
                args += ["-t", ffmpegTime(trim.end - trim.start)]
            } else {
                args += ["-ss", ffmpegTime(trim.start), "-to", ffmpegTime(trim.end)]
            }
        }
        let filters = [crop?.filter, rotation?.filter, resolution.filter(sourceHeight: info.height, quality: quality, useVideoToolbox: hardwarePipeline)].compactMap { $0 }
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
        let videoRate = info.outputRate(preset: preset, quality: quality, resolution: resolution), audioRate = info.safeAudioRate
        switch preset {
        case .qualityTop:
            args += preferHardwareEncoder
                ? hardware(codec: "h264_videotoolbox", videoRate: videoRate, audioRate: audioRate, inputAudioCodec: info.audioCodec, keepsVideoToolboxFrames: hardwarePipeline)
                : softwareBitrate(videoRate: videoRate, audioRate: audioRate, inputAudioCodec: info.audioCodec)
        case .h264Cap8:
            args += preferHardwareEncoder
                ? hardware(codec: "h264_videotoolbox", videoRate: videoRate, audioRate: 192_000, inputAudioCodec: info.audioCodec, forceAAC: true, keepsVideoToolboxFrames: hardwarePipeline)
                : softwareBitrate(videoRate: videoRate, audioRate: 192_000, inputAudioCodec: info.audioCodec, forceAAC: true)
        case .smartMP4: preconditionFailure("智能预设必须在探测后解析为具体编码路径")
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

    private func canUseVideoToolboxPipeline(info: VideoInfo, preset: ConversionPreset, rotation: VideoRotation?, crop: CropRect?) -> Bool {
        usesVideoToolboxEncoder(preset)
            && crop == nil
            && rotation == nil
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
    private func outputSummary(_ info: VideoInfo, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution) -> String {
        let sizeLabel = resolution.targetHeight.map { " · \($0)P" } ?? ""
        if preset == .qualityTop {
            return L10n.format("保留源码率 %.1f Mbps%@", Double(info.outputRate(preset: preset, quality: quality, resolution: resolution)) / 1_000_000, sizeLabel)
        }
        if preset == .h264Cap8 { return "H.264 \(String(format: "%.1f", Double(info.outputRate(preset: preset, quality: quality, resolution: resolution)) / 1_000_000)) Mbps · AAC 192k\(sizeLabel)" }
        if preset == .h264Software { return "H.264 · CRF \(quality.crf)\(sizeLabel)" }
        if preset == .remux { return L10n.text("不重新编码") }
        return L10n.format("目标码率 %.1f Mbps", Double(info.outputRate(preset: preset, quality: quality, resolution: resolution)) / 1_000_000) + sizeLabel
    }

    private func consumeProgress(_ text: String, duration: Double?, id: UUID, count: Int) {
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
        if jobs.contains(where: { if case .running(nil) = $0.state { return true }; return false }) { overallProgress = nil; return }
        overallProgress = jobs.reduce(0.0) { sum, item in switch item.state { case .complete, .failed, .cancelled: sum + 1; case .running(let progress), .merging(let progress): sum + (progress ?? 0); case .waiting: sum } } / Double(count)
    }

    private func probe(_ source: URL, ffmpegURL: URL) async -> VideoInfo {
        let probe = ffmpegURL.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard FileManager.default.isExecutableFile(atPath: probe.path) else { return VideoInfo(duration: nil, videoRate: nil, audioRate: nil, width: nil, height: nil, hasVideo: true, videoCodec: nil, audioCodec: nil, frameRate: nil, pixelFormat: nil, audioSampleRate: nil, audioChannels: nil) }
        return await Task.detached {
            let process = Process(), pipe = Pipe(); process.executableURL = probe; process.arguments = ["-v", "error", "-show_entries", "stream=codec_type,codec_name,bit_rate,width,height,r_frame_rate,pix_fmt,sample_rate,channels:format=duration,bit_rate", "-of", "json", source.path]; process.standardOutput = pipe
            do {
                try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
                let response = try JSONDecoder().decode(ProbeResponse.self, from: pipe.fileHandleForReading.readDataToEndOfFile())
                let video = response.streams.first { $0.codecType == "video" }, audio = response.streams.first { $0.codecType == "audio" }
                let videoRate = Int(video?.bitRate ?? "") ?? response.format.flatMap { guard let total = Int($0.bitRate ?? "") else { return nil }; return max(total - (Int(audio?.bitRate ?? "") ?? 0), 1) }
                return VideoInfo(duration: Double(response.format?.duration ?? ""), videoRate: videoRate, audioRate: Int(audio?.bitRate ?? ""), width: video?.width, height: video?.height, hasVideo: video != nil, videoCodec: video?.codecName, audioCodec: audio?.codecName, frameRate: video?.rFrameRate, pixelFormat: video?.pixelFormat, audioSampleRate: audio?.sampleRate, audioChannels: audio?.channels)
            } catch { return VideoInfo(duration: nil, videoRate: nil, audioRate: nil, width: nil, height: nil, hasVideo: true, videoCodec: nil, audioCodec: nil, frameRate: nil, pixelFormat: nil, audioSampleRate: nil, audioChannels: nil) }
        }.value
    }

    private func locateFFmpeg() -> URL? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
    private func uniqueOutput(for source: URL, trim: ClipRange?, rotation: VideoRotation?, crop: CropRect?) -> URL {
        let directory = outputDirectory ?? source.deletingLastPathComponent(), stem = source.deletingPathExtension().lastPathComponent
        var suffix = trim.map { "-trim-\(fileNameTime($0.start))-\(fileNameTime($0.end))" } ?? "-MP4FlowConverted"
        if crop != nil { suffix += "-cropped" }
        if let rotation { suffix += "-\(rotation.fileSuffix)" }
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
    private func friendlyError(_ stderr: String, code: Int32) -> String {
        let text = stderr.lowercased()
        if text.contains("unknown encoder") || text.contains("videotoolbox") && text.contains("not available") { return L10n.text("硬件编码不可用。请改用“兼容优先：H.264 MP4（软件）”。") }
        if text.contains("permission denied") || text.contains("no such file") { return L10n.text("无法读取源文件或写入输出位置，请检查文件与权限。") }
        if text.contains("could not write header") || text.contains("muxer") { return L10n.text("该流无法直接封装为 MP4，请改用 H.264 或 HEVC 转码。") }
        return L10n.format("FFmpeg 转换失败（退出码 %d）。", code)
    }
    private func friendlyMergeError(_ stderr: String, code: Int32) -> String {
        let text = stderr.lowercased()
        if text.contains("non monotonous") || text.contains("invalid data") || text.contains("concat") {
            return L10n.text("片段时间轴或流参数不兼容。请先使用相同预设转换为 MP4 后再合并。")
        }
        if text.contains("permission denied") || text.contains("no such file") {
            return L10n.text("无法读取片段或写入输出位置，请检查文件与权限。")
        }
        return L10n.format("FFmpeg 合并失败（退出码 %d）。", code)
    }
}
