import Foundation
import XCTest
@testable import FastConvert

final class ConverterStoreTests: XCTestCase {
    @MainActor
    func testSoftwareConversionPublishesVerifiedMP4() async throws {
        let ffmpeg = try availableFFmpeg()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mov")
        try makeShortVideo(at: source, ffmpeg: ffmpeg)

        let store = ConverterStore()
        store.preset = .h264Software
        store.outputDirectory = directory
        store.items = [ConversionItem(source: source)]
        store.start()
        store.start() // Repeated clicks must not launch a second worker.
        try await waitForQueue(store)

        guard case .complete(let output) = store.items[0].state else {
            return XCTFail("Expected a complete MP4; got \(store.items[0].state)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertGreaterThan(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
        let leftovers = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".MP4Flow-") && $0.lastPathComponent.hasSuffix(".partial.mp4") }
        XCTAssertTrue(leftovers.isEmpty, "Temporary outputs must be removed after publication")
        let published = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }
        XCTAssertEqual(published.count, 1, "Repeated start must not publish a duplicate")
    }

    @MainActor
    func testUnreadableSourceCanBeRetriedAfterItBecomesAvailable() async throws {
        let ffmpeg = try availableFFmpeg()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("late source.mov")

        let store = ConverterStore()
        store.preset = .h264Software
        store.outputDirectory = directory
        store.items = [ConversionItem(source: source)]
        store.start()
        try await waitForQueue(store)
        guard case .failed = store.items[0].state else {
            return XCTFail("Expected an explicit probe failure")
        }
        XCTAssertEqual(store.items[0].failure?.diagnostic, "probe:unavailable")

        try makeShortVideo(at: source, ffmpeg: ffmpeg)
        store.retryIncomplete()
        store.start()
        try await waitForQueue(store)
        guard case .complete(let output) = store.items[0].state else {
            return XCTFail("Expected retry to complete; got \(store.items[0].state)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testProbeDrainsStreamRichJSONBeforeProcessExit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("probe response.json")
        let video: [String: Any] = ["codec_type": "video", "codec_name": "h264", "width": 64, "height": 48, "r_frame_rate": "8/1"]
        let extraStreams: [[String: Any]] = (0..<5_000).map { _ in ["codec_type": "subtitle", "codec_name": "subrip"] }
        let json = try JSONSerialization.data(withJSONObject: [
            "streams": [video] + extraStreams,
            "format": ["duration": "1.0", "bit_rate": "1000000"]
        ])
        XCTAssertGreaterThan(json.count, 64 * 1_024)
        try json.write(to: source)

        let fakeProbe = directory.appendingPathComponent("fake ffprobe")
        try "#!/bin/sh\nfor source in \"$@\"; do :; done\n/bin/cat \"$source\"\n".write(to: fakeProbe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProbe.path)

        let start = Date()
        let info = await ConverterStore.inspectMedia(at: source, using: fakeProbe)
        XCTAssertTrue(info.probeSucceeded)
        XCTAssertTrue(info.hasVideo)
        XCTAssertEqual(info.width, 64)
        XCTAssertEqual(info.subtitleTrackCount, 5_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "A full pipe must not block ffprobe until its 30-second watchdog")
    }

    @MainActor
    func testTrimCropAndRotationKeepSoftwarePresetAndCorrectGeometry() async throws {
        let ffmpeg = try availableFFmpeg()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("edit.mov")
        try makeShortVideo(at: source, ffmpeg: ffmpeg)

        let store = ConverterStore()
        store.preset = .h264Software
        store.outputDirectory = directory
        let item = ConversionItem(source: source)
        store.items = [item]
        store.scheduleTrim(item, start: 0.125, end: 0.375)
        store.scheduleCrop(item, crop: CropRect(x: 8, y: 4, width: 48, height: 32))
        store.scheduleRotation(item, rotation: .clockwise)
        store.start()
        try await waitForQueue(store)

        guard case .complete(let output) = store.items[0].state else {
            return XCTFail("Expected edited conversion to complete; got \(store.items[0].state)")
        }
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        let dimensions = try probeValue(output, ffprobe: ffprobe, entries: "stream=width,height")
        XCTAssertEqual(dimensions.trimmingCharacters(in: .whitespacesAndNewlines), "32,48")
        let duration = try XCTUnwrap(Double(probeValue(output, ffprobe: ffprobe, entries: "format=duration").trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertGreaterThan(duration, 0.1)
        XCTAssertLessThan(duration, 0.5)
    }

    private func availableFFmpeg() throws -> URL {
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: path),
               FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("ffprobe").path) {
                return URL(fileURLWithPath: path)
            }
        }
        throw XCTSkip("FFmpeg and ffprobe are required for this integration test")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-ConverterStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeShortVideo(at output: URL, ffmpeg: URL) throws {
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=red:s=64x48:r=8:d=0.5", "-c:v", "mpeg4", "-y", output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.generationFailed(process.terminationStatus) }
    }

    private func probeValue(_ source: URL, ffprobe: URL, entries: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = ffprobe
        process.arguments = ["-v", "error", "-show_entries", entries, "-of", "csv=p=0", source.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.probeFailed(process.terminationStatus) }
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor
    private func waitForQueue(_ store: ConverterStore) async throws {
        let deadline = Date().addingTimeInterval(20)
        while store.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if store.isRunning {
            store.cancel()
            XCTFail("Conversion queue did not complete within 20 seconds")
        }
    }
}

private enum FixtureError: Error {
    case generationFailed(Int32)
    case probeFailed(Int32)
}
