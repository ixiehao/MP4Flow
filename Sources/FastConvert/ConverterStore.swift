import AppKit
import AVFoundation
import Darwin
import SwiftUI
import UniformTypeIdentifiers

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
    @Published var preset: ConversionPreset = .smartMP4 { didSet { queueRecovery?.schedule() } }
    @Published var quality: ConversionQuality = .balanced { didSet { queueRecovery?.schedule() } }
    @Published var outputResolution: OutputResolution = .original { didSet { queueRecovery?.schedule() } }
    @Published var smartEnhanceTarget: SmartEnhanceTarget = .p720 { didSet { queueRecovery?.schedule() } }
    @Published var outputDirectory: URL? { didSet { queueRecovery?.schedule() } }
    @Published var isRestoringQueue = false
    @Published var recoveryNotice: QueueRecoveryNotice?
    private var queueRecovery: QueueRecovery?
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
    private var presentationRequests: [UUID: UUID] = [:]
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
    init(ffmpegOverride: URL? = nil, journal: QueueJournal? = nil) {
        self.ffmpegOverride = ffmpegOverride
        if let journal { queueRecovery = QueueRecovery(store: self, journal: journal) }
    }

    func reloadRestoredPresentations() {
        for item in items { loadPresentation(for: item) }
    }

    func saveQueueNow() { queueRecovery?.flush() }

    func prepareForTermination() async {
        saveQueueNow()
        if isRunning || isMerging { cancel() }
        activeProcesses.values.forEach { $0.cancel() }
        for _ in 0..<80 {
            if !isRunning && !isMerging && activeProcesses.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        saveQueueNow()
    }

    func exportInfo(for source: URL) async throws -> VideoInfo {
        guard let binary = locateFFmpeg(), let probe = locateFFprobe(for: binary) else { throw ExportOptionError.inspectionUnavailable }
        let info = await MediaInspector.inspect(at: source, using: probe)
        guard info.probeSucceeded, info.hasVideo else { throw ExportOptionError.inspectionUnavailable }
        return info
    }

    func subtitleBurningAvailable(for itemID: UUID? = nil) async -> Bool {
        guard let binary = locateFFmpeg() else { return false }
        let runner = FFmpegProcessRunner(executable: binary, arguments: ["-hide_banner", "-filters"], configuration: .init(inactivityTimeout: 5, maximumOutputBytes: 1_000_000))
        if let itemID { activeProcesses[itemID] = runner }
        defer { if let itemID { activeProcesses.removeValue(forKey: itemID) } }
        let result = await runner.run()
        guard result.succeeded else { return false }
        return String(decoding: result.standardOutput, as: UTF8.self).split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            return fields.count > 1 && fields[1] == "subtitles"
        }
    }

    func setExportOptions(_ proposed: ExportOptions, for item: ConversionItem) {
        let options = proposed.normalized
        guard !isBusy, let index = items.firstIndex(where: { $0.id == item.id }), items[index].exportOptions != options else { return }
        items[index].exportOptions = options
        items[index].prepareForExport()
        queueRecovery?.schedule()
    }

    var hasWaiting: Bool { items.contains { if case .waiting = $0.state { return true }; return false } }
    var hasCompleted: Bool { items.contains { if case .complete = $0.state { return true }; return false } }
    var hasIncomplete: Bool { items.contains { if case .failed = $0.state { return true }; if case .cancelled = $0.state { return true }; return false } }
    var mergeCandidateCount: Int { items.reduce(into: 0) { if case .waiting = $1.state, $1.trimRange == nil, $1.rotation == nil, $1.crop == nil, $1.aspectRatio == nil, $1.imageAdjustment.isIdentity, $1.exportOptions.isDefault { $0 += 1 } } }
    var mergeDisplayCount: Int { isMerging ? mergeItemIDs.count : mergeCandidateCount }
    var canMerge: Bool { !isBusy && mergeCandidateCount >= 2 }
    var isBusy: Bool { isRunning || isMerging || isRestoringQueue }
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
    var hasTargetSizeItems: Bool { items.contains { $0.exportOptions.targetSizeMB != nil } }
    var usesFixedQuality: Bool { preset.usesFixedQuality && !hasTargetSizeItems }
    var qualityDescription: String {
        if hasTargetSizeItems { return L10n.text("目标体积优先，高画质更慢。") }
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
        guard !isRestoringQueue else { return }
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
        guard !isRestoringQueue else { return false }
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
        for id in completedIDs { presentationRequests.removeValue(forKey: id) }
        items.removeAll {
            if case .complete = $0.state { return true }
            return false
        }
        queueIDs.subtract(completedIDs)
        queueRecovery?.schedule()
        if isRunning { refreshProgress(queueIDs.count) }
    }
    /// Removes queue records only. Source files and generated outputs remain untouched.
    func clearQueue() {
        guard !isBusy else { return }
        presentationQueue.cancelAllOperations()
        presentationRequests.removeAll()
        items.removeAll()
        queueRecovery?.schedule()
        statusText = ""
    }
    func retryIncomplete() {
        guard !isBusy else { return }
        for index in items.indices {
            switch items[index].state {
            case .failed, .cancelled: items[index].prepareForExport()
            default: break
            }
        }
        queueRecovery?.schedule()
    }

    func start() {
        guard !isBusy else { return }
        if case .restored? = recoveryNotice { recoveryNotice = nil }
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
        let sources = items.compactMap { item -> URL? in if case .waiting = item.state, item.trimRange == nil, item.rotation == nil, item.crop == nil, item.aspectRatio == nil, item.imageAdjustment.isIdentity, item.exportOptions.isDefault { return item.source }; return nil }
        mergeItemIDs = items.compactMap { item -> UUID? in if case .waiting = item.state, item.trimRange == nil, item.rotation == nil, item.crop == nil, item.aspectRatio == nil, item.imageAdjustment.isIdentity, item.exportOptions.isDefault { return item.id }; return nil }
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
            guard compatibleMergeIDs.contains(item.id), item.trimRange == nil, item.rotation == nil, item.crop == nil, item.aspectRatio == nil, item.imageAdjustment.isIdentity, item.exportOptions.isDefault else { return false }
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
        presentationRequests.removeValue(forKey: item.id)
        items.removeAll { $0.id == item.id }
        queueIDs.remove(item.id)
        queueRecovery?.schedule()
        if isRunning { refreshProgress(queueIDs.count) }
    }

    func canRemove(_ item: ConversionItem) -> Bool {
        guard let current = items.first(where: { $0.id == item.id }) else { return false }
        switch current.state {
        case .running, .merging: return false
        default: return true
        }
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
        guard ClipRange(start: start, end: end).isValid else { return }
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
        edited.prepareForExport()
        items[index] = edited
        queueRecovery?.schedule()
    }

    private func add(_ urls: [URL]) {
        var knownSources = Set(items.map { canonicalURL($0.source) })
        let additions = urls.compactMap { rawURL -> ConversionItem? in
            let source = canonicalURL(rawURL)
            guard !source.hasDirectoryPath, knownSources.insert(source).inserted else { return nil }
            return ConversionItem(source: source)
        }
        items.append(contentsOf: additions)
        queueRecovery?.schedule()
        for item in additions { loadPresentation(for: item) }
    }

    private func loadPresentation(for item: ConversionItem, preserving facts: VideoPresentation? = nil) {
        let request = UUID()
        presentationRequests[item.id] = request
        presentationQueue.addOperation { [weak self] in
            // Keep the queue's bounded concurrency while loading modern
            // AVFoundation properties asynchronously.
            let completed = DispatchSemaphore(value: 0)
            Task { [weak self] in
                defer { completed.signal() }
                guard await MainActor.run(body: { [weak self] in
                    self?.presentationRequests[item.id] == request
                        && self?.items.contains(where: { $0.id == item.id }) == true
                }) else { return }
                let presentation = await VideoPresentation.load(from: item.source)
                await MainActor.run { [weak self] in
                    guard let store = self,
                          store.presentationRequests[item.id] == request,
                          let index = store.items.firstIndex(where: { $0.id == item.id }) else { return }
                    store.presentationRequests.removeValue(forKey: item.id)
                    store.items[index].presentation = facts?.replacingThumbnail(presentation.thumbnail) ?? presentation
                    store.queueRecovery?.schedule()
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
        recordMergeNotices(infos: infos, preset: isCompatibleMerging ? .h264Hardware : .remux)
        mergeDurations = infos.map(\.duration)
        updateMergeProgress(seconds: 0)

        let output = uniqueMergeOutput(for: sources[0])
        // Write beside the intended result, then publish with a move. This
        // keeps incomplete media out of the user's output list and avoids
        // overwriting a file that appears after the unique-name check.
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".MP4Flow-\(UUID().uuidString).partial.mp4")
        let listURL = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-concat-\(UUID().uuidString).txt")
        do {
            let list = try ConcatManifest.render(sources)
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
            if let failure = await verifyOutput(temporary, ffmpegURL: ffmpegURL, expectedAudioCount: infos[0].audioTrackCount, expectedSubtitleCount: 0) {
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

    private func recordMergeNotices(infos: [VideoInfo], preset: ConversionPreset) {
        for (id, info) in zip(mergeItemIDs, infos) {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].mediaHandling = Self.mediaHandlingNotice(for: info, preset: preset)
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
        queueRecovery?.schedule()
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
        queueRecovery?.schedule()
    }

    private func runMergeFFmpeg(ffmpegURL: URL, listURL: URL, info: VideoInfo, output: URL) async -> ProcessResult {
        await runMergeProcess(
            ffmpegURL: ffmpegURL,
            arguments: MergeCommandBuilder.losslessArguments(listURL: listURL, info: info, output: output),
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
        let plan: CompatibleMergePlan
        do { plan = try CompatibleMergePlan(sources: sources, infos: infos) }
        catch {
            finishMerge(message: error.localizedDescription, output: nil)
            return
        }
        recordMergeNotices(infos: infos, preset: isCompatibleMerging ? .h264Hardware : .remux)
        mergeDurations = infos.map(\.duration)
        updateMergeProgress(seconds: 0)
        let output = uniqueMergeOutput(for: sources[0])
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".MP4Flow-\(UUID().uuidString).partial.mp4")
        statusText = L10n.format("正在兼容合并 %d 个片段 · 统一为 %@", sources.count, plan.target.summary)
        var result = await runCompatibleMergeFFmpeg(ffmpegURL: ffmpegURL, plan: plan, output: temporary)
        // Compatible Merge intentionally normalizes every clip through a CPU
        // filter graph. The encoder can still be hardware accelerated; when a
        // VideoToolbox session cannot be created, retry once with libx264 and
        // the exact same target size, rate limits, and AAC settings.
        if case .retryableFailure(_, .softwareEncoder) = result, !cancellationRequested {
            statusText = L10n.text("硬件编码不可用，正在使用兼容编码重试")
            resetCompatibleMergeProgress()
            result = await runCompatibleMergeFFmpeg(ffmpegURL: ffmpegURL, plan: plan, output: temporary, preferHardwareEncoder: false)
        }
        if case .success = result, !cancellationRequested {
            isVerifyingMerge = true
            statusText = L10n.text("正在验证输出")
            if let failure = await verifyOutput(temporary, ffmpegURL: ffmpegURL, expectedAudioCount: plan.audio.count, expectedSubtitleCount: 0) {
                result = .failure(failure.legacyMessage)
            }
        }
        if cancellationRequested { result = .cancelled }
        switch result {
        case .success:
            do {
                try FileManager.default.moveItem(at: temporary, to: output)
                finishMerge(message: L10n.format("已兼容合并 %d 个片段（统一为 %@）：%@", sources.count, plan.target.summary, output.lastPathComponent), output: output)
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

    private func runCompatibleMergeFFmpeg(ffmpegURL: URL, plan: CompatibleMergePlan, output: URL, preferHardwareEncoder: Bool = true) async -> ProcessResult {
        await runMergeProcess(
            ffmpegURL: ffmpegURL,
            arguments: MergeCommandBuilder.compatibleArguments(plan: plan, output: output, preferHardwareEncoder: preferHardwareEncoder),
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
        queueRecovery?.schedule()
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
        let exportOptions = item.exportOptions
        setPhase(.inspecting, for: id, progress: nil, count: count)
        var info = await probe(source, ffmpegURL: ffmpegURL)
        // A transient file-provider or network-volume read may make ffprobe
        // fail once before the same source is readable. Retry inspection once,
        // without launching an encoder against unknown stream metadata.
        if !info.probeSucceeded && !cancellationRequested && shouldRetryProbe(for: source) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !cancellationRequested { info = await probe(source, ffmpegURL: ffmpegURL) }
        }
        guard let inspectionIndex = items.firstIndex(where: { $0.id == id }) else { return }
        guard !cancellationRequested else {
            items[inspectionIndex].state = .cancelled
            items[inspectionIndex].phase = nil
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
        // Invalidate an earlier thumbnail read before publishing this attempt's
        // authoritative facts. Optional image decoding resumes after the batch;
        // it cannot replace these facts with AVFoundation's partial metadata.
        presentationRequests.removeValue(forKey: id)
        let facts = VideoPresentation.inspected(info, previous: items[inspectionIndex].presentation)
        items[inspectionIndex].presentation = facts
        if facts.thumbnail == nil { loadPresentation(for: items[inspectionIndex], preserving: facts) }
        let exportPlan: ExportPlan
        do {
            let canBurn = exportOptions.subtitles == .burn ? await subtitleBurningAvailable(for: id) : false
            exportPlan = try ExportPlan(options: exportOptions, info: info, trim: trim, preset: preset, canBurnSubtitles: canBurn)
        } catch {
            if cancellationRequested {
                if let index = items.firstIndex(where: { $0.id == id }) {
                    items[index].state = .cancelled
                    items[index].phase = nil
                }
                return
            }
            markFailed(id, failure: ConversionFailure(reasonKey: (error as? ExportOptionError)?.reasonKey ?? "导出设置不可用", solutionKey: "请打开导出设置并重新选择。", diagnostic: "export:invalid-options"), count: count)
            return
        }
        // Capability detection yields to the UI. Clearing completed rows in
        // that interval can shift every array index; identity is the contract.
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !cancellationRequested else {
            items[index].state = .cancelled
            items[index].phase = nil
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
        let compatibleAudio = exportPlan.audio.canCopyAll
        let directlyCompatible = info.canCopyVideoToMP4 && compatibleAudio
        let copyVideoAndEncodeAudio = preset == .smartMP4
            && trim == nil && rotation == nil && crop == nil && aspectRatio == nil && imageAdjustment.isIdentity && !resizeRequiresEncoding
            && info.canCopyVideoToMP4 && !compatibleAudio && exportOptions.targetSizeMB == nil && exportOptions.subtitles != .burn
        let resolvedPreset: ConversionPreset
        if preset == .smartEnhanceUpscale {
            resolvedPreset = preset
        } else if rotation != nil || crop != nil || aspectRatio != nil || !imageAdjustment.isIdentity || resizeRequiresEncoding || exportOptions.targetSizeMB != nil || exportOptions.subtitles == .burn {
            // Edits require re-encoding, but retain an explicitly selected
            // software or HEVC encoder. Only copy/automatic presets need a
            // concrete H.264 encoding path here.
            resolvedPreset = (preset == .remux || preset == .smartMP4) ? .h264Hardware : preset
        } else if trim != nil, directlyCompatible {
            resolvedPreset = .remux
        } else if preset == .smartMP4 {
            resolvedPreset = directlyCompatible || copyVideoAndEncodeAudio ? .remux : .h264Hardware
        } else {
            resolvedPreset = preset
        }
        let effectivePreset = exportPlan.encodingPreset(for: resolvedPreset)
        items[index].failure = nil
        items[index].mediaHandling = Self.mediaHandlingNotice(for: info, preset: effectivePreset, options: exportOptions)
        setPhase(copyVideoAndEncodeAudio ? .audioTranscoding : phase(for: effectivePreset, preferHardwareEncoder: true), for: id, progress: info.duration == nil ? nil : 0, count: count, detail: exportPlan.targetSize.map { L10n.format("目标约 %@", L10n.byteCount($0.targetBytes)) } ?? (copyVideoAndEncodeAudio ? nil : outputSummary(info, preset: effectivePreset, quality: quality, resolution: resolution, sourceHeight: editedGeometry?.height)))
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
            result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment, id: id, count: count, copyVideoAndEncodeAudio: copyVideoAndEncodeAudio, exportPlan: exportPlan)
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
            result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment, id: id, count: count, preferHardwarePipeline: false, exportPlan: exportPlan)
        }
        if case .retryableFailure(_, .softwareEncoder) = result,
           !cancellationRequested,
           effectivePreset != .smartEnhanceUpscale,
           FFmpegCommandBuilder.usesVideoToolboxEncoder(effectivePreset) {
            setPhase(.softwareTranscoding, for: id, progress: nil, count: count, detail: L10n.text("硬件编码不可用，正在使用兼容编码重试"))
            result = await runFFmpeg(ffmpegURL: ffmpegURL, source: source, output: temporary, info: info, preset: effectivePreset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment, id: id, count: count, preferHardwarePipeline: false, preferHardwareEncoder: false, exportPlan: exportPlan)
        }
        if case .success = result, !cancellationRequested {
            setPhase(.verifying, for: id, progress: 0.999, count: count)
            if let verificationFailure = await verifyOutput(temporary, ffmpegURL: ffmpegURL, expectedAspectRatio: aspectRatio?.value ?? info.displayAspectRatio(crop: crop, rotation: rotation), requiresSquarePixels: aspectRatio != nil, expectedAudioCount: exportOptions.audioCount(in: info), expectedSubtitleCount: exportOptions.subtitles == .keep ? 1 : 0) {
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
                items[current].outputFileSize = (try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                items[current].phase = nil
                saveQueueNow()
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
    nonisolated static func mediaHandlingNotice(for info: VideoInfo, preset: ConversionPreset, options: ExportOptions = ExportOptions()) -> MediaHandlingNotice? {
        guard info.probeSucceeded, info.hasVideo, info.videoTrackCount > 0 else {
            return MediaHandlingNotice(issues: [.unconfirmed])
        }
        var issues: [MediaHandlingNotice.Issue] = []
        if info.videoTrackCount > 1 {
            issues.append(.extraVideo(info.videoTrackCount))
        }
        if info.audioTrackCount > 1 && options.audio == .first {
            issues.append(.extraAudio(info.audioTrackCount))
        }
        if info.subtitleTrackCount > 0 && options.subtitles == .none {
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
        if message.lowercased().contains("no such filter") && message.lowercased().contains("subtitles") {
            return ConversionFailure(reasonKey: ExportOptionError.missingRenderer.reasonKey, solutionKey: "可选择保留字幕，或安装支持 libass 的 FFmpeg。", diagnostic: "ffmpeg:subtitle-renderer")
        }
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
    private func verifyOutput(_ output: URL, ffmpegURL: URL, expectedAspectRatio: Double? = nil, requiresSquarePixels: Bool = false, expectedAudioCount: Int? = nil, expectedSubtitleCount: Int? = nil) async -> ConversionFailure? {
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
        if (expectedAudioCount != nil && info.audioTrackCount != expectedAudioCount) || (expectedSubtitleCount != nil && info.subtitleTrackCount != expectedSubtitleCount) {
            return ConversionFailure(reasonKey: "输出音轨或字幕不完整", solutionKey: "请检查导出设置后重试。", diagnostic: "verify:stream-selection")
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

    private func runFFmpeg(ffmpegURL: URL, source: URL, output: URL, info: VideoInfo, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, trim: ClipRange?, rotation: VideoRotation?, crop: CropRect?, aspectRatio: DisplayAspectRatio?, imageAdjustment: ImageAdjustment, id: UUID, count: Int, copyVideoAndEncodeAudio: Bool = false, preferHardwarePipeline: Bool = true, preferHardwareEncoder: Bool = true, exportPlan: ExportPlan) async -> ProcessResult {
        let exportOptions = exportPlan.options
        guard !cancellationRequested else { return .cancelled }
        let generation = UUID()
        let usedHardwarePipeline = preferHardwarePipeline && exportOptions.subtitles != .burn && FFmpegCommandBuilder.canUseVideoToolboxPipeline(info: info, preset: preset, crop: crop, imageAdjustment: imageAdjustment)
        let usedHardwareEncoder = preferHardwareEncoder && FFmpegCommandBuilder.usesVideoToolboxEncoder(preset)
        progressGeneration[id] = generation
        progressBuffers[id] = nil
        progressTimes[id] = nil
        lastProgressUpdate[id] = nil
        let runner = FFmpegProcessRunner(
            executable: ffmpegURL,
            arguments: FFmpegCommandBuilder.arguments(source: source, output: output, info: info, preset: preset, quality: quality, resolution: resolution, trim: trim, rotation: rotation, crop: crop, aspectRatio: aspectRatio, imageAdjustment: imageAdjustment, copyVideoAndEncodeAudio: copyVideoAndEncodeAudio, preferHardwarePipeline: preferHardwarePipeline, preferHardwareEncoder: preferHardwareEncoder, exportPlan: exportPlan),
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
            return MediaInspector.unavailable()
        }
        guard !cancellationRequested else { return MediaInspector.unavailable() }
        let id = UUID()
        let runner = FFmpegProcessRunner(
            executable: probe,
            arguments: MediaInspector.arguments(for: source),
            configuration: FFmpegProcessRunner.Configuration(inactivityTimeout: 30)
        )
        activeProcesses[id] = runner
        defer { activeProcesses.removeValue(forKey: id) }
        return await MediaInspector.inspect(at: source, using: probe, runner: runner)
    }

    private func locateFFmpeg() -> URL? {
        if let ffmpegOverride {
            return FileManager.default.isExecutableFile(atPath: ffmpegOverride.path) ? ffmpegOverride : nil
        }
        let candidate = DependencyToolResolver.resolve().ffmpeg
        return candidate.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
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
        return OutputFileNaming.uniqueURL(in: directory, stem: stem, suffix: suffix)
    }
    private func uniqueMergeOutput(for firstSource: URL) -> URL {
        let directory = outputDirectory ?? firstSource.deletingLastPathComponent()
        return OutputFileNaming.uniqueURL(in: directory, stem: firstSource.deletingPathExtension().lastPathComponent, suffix: "-merge")
    }
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
