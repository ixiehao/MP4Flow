import Foundation
import XCTest
@testable import FastConvert

final class ExportRecoveryTests: XCTestCase {
    func testDevelopmentAndQAStorageCannotOverlapProductionQueue() {
        XCTAssertEqual(QueueJournal.storageFolder(bundleIdentifier: "com.ixiehao.mp4flow"), "MP4Flow")
        XCTAssertNotEqual(QueueJournal.storageFolder(bundleIdentifier: nil), "MP4Flow")
        XCTAssertNotEqual(QueueJournal.storageFolder(bundleIdentifier: "com.ixiehao.mp4flow.exportqa"), "MP4Flow")
        XCTAssertFalse(QueueJournal.storageFolder(bundleIdentifier: "../qa/test").contains("/"))
    }

    func testExportErrorsAndSectionTitlesExistInEveryCatalog() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("AppResources")
        for language in AppLanguage.allCases {
            let url = resources.appendingPathComponent(language.rawValue + ".lproj/Localizable.strings")
            let catalog = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
            let errorKeys = ExportOptionError.allCases.map(\.reasonKey)
            for key in errorKeys + ["目标体积", "音轨", "字幕", "未检测到字幕", "烧录后字幕无法关闭；需要支持 libass 的 FFmpeg。", "输出不保留字幕；可按需选择。", "保留文字字幕时样式可能简化；未选中的字幕不输出。"] {
                XCTAssertNotNil(catalog[key], "Missing \(language.rawValue): \(key)")
                if language != .chinese && errorKeys.contains(key) { XCTAssertNotEqual(catalog[key], key) }
            }
        }
    }

    @MainActor
    func testClearCompletedPersistsOneThroughFourUnfinishedItems() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for count in 1...4 {
            let journal = QueueJournal(url: directory.appendingPathComponent("queue-\(count).json"))
            let store = ConverterStore(journal: journal)
            try await awaitRecovery(store)
            store.items = (0..<8).map { index in
                var item = ConversionItem(source: directory.appendingPathComponent("source-\(index).mov"))
                if index < 8 - count { item.state = .complete(directory.appendingPathComponent("done-\(index).mp4")) }
                else { item.state = .running(0.25) }
                return item
            }
            let survivors = store.items.suffix(count).map(\.id)
            store.clearCompleted(); store.saveQueueNow()
            let recovered = ConverterStore(journal: journal)
            try await awaitRecovery(recovered)
            XCTAssertEqual(recovered.items.map(\.id), survivors)
            XCTAssertTrue(recovered.items.allSatisfy { $0.state == .waiting })
            XCTAssertFalse(recovered.isRunning)
            store.items = []; store.saveQueueNow()
            recovered.items = []; recovered.saveQueueNow()
        }
    }

    @MainActor
    func testSaveFailureIsReportedAndDoesNotOverwriteExistingFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        let original = Data("preserve me".utf8)
        try original.write(to: blocker)
        let store = ConverterStore(journal: QueueJournal(url: blocker.appendingPathComponent("queue.json")))
        try await awaitRecovery(store)
        store.items = [ConversionItem(source: directory.appendingPathComponent("source.mp4"))]
        store.saveQueueNow()
        XCTAssertEqual(store.recoveryNotice, .saveFailed)
        XCTAssertEqual(store.recoveryNotice?.message, L10n.text("队列保存失败，请检查磁盘空间和权限。"))
        XCTAssertEqual(try Data(contentsOf: blocker), original)
    }
    func testTargetBudgetAccountsForEveryAudioTrackAndRejectsInvalidValues() throws {
        let silent = try TargetSizePlan(megabytes: 10, duration: 60, audioTracks: 0)
        let stereo = try TargetSizePlan(megabytes: 10, duration: 60, audioTracks: 2)
        XCTAssertEqual(silent.videoRate - stereo.videoRate, 256_000)
        XCTAssertEqual(stereo.targetBytes, 10_000_000)
        XCTAssertEqual(stereo.audioRatePerTrack, 128_000)
        let generous = try TargetSizePlan(megabytes: 100, duration: 4, audioTracks: 1, sourceVideoRate: 2_000_000)
        XCTAssertEqual(generous.videoRate, 2_000_000, "A generous target must not inflate the source bitrate")
        for size in [Double.nan, .infinity, -1, 0, 0.5, 100_001] {
            XCTAssertThrowsError(try TargetSizePlan(megabytes: size, duration: 60, audioTracks: 1))
        }
        for duration in [Double.nan, .infinity, -1, 0] {
            XCTAssertThrowsError(try TargetSizePlan(megabytes: 10, duration: duration, audioTracks: 1))
        }
        XCTAssertThrowsError(try TargetSizePlan(megabytes: 1, duration: 7_200, audioTracks: 1))
    }

    @MainActor
    func testSnapshotRestoresEditsOrderIdentityAndCompletedOutputsWithoutAutoStarting() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("private original.mov")
        let completed = directory.appendingPathComponent("already complete.mp4")
        try Data("keep completed bytes".utf8).write(to: completed)
        let store = ConverterStore()
        store.preset = .hevcHardware; store.quality = .high; store.outputResolution = .p720
        store.outputDirectory = directory
        store.items = (0..<8).map { index in
            var item = ConversionItem(source: source)
            item.state = index < 4 ? .complete(completed) : (index == 4 ? .running(0.4) : (index == 5 ? .failed("ignored display language") : .waiting))
            item.trimRange = ClipRange(start: 1.25, end: 8.5)
            item.crop = CropRect(x: 2, y: 4, width: 120, height: 80)
            item.aspectRatio = DisplayAspectRatio(width: 4, height: 3)
            item.rotation = .clockwise
            item.imageAdjustment = ImageAdjustment(brightness: 10, shadows: 20, denoise: true)
            item.exportOptions = ExportOptions(targetSizeMB: 8, audio: .selected, audioStreamIndex: 2, subtitles: .keep, subtitleStreamIndex: 3)
            item.mediaHandling = MediaHandlingNotice(issues: [.chapters(2)])
            return item
        }
        let snapshot = QueueSnapshot(store: store)
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("ignored display language"))
        let journal = QueueJournal(url: directory.appendingPathComponent("journal/queue.json"))
        XCTAssertTrue(journal.flush(snapshot))
        let restored = ConverterStore(journal: journal)
        try await awaitRecovery(restored)
        XCTAssertFalse(restored.isRunning)
        XCTAssertEqual(restored.items.map(\.id), store.items.map(\.id))
        XCTAssertEqual(restored.preset, .hevcHardware)
        XCTAssertEqual(restored.outputResolution, .p720)
        XCTAssertEqual(restored.items[7].exportOptions, store.items[7].exportOptions)
        XCTAssertEqual(restored.items[7].imageAdjustment, store.items[7].imageAdjustment)
        XCTAssertEqual(restored.items[7].crop, store.items[7].crop)
        XCTAssertEqual(restored.items[7].trimRange, store.items[7].trimRange)
        XCTAssertEqual(restored.items[7].aspectRatio, store.items[7].aspectRatio)
        XCTAssertEqual(restored.items[7].rotation, .clockwise)
        XCTAssertEqual(restored.items[4].state, .waiting)
        XCTAssertEqual(restored.items[5].state, .waiting)
        XCTAssertEqual(restored.items[0].state, .complete(completed))
        XCTAssertEqual(restored.items[0].mediaHandling, store.items[0].mediaHandling)
        restored.clearCompleted()
        restored.saveQueueNow()
        let remaining = await journal.load().snapshot
        XCTAssertEqual(remaining?.jobs.count, 4)
        XCTAssertEqual(try Data(contentsOf: completed), Data("keep completed bytes".utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: journal.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        restored.items.removeAll(); restored.saveQueueNow()
    }

    @MainActor
    func testProgressChangesDoNotRewriteJournalFactsAndInactiveChoicesNormalize() throws {
        let store = ConverterStore()
        var item = ConversionItem(source: URL(fileURLWithPath: "/tmp/fixture.mp4"))
        item.state = .running(0.1); store.items = [item]
        let first = QueueSnapshot(store: store)
        store.items[0].state = .running(0.9)
        XCTAssertEqual(first, QueueSnapshot(store: store))
        store.setExportOptions(ExportOptions(audioStreamIndex: 9, subtitleStreamIndex: 99), for: item)
        XCTAssertTrue(store.items[0].exportOptions.isDefault)
        XCTAssertEqual(store.items[0].state, .running(0.9), "Inactive selector IDs must not reschedule a completed/working choice")
    }

    @MainActor
    func testMalformedAndFutureRecordsArePreservedBeforeStartingNewJournal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConverterStore()
        for bytes in [Data("not json".utf8), try JSONEncoder().encode(futureSnapshot(store))] {
            let location = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            let url = location.appendingPathComponent("queue.json")
            try bytes.write(to: url)
            let journal = QueueJournal(url: url)
            let result = await journal.load()
            XCTAssertTrue(result.recoveredError)
            XCTAssertNil(result.snapshot)
            let backups = try FileManager.default.contentsOfDirectory(at: location, includingPropertiesForKeys: nil)
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: backups[0]), bytes)
            XCTAssertTrue(journal.flush(QueueSnapshot(store: store)))
        }
    }

    @MainActor private func futureSnapshot(_ store: ConverterStore) -> QueueSnapshot {
        var snapshot = QueueSnapshot(store: store); snapshot.version = 999; return snapshot
    }
    @MainActor private func awaitRecovery(_ store: ConverterStore) async throws {
        let deadline = TestDeadline(seconds: 5)
        while store.isRestoringQueue && deadline.hasTimeRemaining { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(store.isRestoringQueue)
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-export-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
