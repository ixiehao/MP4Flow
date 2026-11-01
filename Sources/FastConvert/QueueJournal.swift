import Foundation

enum QueueRecoveryNotice: Equatable {
    case restoring, restored(Int), recordPreserved, saveFailed
    var isError: Bool { self == .recordPreserved || self == .saveFailed }
    var message: String {
        switch self {
        case .restoring: L10n.text("正在恢复上次队列…")
        case .restored(let count): L10n.format("已恢复 %d 个任务，点击开始继续。", count)
        case .recordPreserved: L10n.text("无法恢复上次队列，原记录已保留。")
        case .saveFailed: L10n.text("队列保存失败，请检查磁盘空间和权限。")
        }
    }
}

/// Local-only journal. No translated status, thumbnails or transient progress.
struct QueueSnapshot: Codable, Equatable, Sendable {
    var version = 1
    let preset: String
    let quality: String
    let resolution: String
    let enhanceTarget: Int
    let outputDirectory: URL?
    let jobs: [Job]

    struct Job: Codable, Equatable, Sendable {
        let id: UUID
        let source: URL
        let output: URL?
        let outputBytes: Int64?
        let trim: [Double]?
        let crop: [Int]?
        let aspect: [Int]?
        let rotation: String?
        let brightness: Int
        let shadows: Int
        let denoise: Bool
        let options: ExportOptions
        let duration: Double?
        let width: Int?
        let height: Int?
        let sourceBytes: Int64?
        let notice: MediaHandlingNotice?

        init(_ item: ConversionItem) {
            id = item.id; source = item.source
            if case .complete(let url) = item.state { output = url } else { output = nil }
            outputBytes = output == nil ? nil : item.outputFileSize
            trim = item.trimRange.map { [$0.start, $0.end] }
            crop = item.crop.map { [$0.x, $0.y, $0.width, $0.height] }
            aspect = item.aspectRatio.map { [$0.width, $0.height] }
            rotation = item.rotation?.rawValue
            brightness = item.imageAdjustment.brightness; shadows = item.imageAdjustment.shadows; denoise = item.imageAdjustment.denoise
            options = item.exportOptions
            duration = item.presentation?.duration.isFinite == true ? item.presentation?.duration : nil
            width = item.presentation?.width; height = item.presentation?.height; sourceBytes = item.presentation?.fileSize
            notice = item.mediaHandling
        }

        func restored() throws -> ConversionItem {
            guard source.isFileURL, output?.isFileURL != false else { throw JournalError.invalidRecord }
            if let trim { guard trim.count == 2, ClipRange(start: trim[0], end: trim[1]).isValid else { throw JournalError.invalidRecord } }
            if let crop { guard crop.count == 4, crop.allSatisfy({ (0...1_000_000).contains($0) }), crop[2] >= 2, crop[3] >= 2 else { throw JournalError.invalidRecord } }
            if let aspect { guard aspect.count == 2, DisplayAspectRatio(width: aspect[0], height: aspect[1]) != nil else { throw JournalError.invalidRecord } }
            if let size = options.targetSizeMB { guard size.isFinite, (1...100_000).contains(size) else { throw JournalError.invalidRecord } }
            if let rotation { guard VideoRotation(rawValue: rotation) != nil else { throw JournalError.invalidRecord } }
            if let index = options.audioStreamIndex { guard index >= 0 else { throw JournalError.invalidRecord } }
            if let index = options.subtitleStreamIndex { guard index >= 0 else { throw JournalError.invalidRecord } }
            if let duration { guard duration.isFinite, duration >= 0, duration < Double(Int.max / 2) else { throw JournalError.invalidRecord } }
            var item = ConversionItem(id: id, source: source)
            item.state = output.map(ConversionState.complete) ?? .waiting
            item.outputFileSize = output == nil ? nil : outputBytes
            item.trimRange = trim.map { ClipRange(start: $0[0], end: $0[1]) }
            item.crop = crop.map { CropRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
            item.aspectRatio = aspect.flatMap { DisplayAspectRatio(width: $0[0], height: $0[1]) }
            item.rotation = rotation.flatMap(VideoRotation.init(rawValue:))
            item.imageAdjustment = ImageAdjustment(brightness: brightness, shadows: shadows, denoise: denoise)
            item.exportOptions = options.normalized
            item.mediaHandling = notice
            if let duration { item.presentation = VideoPresentation(duration: duration, fileSize: sourceBytes, thumbnail: nil, width: width, height: height) }
            return item
        }
    }

    @MainActor init(store: ConverterStore) {
        preset = store.preset.rawValue; quality = store.quality.rawValue; resolution = store.outputResolution.rawValue
        enhanceTarget = store.smartEnhanceTarget.rawValue; outputDirectory = store.outputDirectory
        jobs = store.items.map(Job.init)
    }

    func restoredJobs() throws -> [ConversionItem] {
        guard version == 1, jobs.count <= 10_000, outputDirectory?.isFileURL != false,
              Set(jobs.map(\.id)).count == jobs.count else { throw JournalError.invalidRecord }
        return try jobs.map { try $0.restored() }
    }
}

enum JournalError: Error { case invalidRecord, tooLarge }

final class QueueJournal: @unchecked Sendable {
    let url: URL
    private let io = DispatchQueue(label: "com.ixiehao.mp4flow.queue-journal", qos: .utility)
    private var lastWritten: QueueSnapshot?
    private var writesBlocked = false
    init(url: URL) { self.url = url }
    static var live: QueueJournal {
        QueueJournal(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(storageFolder(bundleIdentifier: Bundle.main.bundleIdentifier), isDirectory: true).appendingPathComponent("queue-v1.json"))
    }
    /// QA and development bundles must never read or replace a user's queue.
    static func storageFolder(bundleIdentifier: String?) -> String {
        guard let bundleIdentifier else { return "MP4Flow-Development" }
        if bundleIdentifier == "com.ixiehao.mp4flow" { return "MP4Flow" }
        let safe = bundleIdentifier.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return "MP4Flow-" + String(safe.prefix(160))
    }

    func load() async -> (snapshot: QueueSnapshot?, recoveredError: Bool) {
        await withCheckedContinuation { continuation in
            io.async {
                guard FileManager.default.fileExists(atPath: self.url.path) else { continuation.resume(returning: (nil, false)); return }
                do {
                    let file = try FileHandle(forReadingFrom: self.url)
                    defer { try? file.close() }
                    let data = try file.read(upToCount: 20_000_001) ?? Data()
                    guard data.count <= 20_000_000 else { throw JournalError.tooLarge }
                    let snapshot = try JSONDecoder().decode(QueueSnapshot.self, from: data)
                    _ = try snapshot.restoredJobs()
                    self.lastWritten = snapshot
                    continuation.resume(returning: (snapshot, false))
                } catch {
                    // Preserve malformed/future-version records before permitting a new journal.
                    let backup = self.url.deletingLastPathComponent().appendingPathComponent("queue-recovery-\(UUID().uuidString).json")
                    do { try FileManager.default.moveItem(at: self.url, to: backup); continuation.resume(returning: (nil, true)) }
                    catch { self.writesBlocked = true; continuation.resume(returning: (nil, true)) }
                }
            }
        }
    }

    func save(_ snapshot: QueueSnapshot, completion: @escaping @Sendable (Bool) -> Void) {
        io.async { completion(self.write(snapshot)) }
    }
    func flush(_ snapshot: QueueSnapshot) -> Bool { io.sync { write(snapshot) } }
    private func write(_ snapshot: QueueSnapshot) -> Bool {
        guard !writesBlocked else { return false }
        if lastWritten == snapshot && FileManager.default.fileExists(atPath: url.path) { return true }
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= 20_000_000 else { return false }
            try PrivateAtomicFile.write(data, to: url)
            lastWritten = snapshot
            return true
        } catch { return false }
    }
}

@MainActor final class QueueRecovery {
    private let journal: QueueJournal
    private weak var store: ConverterStore?
    private var scheduled: DispatchWorkItem?
    private var restored = false
    private var saveGeneration = UUID()

    init(store: ConverterStore, journal: QueueJournal) {
        self.store = store; self.journal = journal
        store.isRestoringQueue = true
        store.recoveryNotice = .restoring
        Task { [weak self] in
            let result = await journal.load()
            guard let self, let store = self.store else { return }
            store.recoveryNotice = nil
            if let saved = result.snapshot, let jobs = try? saved.restoredJobs() {
                store.preset = ConversionPreset(rawValue: saved.preset) ?? .smartMP4
                store.quality = ConversionQuality(rawValue: saved.quality) ?? .balanced
                store.outputResolution = OutputResolution(rawValue: saved.resolution) ?? .original
                store.smartEnhanceTarget = SmartEnhanceTarget(rawValue: saved.enhanceTarget) ?? .p720
                store.outputDirectory = saved.outputDirectory
                store.items = jobs
                let unfinished = jobs.filter { if case .waiting = $0.state { true } else { false } }.count
                if unfinished > 0 { store.recoveryNotice = .restored(unfinished) }
            }
            if result.recoveredError { store.recoveryNotice = .recordPreserved }
            self.restored = true
            store.isRestoringQueue = false
            store.reloadRestoredPresentations()
            self.schedule()
        }
    }
    func schedule() {
        guard restored, scheduled == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let store = self.store else { return }
            self.scheduled = nil
            let generation = UUID()
            self.saveGeneration = generation
            self.journal.save(QueueSnapshot(store: store)) { [weak self] success in
                Task { @MainActor in
                    guard let self, self.saveGeneration == generation else { return }
                    if !success { self.store?.recoveryNotice = .saveFailed }
                    else if self.store?.recoveryNotice == .saveFailed { self.store?.recoveryNotice = nil }
                }
            }
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func flush() {
        guard restored, let store else { return }
        scheduled?.cancel(); scheduled = nil
        saveGeneration = UUID()
        if !journal.flush(QueueSnapshot(store: store)) { store.recoveryNotice = .saveFailed }
        else if store.recoveryNotice == .saveFailed { store.recoveryNotice = nil }
    }
}
