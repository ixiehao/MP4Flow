import Foundation
import XCTest
@testable import FastConvert

final class ConverterStoreTests: XCTestCase {
    /// Opt-in local benchmark of the actual queue. Media paths are supplied at
    /// invocation time and never stored in the repository or printed in reports.
    @MainActor
    func testAuthorizedMedia720pBenchmark() async throws {
        guard let input = ProcessInfo.processInfo.environment["MP4FLOW_BENCHMARK_INPUT"], !input.isEmpty else {
            throw XCTSkip("Set MP4FLOW_BENCHMARK_INPUT to an authorized local video to run the full-media benchmark")
        }
        let ffmpeg = try availableFFmpeg()
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        let source = URL(fileURLWithPath: input)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceDuration = try XCTUnwrap(Double(probeValue(source, ffprobe: ffprobe, entries: "format=duration").trimmingCharacters(in: .whitespacesAndNewlines)))
        let store = ConverterStore()
        store.outputResolution = .p720
        store.outputDirectory = directory
        store.items = [ConversionItem(source: source)]
        let started = Date()
        store.start()
        try await waitForQueue(store, timeout: 600)
        let elapsed = Date().timeIntervalSince(started)
        guard case .complete(let output) = store.items[0].state else {
            return XCTFail("Authorized benchmark did not complete: \(store.items[0].state)")
        }
        let dimensions = try probeValue(output, ffprobe: ffprobe, entries: "stream=width,height", selectStreams: "v:0")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outputDuration = try XCTUnwrap(Double(probeValue(output, ffprobe: ffprobe, entries: "format=duration").trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(outputDuration, sourceDuration, accuracy: 0.15)
        let sourceFrames = Int(try probeValue(source, ffprobe: ffprobe, entries: "stream=nb_frames", selectStreams: "v:0").trimmingCharacters(in: .whitespacesAndNewlines))
        let outputFrames = Int(try probeValue(output, ffprobe: ffprobe, entries: "stream=nb_frames", selectStreams: "v:0").trimmingCharacters(in: .whitespacesAndNewlines))
        if let sourceFrames, let outputFrames { XCTAssertEqual(outputFrames, sourceFrames) }
        XCTAssertEqual(try decodeVideo(output, ffmpeg: ffmpeg), 0)
        print(String(format: "Local queue benchmark: source %.3f s; elapsed %.3f s; %.2fx real time; output %@; frames %@", sourceDuration, elapsed, sourceDuration / max(elapsed, 0.001), dimensions, outputFrames.map(String.init) ?? "unknown"))
    }

    func testHardwareFallbackClassifierRetriesOnlyExplicitVideoToolboxFailures() {
        XCTAssertEqual(
            FFmpegHardwareRetryClassifier.hint(
                stderr: "Impossible to convert between filter Parsed_scale_vt_0 and output format",
                usedHardwarePipeline: true,
                usedHardwareEncoder: true
            ),
            .cpuDecodeAndFilter
        )
        XCTAssertEqual(
            FFmpegHardwareRetryClassifier.hint(
                stderr: "Unknown encoder 'h264_videotoolbox'",
                usedHardwarePipeline: true,
                usedHardwareEncoder: true
            ),
            .softwareEncoder,
            "A missing VT encoder should skip the intermediate retry with the same encoder"
        )
        XCTAssertEqual(
            FFmpegHardwareRetryClassifier.hint(
                stderr: "VTCompressionSessionCreate failed with error -12903",
                usedHardwarePipeline: false,
                usedHardwareEncoder: true
            ),
            .softwareEncoder
        )
        for stderr in [
            "Invalid data found when processing input",
            "No space left on device",
            "Error while decoding stream 0:0",
            "FFmpeg stalled without progress"
        ] {
            XCTAssertNil(
                FFmpegHardwareRetryClassifier.hint(
                    stderr: stderr,
                    usedHardwarePipeline: true,
                    usedHardwareEncoder: true
                ),
                "Must not replay an entire video for unrelated failure: \(stderr)"
            )
        }
        let mappedHardwareThenDecodeError = """
        Stream mapping:
          Stream #0:0 -> #0:0 (h264 (native) -> h264 (h264_videotoolbox))
        Error while decoding stream 0:0
        """
        XCTAssertNil(FFmpegHardwareRetryClassifier.hint(
            stderr: mappedHardwareThenDecodeError,
            usedHardwarePipeline: true,
            usedHardwareEncoder: true
        ))
        let mappedHardwareThenMuxError = """
        Stream mapping:
          Stream #0:0 -> #0:0 (h264 (native) -> h264 (h264_videotoolbox))
        Could not write header for output file #0 (incorrect codec parameters?): Invalid argument
        """
        XCTAssertNil(FFmpegHardwareRetryClassifier.hint(
            stderr: mappedHardwareThenMuxError,
            usedHardwarePipeline: true,
            usedHardwareEncoder: true
        ))
        let explicitHardwareAndTerminalError = """
        [Parsed_scale_vt_0] Error applying hardware filter
        No space left on device
        """
        XCTAssertNil(FFmpegHardwareRetryClassifier.hint(
            stderr: explicitHardwareAndTerminalError,
            usedHardwarePipeline: true,
            usedHardwareEncoder: true
        ), "A terminal disk failure must not trigger another full encode")
        let cpuPipelineThenDecodeError = """
        Stream mapping:
          Stream #0:0 -> #0:0 (h264 (native) -> h264 (h264_videotoolbox))
        Error while decoding stream 0:0
        """
        XCTAssertNil(FFmpegHardwareRetryClassifier.hint(
            stderr: cpuPipelineThenDecodeError,
            usedHardwarePipeline: false,
            usedHardwareEncoder: true
        ))
        let mappedHardwareThenOutputError = """
        Stream mapping:
          Stream #0:0 -> #0:0 (h264 (native) -> h264 (h264_videotoolbox))
        Error initializing output stream 0:0
        """
        XCTAssertNil(FFmpegHardwareRetryClassifier.hint(
            stderr: mappedHardwareThenOutputError,
            usedHardwarePipeline: true,
            usedHardwareEncoder: true
        ))
        XCTAssertNil(
            FFmpegHardwareRetryClassifier.hint(
                stderr: "No such filter: 'scale_vt'",
                usedHardwarePipeline: false,
                usedHardwareEncoder: false
            )
        )
    }

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
    func testRemovingWaitingItemUpdatesBatchCountAndSkipsItsConversion() async throws {
        let ffmpeg = try availableFFmpeg()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.mov")
        let skipped = directory.appendingPathComponent("skipped.mov")
        try makeShortVideo(at: first, ffmpeg: ffmpeg)
        try FileManager.default.copyItem(at: first, to: skipped)
        let store = ConverterStore()
        store.preset = .h264Software
        store.outputDirectory = directory
        let waiting = ConversionItem(source: skipped)
        store.items = [ConversionItem(source: first), waiting]
        store.start()
        store.remove(waiting)
        XCTAssertEqual(store.activeBatchProgressLabel, L10n.format("已处理 %d/%d", 0, 1))
        try await waitForQueue(store)
        guard let remaining = store.items.first, case .complete = remaining.state else {
            return XCTFail("The remaining queued item should complete")
        }
        let outputs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }
        XCTAssertEqual(outputs.count, 1)
        XCTAssertFalse(outputs.contains(where: { $0.lastPathComponent.hasPrefix("skipped") }))
    }

    @MainActor
    func testDefault1080pTo720pConversionPreservesGeometryFrameRateAndAudio() async throws {
        let ffmpeg = try availableFFmpeg()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("1080p source.mp4")
        guard let sourceEncoder = try availableH264Encoder(ffmpeg: ffmpeg) else {
            throw XCTSkip("FFmpeg must provide libx264 or h264_videotoolbox to generate the fixture")
        }
        try make1080pVideo(at: source, ffmpeg: ffmpeg, encoder: sourceEncoder)

        let store = ConverterStore()
        store.outputResolution = .p720
        store.outputDirectory = directory
        store.items = [ConversionItem(source: source)]
        store.start()
        try await waitForQueue(store)

        guard case .complete(let output) = store.items[0].state else {
            return XCTFail("Expected the default 1080p→720p conversion to complete; got \(store.items[0].state)")
        }
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        let video = try probeValue(
            output,
            ffprobe: ffprobe,
            entries: "stream=width,height,sample_aspect_ratio,display_aspect_ratio,r_frame_rate",
            selectStreams: "v:0"
        ).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
        XCTAssertEqual(video.count, 5)
        XCTAssertEqual(video[0], "1280")
        XCTAssertEqual(video[1], "720")
        XCTAssertEqual(video[2], "1:1")
        XCTAssertEqual(video[3], "16:9")
        XCTAssertEqual(video[4], "30000/1001")

        let audioCodec = try probeValue(output, ffprobe: ffprobe, entries: "stream=codec_name", selectStreams: "a:0")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(audioCodec, "aac")
        let duration = try XCTUnwrap(Double(probeValue(output, ffprobe: ffprobe, entries: "format=duration").trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertGreaterThan(duration, 1.8)
        XCTAssertLessThan(duration, 2.2)
        XCTAssertEqual(try decodeVideo(output, ffmpeg: ffmpeg), 0, "The converted video and audio must decode cleanly")
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

    @MainActor
    func testEditingCompletedVideoCreatesNewOutputsAndPreservesPreviousFiles() async throws {
        let ffmpeg = try availableFFmpeg()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("reedit.mov")
        try makeShortVideo(at: source, ffmpeg: ffmpeg)
        let store = ConverterStore()
        store.preset = .h264Software
        store.outputDirectory = directory
        store.items = [ConversionItem(source: source)]
        store.start()
        try await waitForQueue(store)

        let edits: [(ConversionItem) -> Void] = [
            { store.scheduleTrim($0, start: 0.125, end: 0.5) },
            { store.scheduleCrop($0, crop: CropRect(x: 8, y: 4, width: 48, height: 32)) },
            { store.scheduleRotation($0, rotation: .clockwise) }
        ]
        var preservedOutputs: [URL: Data] = [:]
        for edit in edits {
            guard case .complete(let oldOutput) = store.items[0].state else {
                return XCTFail("The preceding conversion must complete before editing")
            }
            preservedOutputs[oldOutput] = try Data(contentsOf: oldOutput)
            edit(store.items[0])
            XCTAssertEqual(store.items[0].state, .waiting)
            XCTAssertTrue(store.hasWaiting, "Editing a completed row must enable Start again")
            store.start()
            try await waitForQueue(store)
            guard case .complete(let newOutput) = store.items[0].state else {
                return XCTFail("Re-edited source must convert successfully")
            }
            XCTAssertNotEqual(newOutput, oldOutput)
            for (url, bytes) in preservedOutputs {
                XCTAssertEqual(try Data(contentsOf: url), bytes, "Existing outputs must not be modified or deleted")
            }
        }
        guard case .complete(let output) = store.items[0].state else { return XCTFail("Missing final output") }
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        XCTAssertEqual(try probeValue(output, ffprobe: ffprobe, entries: "stream=width,height").trimmingCharacters(in: .whitespacesAndNewlines), "32,48")
        XCTAssertEqual(try decodeVideo(output, ffmpeg: ffmpeg), 0)
        let completed = store.items[0]
        store.scheduleTrim(completed, start: 0.125, end: 0.5)
        store.scheduleCrop(completed, crop: completed.crop)
        store.scheduleRotation(completed, rotation: .clockwise)
        XCTAssertEqual(store.items[0], completed, "Confirming unchanged settings must keep the valid result")
    }

    @MainActor
    func testEditingTerminalRowsClearsStaleResultsAndResettingEditsAlsoRequeues() {
        let source = URL(fileURLWithPath: "/test/input.mov")
        let output = URL(fileURLWithPath: "/test/output.mp4")
        let store = ConverterStore()
        let edits: [(ConversionItem) -> Void] = [
            { store.scheduleTrim($0, start: 1, end: 2) },
            { store.scheduleCrop($0, crop: nil) },
            { store.scheduleRotation($0, rotation: nil) }
        ]
        for state in [ConversionState.complete(output), .failed("old failure"), .cancelled] {
            for edit in edits {
                var item = ConversionItem(source: source)
                item.state = state
                item.crop = CropRect(x: 2, y: 2, width: 32, height: 32)
                item.rotation = .clockwise
                item.phase = .verifying
                item.failure = ConversionFailure(reasonKey: "reason", solutionKey: "solution", diagnostic: "old")
                item.mediaHandling = MediaHandlingNotice(issues: [.unconfirmed])
                store.items = [item]
                edit(item)
                XCTAssertEqual(store.items[0].id, item.id)
                XCTAssertEqual(store.items[0].source, source)
                XCTAssertEqual(store.items[0].state, .waiting)
                XCTAssertNil(store.items[0].phase)
                XCTAssertNil(store.items[0].failure)
                XCTAssertNil(store.items[0].mediaHandling)
            }
        }
    }

    @MainActor
    func testEditsRejectInvalidTrimAndDoNotChangeAnActiveOrRemovedRow() {
        let store = ConverterStore()
        let source = URL(fileURLWithPath: "/test/input.mov")
        var item = ConversionItem(source: source)
        item.state = .complete(URL(fileURLWithPath: "/test/output.mp4"))
        store.items = [item]
        for (start, end) in [(-1.0, 2.0), (Double.nan, 2.0), (0.0, Double.infinity), (2.0, 1.0)] {
            store.scheduleTrim(item, start: start, end: end)
            XCTAssertEqual(store.items[0], item)
        }
        store.isRunning = true
        store.scheduleTrim(item, start: 0, end: 1)
        store.scheduleCrop(item, crop: CropRect(x: 0, y: 0, width: 32, height: 32))
        store.scheduleRotation(item, rotation: .clockwise)
        XCTAssertEqual(store.items[0], item)
        store.isRunning = false
        store.items = []
        store.scheduleRotation(item, rotation: .clockwise)
        XCTAssertTrue(store.items.isEmpty, "A stale editor must not restore a removed row")
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

    private func availableH264Encoder(ffmpeg: URL) throws -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-encoders"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(decoding: data, as: UTF8.self)
        if output.contains(" libx264 ") { return "libx264" }
        if output.contains(" h264_videotoolbox ") { return "h264_videotoolbox" }
        return nil
    }

    private func make1080pVideo(at output: URL, ffmpeg: URL, encoder: String) throws {
        let process = Process()
        process.executableURL = ffmpeg
        var arguments = [
            "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30000/1001:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2",
            "-c:v", encoder
        ]
        if encoder == "libx264" {
            arguments += ["-preset", "ultrafast", "-crf", "18"]
        } else {
            arguments += ["-b:v", "6M"]
        }
        arguments += ["-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "-y", output.path]
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.generationFailed(process.terminationStatus) }
    }

    private func probeValue(_ source: URL, ffprobe: URL, entries: String, selectStreams: String? = nil) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = ffprobe
        var arguments = ["-v", "error"]
        if let selectStreams { arguments += ["-select_streams", selectStreams] }
        arguments += ["-show_entries", entries, "-of", "csv=p=0", source.path]
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.probeFailed(process.terminationStatus) }
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeVideo(_ source: URL, ffmpeg: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-v", "error", "-i", source.path, "-f", "null", "-"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @MainActor
    private func waitForQueue(_ store: ConverterStore, timeout: TimeInterval = 20) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while store.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if store.isRunning {
            store.cancel()
            XCTFail("Conversion queue did not complete within \(timeout) seconds")
        }
    }
}

private enum FixtureError: Error {
    case generationFailed(Int32)
    case probeFailed(Int32)
}
