import Foundation
import AppKit
import XCTest
@testable import FastConvert

final class StateStorageAuditTests: XCTestCase {
    func testProbeEstimateSubtractsAllAudioBitratesAndDetectsMixedCodecs() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("probe.json"), probe = directory.appendingPathComponent("ffprobe")
        try Data(#"{"streams":[{"index":0,"codec_type":"video","codec_name":"h264","width":320,"height":240},{"index":1,"codec_type":"audio","codec_name":"aac","bit_rate":"64000"},{"index":2,"codec_type":"audio","codec_name":"ac3","bit_rate":"128000"}],"format":{"duration":"1","bit_rate":"1192000"}}"#.utf8).write(to: source)
        try "#!/bin/sh\nfor argument in \"$@\"; do :; done\nexec /bin/cat \"$argument\"\n".write(to: probe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: probe.path)
        let info = await MediaInspector.inspect(at: source, using: probe)
        XCTAssertEqual(info.videoRate, 1_000_000)
        XCTAssertEqual(info.audioTracks.count, 2)
        XCTAssertFalse(info.canDirectRemuxToMP4, "Checking the first AAC track alone would miss the second AC3 track")
    }

    @MainActor func testUnchangedJournalIsRecreatedIfItsFileWasRemoved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConverterStore(); store.items = [ConversionItem(source: directory.appendingPathComponent("original.mp4"))]
        let snapshot = QueueSnapshot(store: store)
        let journal = QueueJournal(url: directory.appendingPathComponent("queue.json"))
        XCTAssertTrue(journal.flush(snapshot))
        try FileManager.default.removeItem(at: journal.url)
        XCTAssertTrue(journal.flush(snapshot))
        XCTAssertEqual(try JSONDecoder().decode(QueueSnapshot.self, from: Data(contentsOf: journal.url)), snapshot)
    }
    func testRestoredPresentationBecomesDifferentWhenItsThumbnailLoads() {
        let cached = VideoPresentation(duration: 1, fileSize: 100, thumbnail: nil, width: 100, height: 100)
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let loaded = VideoPresentation(duration: 1, fileSize: 100, thumbnail: image, width: 100, height: 100)
        XCTAssertNotEqual(cached, loaded)
        XCTAssertEqual(loaded, VideoPresentation(duration: 1, fileSize: 100, thumbnail: image, width: 100, height: 100))
    }
    @MainActor func testStaleWaitingRowCannotRemoveTheActiveWorker() {
        let store = ConverterStore()
        let stale = ConversionItem(source: URL(fileURLWithPath: "/tmp/original.mp4"))
        store.items = [stale]
        store.items[0].state = .running(0.25)
        XCTAssertFalse(store.canRemove(stale))
        store.remove(stale)
        XCTAssertEqual(store.items.count, 1)
        store.items[0].state = .merging(0.5)
        store.remove(stale)
        XCTAssertEqual(store.items.count, 1)
        store.items[0].state = .waiting
        store.remove(stale)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.canRemove(stale))
    }
    @MainActor func testEveryEditAndRetryClearsResultFactsAsOneTransition() {
        let store = ConverterStore()
        let edits: [(ConversionItem) -> Void] = [
            { store.scheduleTrim($0, start: 1, end: 2) },
            { store.scheduleCrop($0, crop: CropRect(x: 0, y: 0, width: 100, height: 80)) },
            { store.scheduleRotation($0, rotation: .clockwise) },
            { store.scheduleFrameEdits($0, crop: nil, aspectRatio: nil, imageAdjustment: ImageAdjustment(brightness: 10, shadows: 0)) },
            { store.setExportOptions(ExportOptions(audio: .none), for: $0) },
            { _ in store.retryIncomplete() }
        ]
        for (offset, edit) in edits.enumerated() {
            var item = ConversionItem(source: URL(fileURLWithPath: "/tmp/retained-original.mp4"))
            item.state = offset == edits.count - 1 ? .failed("old failure") : .complete(URL(fileURLWithPath: "/tmp/retained-output.mp4"))
            item.outputFileSize = 987_654; item.phase = .verifying
            item.failure = ConversionFailure(reasonKey: "old", solutionKey: "old", diagnostic: nil)
            item.mediaHandling = MediaHandlingNotice(issues: [.unconfirmed])
            store.items = [item]; edit(item)
            XCTAssertEqual(store.items[0].id, item.id)
            XCTAssertEqual(store.items[0].state, .waiting)
            XCTAssertNil(store.items[0].outputFileSize)
            XCTAssertNil(store.items[0].phase)
            XCTAssertNil(store.items[0].failure)
            XCTAssertNil(store.items[0].mediaHandling)
        }
    }

    func testAtomicReplacementPreservesOldReadersAndCreatesOnlyPrivateFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("queue.json")
        let before = Data(repeating: 1, count: 200_000), after = Data(repeating: 2, count: 250_000)
        try PrivateAtomicFile.write(before, to: destination)
        let reader = try FileHandle(forReadingFrom: destination)
        defer { try? reader.close() }
        try PrivateAtomicFile.write(after, to: destination)
        XCTAssertEqual(reader.readDataToEndOfFile(), before, "An existing reader must never observe truncation or mixed generations")
        XCTAssertEqual(try Data(contentsOf: destination), after)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["queue.json"])
        XCTAssertThrowsError(try PrivateAtomicFile.write(after, to: directory))
        XCTAssertEqual(try Data(contentsOf: destination), after)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["queue.json"])
    }

    @MainActor func testInvalidRotationRecordIsBackedUpWithoutLosingOriginalBytes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConverterStore(); store.items = [ConversionItem(source: directory.appendingPathComponent("source.mp4"))]
        let data = try JSONEncoder().encode(QueueSnapshot(store: store))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var jobs = try XCTUnwrap(object["jobs"] as? [[String: Any]])
        jobs[0]["rotation"] = "invalid-future-rotation"; object["jobs"] = jobs
        let original = try JSONSerialization.data(withJSONObject: object)
        let path = directory.appendingPathComponent("queue.json"); try original.write(to: path)
        let loaded = await QueueJournal(url: path).load()
        XCTAssertTrue(loaded.recoveredError); XCTAssertNil(loaded.snapshot)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testExtremeAndStaleTrimRangesAreRejectedBeforeBuildingCommands() throws {
        let info = VideoInfo(duration: 10, videoRate: Int.max, audioRate: nil, width: Int.max, height: Int.max, hasVideo: true, videoCodec: "h264", audioCodec: nil, frameRate: "25/1", pixelFormat: "yuv420p", audioSampleRate: nil, audioChannels: nil, audioTrackCount: 0, subtitleTrackCount: 0, colorTransfer: nil, probeSucceeded: true)
        XCTAssertEqual(info.fallbackRate, 10_000_000)
        XCTAssertLessThanOrEqual(info.outputRate(preset: .h264Hardware, quality: .high, resolution: .original), 100_000_000)
        for range in [ClipRange(start: 0, end: .greatestFiniteMagnitude), ClipRange(start: 0, end: 20), ClipRange(start: .nan, end: 10)] {
            XCTAssertThrowsError(try ExportPlan(options: ExportOptions(), info: info, trim: range, preset: .smartMP4, canBurnSubtitles: false))
        }
        XCTAssertNil(MergeCommandBuilder.target([]))
        XCTAssertThrowsError(try CompatibleMergePlan(sources: [], infos: []))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-state-audit-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
