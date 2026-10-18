import Foundation
import XCTest
@testable import FastConvert

final class ConversionPlanningTests: XCTestCase {
    func testResizeUsesDisplayedOrientationAndCropDimensions() {
        var info = fixtureInfo()
        info.displayGeometry = VideoGeometry.displayed(width: 1280, height: 720, sampleAspectRatio: "1:1", rotation: 90)
        XCTAssertEqual(info.displayGeometry?.width, 720)
        XCTAssertEqual(info.displayGeometry?.height, 1280)
        XCTAssertTrue(OutputResolution.p720.requiresReencode(sourceHeight: info.displayGeometry?.height), "Encoded height 720 is not a no-op for a portrait display matrix")
        XCTAssertEqual(info.geometry(crop: CropRect(x: 0, y: 0, width: 600, height: 400), rotation: .clockwise)?.height, 600)
        XCTAssertNil(VideoGeometry.displayed(width: 1280, height: 720, sampleAspectRatio: "1:1", rotation: 45))
        XCTAssertEqual(VideoGeometry.displayed(width: 1280, height: 720, sampleAspectRatio: "4:3", rotation: nil)?.canSkipUnchangedSize, false)
        XCTAssertEqual(VideoGeometry.displayed(width: 1279, height: 720, sampleAspectRatio: "1:1", rotation: nil)?.canSkipUnchangedSize, false)
        XCTAssertNil(OutputResolution.p720.filter(sourceHeight: 720, quality: .balanced, useVideoToolbox: true, canSkipUnchangedSize: true))
        XCTAssertNotNil(OutputResolution.p720.filter(sourceHeight: 720, quality: .balanced, useVideoToolbox: true, canSkipUnchangedSize: false))
    }

    func testEncodingClockRequiresPositiveBoundedRational() {
        var info = fixtureInfo()
        info.timeBase = "1/90000"
        XCTAssertEqual(info.encodingTimeBase, "1/90000")
        for invalid in ["", "N/A", "1/0", "0/90000", "-1/30", "1/999999999999", "1/30/2", "demux"] {
            info.timeBase = invalid
            XCTAssertNil(info.encodingTimeBase, invalid)
        }
    }

    @MainActor
    func testSameSizeSmartConversionCopiesVideoButExplicitSoftwareStillEncodes() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("720p.mp4")
        try run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x720:rate=6:duration=1", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "30", source.path])
        let sourceHash = try copiedVideoHash(source, ffmpeg: tools.ffmpeg)

        let smart = ConverterStore()
        smart.outputResolution = .p720
        smart.outputDirectory = directory
        smart.items = [ConversionItem(source: source)]
        smart.start()
        let copied = try await completedOutput(smart)
        XCTAssertEqual(try copiedVideoHash(copied, ffmpeg: tools.ffmpeg), sourceHash, "An unchanged smart resize must not spend time re-encoding")

        let software = ConverterStore()
        software.preset = .h264Software
        software.outputResolution = .p720
        software.outputDirectory = directory
        software.items = [ConversionItem(source: source)]
        software.start()
        let encoded = try await completedOutput(software)
        XCTAssertNotEqual(try copiedVideoHash(encoded, ffmpeg: tools.ffmpeg), sourceHash, "An explicit software/quality choice must retain its encoding semantics")
    }

    @MainActor
    func testSmartConvertsOnlyIncompatibleAudioAndKeepsVideoBytes() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("H264 and PCM.mov")
        try run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x720:rate=12:duration=1", "-f", "lavfi", "-i", "sine=frequency=660:sample_rate=48000:duration=1", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "30", "-c:a", "pcm_s16le", "-shortest", source.path])
        let sourceHash = try copiedVideoHash(source, ffmpeg: tools.ffmpeg)

        let smart = ConverterStore()
        smart.outputResolution = .p720
        smart.outputDirectory = directory
        smart.items = [ConversionItem(source: source)]
        smart.start()
        let output = try await completedOutput(smart)
        XCTAssertEqual(try copiedVideoHash(output, ffmpeg: tools.ffmpeg), sourceHash, "Non-AAC audio must not force compatible H.264 video through an encoder")
        let audio = try capture(tools.ffprobe, ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0", output.path])
        XCTAssertEqual(audio.trimmingCharacters(in: .whitespacesAndNewlines), "aac")
        let durationText = try capture(tools.ffprobe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", output.path])
        let duration = try XCTUnwrap(Double(durationText.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(duration, 1, accuracy: 0.1)
        try run(tools.ffmpeg, ["-v", "error", "-i", output.path, "-map", "0:v:0", "-map", "0:a:0", "-f", "null", "-"])

        for (preset, resolution) in [(ConversionPreset.h264Software, OutputResolution.p720), (.smartMP4, .p480)] {
            let encoded = ConverterStore()
            encoded.preset = preset
            encoded.outputResolution = resolution
            encoded.outputDirectory = directory
            encoded.items = [ConversionItem(source: source)]
            encoded.start()
            let encodedOutput = try await completedOutput(encoded)
            XCTAssertNotEqual(try copiedVideoHash(encodedOutput, ffmpeg: tools.ffmpeg), sourceHash, "Explicit encoding and actual resizing must still encode video")
        }
    }

    @MainActor
    func testVariableFrameRateTranscodePreservesEveryPresentationTimestamp() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("variable timing.mp4")
        try run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x96:rate=30:duration=2", "-vf", "settb=1/90000,setpts=PTS+270*sin(N)", "-enc_time_base:v", "1/90000", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24", source.path])
        let sourceTimes = try frameTimes(source, ffprobe: tools.ffprobe)
        XCTAssertEqual(sourceTimes.count, 60)
        let intervals = zip(sourceTimes.dropFirst(), sourceTimes).map(-)
        XCTAssertGreaterThan((intervals.max() ?? 0) - (intervals.min() ?? 0), 0.003, "The fixture must actually have irregular timestamps")

        for preset in [ConversionPreset.h264Software, .h264Hardware] {
            let store = ConverterStore()
            store.preset = preset
            store.outputDirectory = directory
            let item = ConversionItem(source: source)
            store.items = [item]
            if preset == .h264Hardware { store.scheduleRotation(item, rotation: .clockwise) }
            store.start()
            let output = try await completedOutput(store)
            let outputTimes = try frameTimes(output, ffprobe: tools.ffprobe)
            XCTAssertEqual(outputTimes.count, sourceTimes.count)
            for (sourceTime, outputTime) in zip(sourceTimes, outputTimes) {
                XCTAssertEqual(outputTime, sourceTime, accuracy: 0.000012, "A VFR frame must retain its original presentation time: \(preset)")
            }
            if preset == .h264Hardware {
                let dimensions = try capture(tools.ffprobe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", output.path])
                XCTAssertEqual(dimensions.trimmingCharacters(in: .whitespacesAndNewlines), "96,160", "Rotation must preserve the source clock while swapping output dimensions")
            }
        }
    }

    @MainActor
    func testLateAccurateTrimMatchesReferenceFrameAndCopiedAudio() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("late trim.mp4")
        try run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=192x128:rate=30:duration=8", "-f", "lavfi", "-i", "sine=frequency=660:sample_rate=48000:duration=8", "-c:v", "libx264", "-preset", "ultrafast", "-g", "90", "-crf", "24", "-c:a", "aac", "-shortest", source.path])

        let store = ConverterStore()
        store.preset = .h264Software
        store.outputDirectory = directory
        let item = ConversionItem(source: source)
        store.items = [item]
        store.scheduleTrim(item, start: 6.123, end: 7.456)
        // Force a pixel edit, since a compatible trim alone deliberately copies.
        store.scheduleCrop(item, crop: CropRect(x: 0, y: 0, width: 192, height: 128))
        store.start()
        let output = try await completedOutput(store)
        let reference = directory.appendingPathComponent("reference.mp4")
        try run(tools.ffmpeg, ["-v", "error", "-i", source.path, "-ss", "6.123", "-to", "7.456", "-vf", "crop=192:128:0:0", "-enc_time_base:v", "1/15360", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", "-an", reference.path])
        let actualFrame = try capture(tools.ffmpeg, ["-v", "error", "-i", output.path, "-map", "0:v:0", "-frames:v", "1", "-f", "md5", "-"])
        let referenceFrame = try capture(tools.ffmpeg, ["-v", "error", "-i", reference.path, "-map", "0:v:0", "-frames:v", "1", "-f", "md5", "-"])
        XCTAssertEqual(actualFrame, referenceFrame, "Fast seeking must retain the first accurately selected video frame")
        let actualAudio = try capture(tools.ffmpeg, ["-v", "error", "-i", output.path, "-t", "1.1", "-vn", "-c:a", "pcm_s16le", "-f", "md5", "-"])
        let referenceAudio = try capture(tools.ffmpeg, ["-v", "error", "-ss", "6.123", "-i", source.path, "-t", "1.1", "-vn", "-c:a", "pcm_s16le", "-f", "md5", "-"])
        XCTAssertEqual(actualAudio, referenceAudio, "Copied AAC must discard pre-roll and remain aligned to the requested start")
    }

    private func fixtureInfo() -> VideoInfo {
        VideoInfo(duration: 1, videoRate: 1_000_000, audioRate: nil, width: 1280, height: 720, hasVideo: true, videoCodec: "h264", audioCodec: nil, frameRate: "30/1", pixelFormat: "yuv420p", audioSampleRate: nil, audioChannels: nil, audioTrackCount: 0, subtitleTrackCount: 0, colorTransfer: nil, probeSucceeded: true)
    }

    private func mediaTools() throws -> (ffmpeg: URL, ffprobe: URL) {
        guard let path = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("FFmpeg is required for synthetic media tests")
        }
        let ffmpeg = URL(fileURLWithPath: path)
        guard try capture(ffmpeg, ["-hide_banner", "-encoders"]).contains("libx264") else {
            throw XCTSkip("The synthetic regression fixture requires libx264")
        }
        return (ffmpeg, ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe"))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mp4flow-planning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func run(_ executable: URL, _ arguments: [String]) throws {
        _ = try capture(executable, arguments)
    }

    private func capture(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Synthetic fixture command failed: \(arguments.prefix(4))")
        guard process.terminationStatus == 0 else { throw NSError(domain: "ConversionPlanningTests", code: Int(process.terminationStatus)) }
        return String(decoding: data, as: UTF8.self)
    }

    private func copiedVideoHash(_ source: URL, ffmpeg: URL) throws -> String {
        try capture(ffmpeg, ["-v", "error", "-i", source.path, "-map", "0:v:0", "-c:v", "copy", "-f", "hash", "-"])
    }

    private func frameTimes(_ source: URL, ffprobe: URL) throws -> [Double] {
        let data = try capture(ffprobe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", source.path])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any])
        let frames = try XCTUnwrap(json["frames"] as? [[String: Any]])
        return frames.compactMap { ($0["best_effort_timestamp_time"] as? String).flatMap(Double.init) }
    }

    @MainActor
    private func completedOutput(_ store: ConverterStore) async throws -> URL {
        let deadline = Date().addingTimeInterval(30)
        while store.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(store.isRunning, "The small synthetic conversion should complete")
        guard case .complete(let output) = store.items[0].state else {
            throw NSError(domain: "ConversionPlanningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected state: \(store.items[0].state)"])
        }
        return output
    }
}
