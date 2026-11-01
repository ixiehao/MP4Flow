import Foundation
import XCTest
@testable import FastConvert

@MainActor final class ExportMediaTests: XCTestCase {
    private var ffmpeg: URL {
        if let override = ProcessInfo.processInfo.environment["MP4FLOW_TEST_FFMPEG"] { return URL(fileURLWithPath: override) }
        return DependencyToolResolver.resolve().ffmpeg ?? URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    }
    private var ffprobe: URL { ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe") }

    func testSelectedAudioAndTextSubtitleKeepVideoPacketsAndLanguages() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await fixture(directory)
        let before = try Data(contentsOf: source)
        let info = try await ConverterStore(ffmpegOverride: ffmpeg).exportInfo(for: source)
        XCTAssertEqual(info.audioTracks.map(\.language), ["eng", "jpn"])
        XCTAssertEqual(info.subtitleTracks.map(\.language), ["spa"])
        let selected = ExportOptions(audio: .selected, audioStreamIndex: info.audioTracks[1].index, subtitles: .keep, subtitleStreamIndex: info.subtitleTracks[0].index)
        let store = try await converted(source, options: selected)
        let output = try completedOutput(store)
        let result = try await store.exportInfo(for: output)
        XCTAssertEqual(result.audioTracks.map(\.language), ["jpn"])
        XCTAssertEqual(result.subtitleTracks.map(\.language), ["spa"])
        XCTAssertEqual(result.subtitleTracks.first?.codec, "mov_text")
        let originalVideo = try await packetHashes(source, stream: "v:0"), exportedVideo = try await packetHashes(output, stream: "v:0")
        let originalAudio = try await packetHashes(source, stream: "a:1"), exportedAudio = try await packetHashes(output, stream: "a:0")
        XCTAssertEqual(originalVideo, exportedVideo)
        XCTAssertEqual(originalAudio, exportedAudio)
        let subtitle = try await run(ffmpeg, ["-v", "error", "-i", output.path, "-map", "0:s:0", "-f", "srt", "-"])
        XCTAssertTrue(String(decoding: subtitle, as: UTF8.self).contains("Subtitle visible"))
        _ = try await run(ffmpeg, ["-v", "error", "-i", output.path, "-f", "null", "-"])
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(store.items[0].outputFileSize, Int64(try Data(contentsOf: output).count))
        XCTAssertFalse(store.items[0].mediaHandling?.issues.contains { if case .subtitles = $0 { true } else { false } } ?? false)
    }

    func testAllAudioAndMuteActuallyProduceRequestedTracks() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await fixture(directory)
        XCTAssertEqual(ExportOptions().audio, .all)
        let defaultStore = try await converted(source, options: ExportOptions())
        let defaultInfo = try await defaultStore.exportInfo(for: completedOutput(defaultStore))
        XCTAssertEqual(defaultInfo.audioTracks.map(\.language), ["eng", "jpn"], "Defaults must retain every audio track")
        XCTAssertFalse(defaultStore.items[0].mediaHandling?.issues.contains { if case .extraAudio = $0 { true } else { false } } ?? false)
        for mode in [AudioSelection.all, .none] {
            let store = try await converted(source, options: ExportOptions(audio: mode))
            let output = try completedOutput(store)
            let info = try await store.exportInfo(for: output)
            XCTAssertEqual(info.audioTrackCount, mode == .all ? 2 : 0)
            XCTAssertEqual(info.subtitleTrackCount, 0)
            _ = try await run(ffmpeg, ["-v", "error", "-i", output.path, "-f", "null", "-"])
        }
    }

    func testIncompatibleSelectedAudioIsEncodedWithoutReencodingCompatibleVideo() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await fixture(directory, audioCodec: "ac3")
        let inspector = ConverterStore(ffmpegOverride: ffmpeg)
        let info = try await inspector.exportInfo(for: source)
        let store = try await converted(source, options: ExportOptions(audio: .selected, audioStreamIndex: info.audioTracks[1].index, subtitles: .keep, subtitleStreamIndex: info.subtitleTracks[0].index))
        let output = try completedOutput(store)
        let result = try await inspector.exportInfo(for: output)
        XCTAssertEqual(result.audioTracks.map(\.codec), ["aac"])
        XCTAssertEqual(result.audioTracks.map(\.language), ["jpn"])
        XCTAssertEqual(result.subtitleTracks.map(\.codec), ["mov_text"])
        let before = try await packetHashes(source, stream: "v:0"), after = try await packetHashes(output, stream: "v:0")
        XCTAssertEqual(before, after)
    }

    func testMixedAudioReencodesOnlyIncompatibleTrackAndPreservesDefaultSelection() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try await fixture(directory)
        let mixed = directory.appendingPathComponent("mixed.mkv")
        _ = try await run(ffmpeg, ["-v", "error", "-i", original.path, "-map", "0", "-c", "copy", "-c:a:1", "ac3", "-disposition:a:0", "0", "-disposition:a:1", "default", mixed.path])
        let store = try await converted(mixed, options: ExportOptions())
        let output = try completedOutput(store)
        let info = try await store.exportInfo(for: output)
        XCTAssertEqual(info.audioTracks.map(\.codec), ["aac", "aac"])
        XCTAssertEqual(info.audioTracks.map(\.isDefault), [false, true])
        let before = try await packetHashes(mixed, stream: "a:0"), after = try await packetHashes(output, stream: "a:0")
        XCTAssertEqual(before, after, "A compatible AAC stream must not be recompressed just because another track is AC3")
    }

    func testTargetSizeBudgetWorksWithSoftwareAndHardwareAndTrimmedDuration() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("noise input.mkv")
        _ = try await run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=640x360:r=30:d=10,noise=alls=30:allf=t+u", "-f", "lavfi", "-i", "sine=frequency=440:duration=10", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "12", "-c:a", "aac", source.path])
        for preset in [ConversionPreset.h264Software, .h264Hardware] {
            let store = try await converted(source, options: ExportOptions(targetSizeMB: 1), preset: preset, trim: ClipRange(start: 1, end: 9))
            let output = try completedOutput(store)
            let count = try Data(contentsOf: output).count
            XCTAssertGreaterThan(count, 650_000, "A real bitrate budget must be used")
            XCTAssertLessThan(count, 1_400_000, "The target is approximate, not an exact byte promise")
            let info = try await store.exportInfo(for: output)
            XCTAssertEqual(try XCTUnwrap(info.duration), 8, accuracy: 0.15)
            XCTAssertEqual(info.audioTrackCount, 1)
            _ = try await run(ffmpeg, ["-v", "error", "-i", output.path, "-f", "null", "-"])
        }
    }

    func testMissingSelectionAndMissingRendererFailWithoutPublishing() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await fixture(directory)
        let inspector = ConverterStore(ffmpegOverride: ffmpeg)
        let info = try await inspector.exportInfo(for: source)
        var invalid = [ExportOptions(audio: .selected, audioStreamIndex: 999), ExportOptions(subtitles: .keep, subtitleStreamIndex: 999)]
        if !(await inspector.subtitleBurningAvailable()) {
            invalid.append(ExportOptions(subtitles: .burn, subtitleStreamIndex: info.subtitleTracks[0].index))
        }
        for options in invalid {
            let store = try await converted(source, options: options)
            guard case .failed = store.items[0].state else { return XCTFail("Invalid options must fail explicitly") }
            XCTAssertEqual(store.items[0].failure?.diagnostic, "export:invalid-options")
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { $0.pathExtension == "mp4" || $0.lastPathComponent.contains("partial") })
    }

    func testBurnedSubtitleRemainsVisibleAfterSeekAndSpecialFilenameEscaping() async throws {
        let inspector = ConverterStore(ffmpegOverride: ffmpeg)
        guard await inspector.subtitleBurningAvailable() else { throw XCTSkip("A libass-enabled FFmpeg is required for the positive burn test") }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await fixture(directory, black: true)
        let info = try await inspector.exportInfo(for: source)
        let store = try await converted(source, options: ExportOptions(audio: .none, subtitles: .burn, subtitleStreamIndex: info.subtitleTracks[0].index), preset: .h264Software, trim: ClipRange(start: 1, end: 3))
        let output = try completedOutput(store)
        let outputInfo = try await store.exportInfo(for: output)
        XCTAssertEqual(outputInfo.subtitleTrackCount, 0)
        XCTAssertEqual(outputInfo.audioTrackCount, 0)
        XCTAssertEqual(try XCTUnwrap(outputInfo.duration), 2, accuracy: 0.15)
        let frame = try await run(ffmpeg, ["-v", "error", "-ss", "0.4", "-i", output.path, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"])
        XCTAssertGreaterThan(frame.filter { $0 > 150 }.count, 60, "The cue must actually be burned into the video after input seeking")
        _ = try await run(ffmpeg, ["-v", "error", "-i", output.path, "-f", "null", "-"])
    }

    func testClearCompletedDuringAsyncSubtitlePreflightKeepsOneThroughFourJobs() async throws {
        let inspector = ConverterStore(ffmpegOverride: ffmpeg)
        guard await inspector.subtitleBurningAvailable() else { throw XCTSkip("Requires libass for the controlled capability-check regression") }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await fixture(directory, black: true)
        let info = try await inspector.exportInfo(for: source)
        for remaining in 1...4 {
            let tools = directory.appendingPathComponent("tools-\(remaining)", isDirectory: true)
            try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
            let marker = tools.appendingPathComponent("checking")
            let wrapper = tools.appendingPathComponent("ffmpeg")
            func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            let script = "#!/bin/sh\nif [ \"$2\" = \"-filters\" ]; then\n  /usr/bin/touch \(quote(marker.path))\n  /bin/sleep 0.4\nfi\nexec \(quote(ffmpeg.path)) \"$@\"\n"
            try script.write(to: wrapper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
            try FileManager.default.createSymbolicLink(at: tools.appendingPathComponent("ffprobe"), withDestinationURL: ffprobe)
            let store = ConverterStore(ffmpegOverride: wrapper)
            store.preset = .h264Software; store.outputDirectory = directory
            store.items = (0..<8).map { index in
                var item = ConversionItem(source: source)
                if index < 8 - remaining { item.state = .complete(directory.appendingPathComponent("previous-\(index).mp4")) }
                else { item.exportOptions = ExportOptions(audio: .none, subtitles: .burn, subtitleStreamIndex: info.subtitleTracks[0].index) }
                return item
            }
            let identities = store.items.suffix(remaining).map(\.id)
            store.start()
            var deadline = TestDeadline(seconds: 5)
            while !FileManager.default.fileExists(atPath: marker.path) && deadline.hasTimeRemaining { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
            store.clearCompleted()
            XCTAssertEqual(store.items.map(\.id), identities)
            deadline = TestDeadline(seconds: 30)
            while store.isRunning && deadline.hasTimeRemaining { try await Task.sleep(nanoseconds: 25_000_000) }
            if store.isRunning {
                let states = store.items.map { "\($0.id): \($0.state), \(String(describing: $0.failure))" }.joined(separator: "; ")
                store.cancel(); XCTFail("Preflight cleanup test timed out (\(remaining) survivors): \(states)")
            }
            XCTAssertEqual(store.items.map(\.id), identities)
            XCTAssertTrue(store.items.allSatisfy { if case .complete = $0.state { true } else { false } }, "Every surviving job must finish after completed rows are removed")
        }
    }

    private func fixture(_ directory: URL, black: Bool = false, audioCodec: String = "aac") async throws -> URL {
        let subtitle = directory.appendingPathComponent("captions.srt")
        try "1\n00:00:00,500 --> 00:00:03,500\nSubtitle visible\n\n".write(to: subtitle, atomically: true, encoding: .utf8)
        let source = directory.appendingPathComponent("选片 [v1], it's:a\\b.mkv")
        _ = try await run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", black ? "color=c=black:s=640x360:r=25:d=4" : "testsrc2=s=320x240:r=25:d=4", "-f", "lavfi", "-i", "sine=frequency=440:duration=4", "-f", "lavfi", "-i", "sine=frequency=880:duration=4", "-i", subtitle.path, "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:s", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-c:a", audioCodec, "-c:s", "srt", "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=jpn", "-metadata:s:s:0", "language=spa", "-y", source.path])
        return source
    }

    private func converted(_ source: URL, options: ExportOptions, preset: ConversionPreset = .smartMP4, trim: ClipRange? = nil) async throws -> ConverterStore {
        let store = ConverterStore(ffmpegOverride: ffmpeg)
        store.preset = preset; store.outputDirectory = source.deletingLastPathComponent()
        var item = ConversionItem(source: source); item.exportOptions = options; item.trimRange = trim
        store.items = [item]; store.start()
        let deadline = TestDeadline(seconds: 60)
        while store.isRunning && deadline.hasTimeRemaining { try await Task.sleep(nanoseconds: 50_000_000) }
        if store.isRunning { store.cancel(); XCTFail("Queue timed out") }
        return store
    }
    private func completedOutput(_ store: ConverterStore) throws -> URL {
        guard case .complete(let url) = store.items[0].state else {
            XCTFail("Export failed: \(store.items[0].state); \(String(describing: store.items[0].failure))")
            throw TestError.failed
        }
        return url
    }
    private func packetHashes(_ source: URL, stream: String) async throws -> [String] {
        let data = try await run(ffprobe, ["-v", "error", "-select_streams", stream, "-show_packets", "-show_data_hash", "sha256", "-show_entries", "packet=data_hash", "-of", "json", source.path])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let packets = try XCTUnwrap(object["packets"] as? [[String: Any]])
        // MP4 adds AAC skip-sample side data; compare encoded payloads only.
        return try packets.map { try XCTUnwrap($0["data_hash"] as? String) }
    }
    private func run(_ executable: URL, _ args: [String]) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw XCTSkip("FFmpeg/ffprobe are required") }
        let runner = FFmpegProcessRunner(executable: executable, arguments: args, configuration: .init(inactivityTimeout: 60, maximumOutputBytes: 2_000_000))
        let result = await runner.run()
        guard result.succeeded else { XCTFail("Media command failed: \(result.standardError)"); throw TestError.failed }
        return result.standardOutput
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-export-media-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private enum TestError: Error { case failed }
}
