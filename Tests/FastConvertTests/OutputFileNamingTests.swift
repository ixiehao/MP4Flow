import Foundation
import XCTest
@testable import FastConvert

final class OutputFileNamingTests: XCTestCase {
    private let nearLimitStems = [
        String(repeating: "a", count: 248), String(repeating: "片", count: 82),
        String(repeating: "é", count: 124), String(repeating: "Я", count: 124),
        String(repeating: "ñ", count: 124), String(repeating: "映", count: 82),
        String(repeating: "한", count: 82), String(repeating: "e\u{301}", count: 82),
        String(repeating: "🎬", count: 62),
        String(repeating: "한", count: 27),
        String(repeating: "か\u{3099}", count: 41),
        String(repeating: "👩🏽‍💻", count: 16)
    ]

    func testLongNamesKeepCompleteEditSuffixAndExtensionWithoutSplittingCharacters() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for stem in nearLimitStems {
            for suffix in ["-MP4FlowConverted", "-merge", "-trim-000005-000010-cropped-aspect-16x9-rotated-cw-adjusted"] {
                let output = OutputFileNaming.uniqueURL(in: directory, stem: stem, suffix: suffix)
                XCTAssertLessThanOrEqual(output.lastPathComponent.utf8.count, 255)
                XCTAssertTrue(output.lastPathComponent.hasSuffix(suffix + ".mp4"))
                XCTAssertTrue(stem.hasPrefix(String(output.lastPathComponent.dropLast((suffix + ".mp4").count))))
                try Data("valid filename".utf8).write(to: output)
                XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
                XCTAssertLessThanOrEqual(output.lastPathComponent.utf8.count, 255, "The filesystem-normalized URL must still fit after writing")
                XCTAssertEqual(try Data(contentsOf: output), Data("valid filename".utf8))
                // Canonically equivalent spellings intentionally refer to the
                // same filesystem name. Collisions have their own test below.
                try FileManager.default.removeItem(at: output)
            }
        }
    }

    func testCollisionNumbersFitAndNeverReplaceExistingOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stem = String(repeating: "a", count: 248)
        let bytes = Data("existing user output".utf8)
        var outputs: Set<URL> = []
        for number in 1...12 {
            let output = OutputFileNaming.uniqueURL(in: directory, stem: stem, suffix: "-MP4FlowConverted")
            XCTAssertLessThanOrEqual(output.lastPathComponent.utf8.count, 255)
            XCTAssertTrue(output.lastPathComponent.hasSuffix(number == 1 ? "-MP4FlowConverted.mp4" : "-MP4FlowConverted-\(number).mp4"))
            XCTAssertTrue(outputs.insert(output).inserted)
            try bytes.write(to: output)
        }
        for output in outputs { XCTAssertEqual(try Data(contentsOf: output), bytes) }
    }

    func testOrdinaryFilenameIsUnchanged() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(OutputFileNaming.uniqueURL(in: directory, stem: "Family holiday", suffix: "-merge").lastPathComponent,
                       "Family holiday-merge.mp4")
    }

    @MainActor
    func testActualConversionsOfNearLimitMultilingualSourcesPreserveMediaAndExistingOutput() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ffmpeg = try tool()
        let base = directory.appendingPathComponent("fixture.mp4")
        try await Self.makeFixture(base, ffmpeg: ffmpeg)
        let original = try Data(contentsOf: base)
        let outputDirectory = directory.appendingPathComponent("outputs", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let sources = try nearLimitStems.prefix(7).map { stem -> URL in
            let source = directory.appendingPathComponent(stem + ".mp4")
            try FileManager.default.copyItem(at: base, to: source)
            return source
        }
        let existing = OutputFileNaming.uniqueURL(in: outputDirectory, stem: sources[0].deletingPathExtension().lastPathComponent, suffix: "-MP4FlowConverted")
        let sentinel = Data("previous user output must survive".utf8)
        try sentinel.write(to: existing)
        let store = ConverterStore(ffmpegOverride: ffmpeg)
        store.outputDirectory = outputDirectory
        store.items = sources.map { ConversionItem(source: $0) }
        store.start()
        try await waitForStore(store)
        for item in store.items {
            guard case .complete(let output) = item.state else { return XCTFail("Long-name conversion failed: \(item.state)") }
            XCTAssertLessThanOrEqual(output.lastPathComponent.utf8.count, 255)
            let decoded = await FFmpegProcessRunner(executable: ffmpeg, arguments: ["-v", "error", "-i", output.path, "-f", "null", "-"]).run()
            XCTAssertTrue(decoded.succeeded, decoded.standardError)
            XCTAssertEqual(try Data(contentsOf: item.source), original)
        }
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).contains { $0.hasSuffix(".partial.mp4") })
    }

    @MainActor
    func testActualLosslessMergeFromNearLimitSourcePublishesDecodableOutput() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ffmpeg = try tool()
        let source = directory.appendingPathComponent(String(repeating: "a", count: 248) + ".mp4")
        try await Self.makeFixture(source, ffmpeg: ffmpeg)
        let original = try Data(contentsOf: source)
        let second = directory.appendingPathComponent("second.mp4")
        try FileManager.default.copyItem(at: source, to: second)
        let store = ConverterStore(ffmpegOverride: ffmpeg)
        store.outputDirectory = directory
        store.items = [ConversionItem(source: source), ConversionItem(source: second)]
        store.mergeWaitingItems()
        try await waitForStore(store)
        let output = try XCTUnwrap(store.mergeOutput, store.mergeNotice)
        XCTAssertLessThanOrEqual(output.lastPathComponent.utf8.count, 255)
        XCTAssertTrue(output.lastPathComponent.hasSuffix("-merge.mp4"))
        let decoded = await FFmpegProcessRunner(executable: ffmpeg, arguments: ["-v", "error", "-i", output.path, "-f", "null", "-"]).run()
        XCTAssertTrue(decoded.succeeded, decoded.standardError)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: second), original)
    }

    private func tool() throws -> URL {
        let binary = ProcessInfo.processInfo.environment["MP4FLOW_TEST_FFMPEG"].map { URL(fileURLWithPath: $0) }
            ?? DependencyToolResolver.resolve().ffmpeg
        guard let binary, FileManager.default.isExecutableFile(atPath: binary.path),
              FileManager.default.isExecutableFile(atPath: binary.deletingLastPathComponent().appendingPathComponent("ffprobe").path) else {
            throw XCTSkip("FFmpeg and its sibling ffprobe are needed for filename integration")
        }
        return binary
    }

    private static func makeFixture(_ output: URL, ffmpeg: URL) async throws {
        let result = await FFmpegProcessRunner(executable: ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=64x48:rate=8:duration=0.5", "-c:v", "libx264", "-pix_fmt", "yuv420p", output.path]).run()
        XCTAssertTrue(result.succeeded, result.standardError)
        guard result.succeeded else { throw CocoaError(.fileWriteUnknown) }
    }

    @MainActor
    private func waitForStore(_ store: ConverterStore) async throws {
        let deadline = TestDeadline(seconds: 30)
        while store.isBusy && deadline.hasTimeRemaining { try await Task.sleep(for: .milliseconds(20)) }
        if store.isBusy {
            store.cancel()
            XCTFail("Filename regression exceeded its deadline")
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-output-naming-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
