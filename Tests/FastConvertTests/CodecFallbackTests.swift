import Foundation
import XCTest
@testable import FastConvert

@MainActor final class CodecFallbackTests: XCTestCase {
    private var ffmpeg: URL {
        DependencyToolResolver.resolve().ffmpeg ?? URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    }
    private var ffprobe: URL { ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe") }

    func testHEVCSoftwareBudgetRetainsQualityEffortWithoutAStreamingCeiling() throws {
        let info = VideoInfo(duration: 10, videoRate: 800_000, audioRate: nil, width: 160, height: 96, hasVideo: true, videoCodec: "h264", audioCodec: nil, frameRate: "12/1", pixelFormat: "yuv420p", audioSampleRate: nil, audioChannels: nil, audioTrackCount: 0, subtitleTrackCount: 0, colorTransfer: nil, probeSucceeded: true)
        let plan = try ExportPlan(options: ExportOptions(targetSizeMB: 1), info: info, trim: nil, preset: .hevcHardware, canBurnSubtitles: false)
        for (quality, effort) in [(ConversionQuality.compact, "fast"), (.balanced, "medium"), (.high, "slow")] {
            let args = FFmpegCommandBuilder.arguments(source: URL(fileURLWithPath: "/tmp/source.mp4"), output: URL(fileURLWithPath: "/tmp/output.mp4"), info: info, preset: .hevcHardware, quality: quality, resolution: .original, trim: nil, rotation: nil, crop: nil, aspectRatio: nil, imageAdjustment: ImageAdjustment(), copyVideoAndEncodeAudio: false, preferHardwarePipeline: false, preferHardwareEncoder: false, exportPlan: plan)
            func option(_ name: String) -> String? { args.firstIndex(of: name).map { args[$0 + 1] } }
            XCTAssertEqual(option("-c:v"), "libx265")
            XCTAssertEqual(option("-preset"), effort)
            XCTAssertEqual(option("-tag:v"), "hvc1")
            XCTAssertFalse(args.contains("-maxrate"))
            XCTAssertFalse(args.contains("-bufsize"))
        }
    }

    func testHEVCEncoderFallbackKeepsTheRequestedCodecAndAudio() async throws {
        try await requireEncoders(["libx264", "libx265"])
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp4")
        _ = try await run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=160x96:r=12:d=1", "-f", "lavfi", "-i", "sine=sample_rate=48000:duration=1", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", source.path])
        let original = try Data(contentsOf: source)
        let audioHash = try await streamHash(source, stream: "a:0")
        let wrapper = directory.appendingPathComponent("ffmpeg")
        // Emulate an Intel Mac without an available HEVC compression session.
        // All non-hardware work, including the final software encode, is real.
        let script = """
        #!/bin/sh
        for argument do
          if [ "$argument" = "hevc_videotoolbox" ]; then
            printf '%s\\n' '[hevc_videotoolbox] cannot create compression session' >&2
            exit 1
          fi
        done
        exec \(shellQuote(ffmpeg.path)) "$@"
        """
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("ffprobe"), withDestinationURL: ffprobe)

        for target in [Optional<Double>.none, 1] {
            let store = ConverterStore(ffmpegOverride: wrapper)
            store.preset = .hevcHardware
            store.outputDirectory = directory
            var item = ConversionItem(source: source)
            item.exportOptions.targetSizeMB = target
            store.items = [item]
            store.start()
            let output = try await completed(store)
            let info = await MediaInspector.inspect(at: output, using: ffprobe)
            XCTAssertEqual(info.videoCodec, "hevc", "An unavailable hardware session must not silently change HEVC to H.264")
            XCTAssertEqual(info.width, 160)
            XCTAssertEqual(info.height, 96)
            XCTAssertEqual(info.audioTrackCount, 1)
            XCTAssertEqual(try XCTUnwrap(info.duration), 1, accuracy: 0.1)
            try await assertHEVCTagAndDecode(output)
            if target == nil {
                let outputAudioHash = try await streamHash(output, stream: "a:0")
                XCTAssertEqual(outputAudioHash, audioHash)
            }
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.contains(".partial") })
    }

    func testHEVCCopyAndLosslessMergeUseNativeCompatibleTag() async throws {
        try await requireEncoders(["libx265"])
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.mp4")
        _ = try await run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=160x96:r=12:d=1", "-c:v", "libx265", "-preset", "ultrafast", "-tag:v", "hev1", first.path])
        let second = directory.appendingPathComponent("second.mp4")
        try FileManager.default.copyItem(at: first, to: second)
        let sourceHash = try await streamHash(first, stream: "v:0")
        for preset in [ConversionPreset.smartMP4, .remux] {
            let store = ConverterStore(ffmpegOverride: ffmpeg)
            store.preset = preset
            store.outputDirectory = directory
            store.items = [ConversionItem(source: first)]
            store.start()
            let output = try await completed(store)
            try await assertHEVCTagAndDecode(output)
            let outputVideoHash = try await streamHash(output, stream: "v:0")
            XCTAssertEqual(outputVideoHash, sourceHash, "A compatibility tag must not re-encode movie packets")
        }
        let merge = ConverterStore(ffmpegOverride: ffmpeg)
        merge.outputDirectory = directory
        merge.items = [ConversionItem(source: first), ConversionItem(source: second)]
        merge.mergeWaitingItems()
        let deadline = TestDeadline(seconds: 30)
        while merge.isMerging && deadline.hasTimeRemaining { try await Task.sleep(nanoseconds: 20_000_000) }
        if merge.isMerging { merge.cancel(); XCTFail("Lossless merge timed out") }
        let merged = try XCTUnwrap(merge.mergeOutput, merge.mergeNotice)
        try await assertHEVCTagAndDecode(merged)
        let info = await MediaInspector.inspect(at: merged, using: ffprobe)
        XCTAssertEqual(try XCTUnwrap(info.duration), 2, accuracy: 0.1)
    }

    private func assertHEVCTagAndDecode(_ url: URL) async throws {
        let result = try await run(ffprobe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name,codec_tag_string", "-of", "json", url.path])
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: result.standardOutput) as? [String: Any])
        let stream = try XCTUnwrap((response["streams"] as? [[String: Any]])?.first)
        XCTAssertEqual(stream["codec_name"] as? String, "hevc")
        XCTAssertEqual(stream["codec_tag_string"] as? String, "hvc1")
        _ = try await run(ffmpeg, ["-v", "error", "-xerror", "-i", url.path, "-map", "0:v:0", "-map", "0:a?", "-f", "null", "-"])
    }
    private func streamHash(_ url: URL, stream: String) async throws -> Data {
        try await run(ffmpeg, ["-v", "error", "-i", url.path, "-map", "0:\(stream)", "-c", "copy", "-f", "hash", "-"]).standardOutput
    }
    private func requireEncoders(_ names: [String]) async throws {
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else { throw XCTSkip("FFmpeg is required") }
        let result = try await run(ffmpeg, ["-hide_banner", "-encoders"])
        let encoders = String(decoding: result.standardOutput, as: UTF8.self)
        guard names.allSatisfy({ encoders.contains(" \($0) ") }) else { throw XCTSkip("Synthetic codec regression requires \(names.joined(separator: ", "))") }
    }
    private func run(_ tool: URL, _ args: [String]) async throws -> FFmpegProcessRunner.Result {
        let result = await FFmpegProcessRunner(executable: tool, arguments: args, configuration: .init(inactivityTimeout: 30)).run()
        guard result.succeeded else { XCTFail(result.standardError); throw CocoaError(.fileReadCorruptFile) }
        return result
    }
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-codec-regression-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func completed(_ store: ConverterStore) async throws -> URL {
        let deadline = TestDeadline(seconds: 45)
        while store.isRunning && deadline.hasTimeRemaining { try await Task.sleep(nanoseconds: 20_000_000) }
        if store.isRunning { store.cancel(); XCTFail("Synthetic export timed out") }
        guard case .complete(let output) = store.items.first?.state else {
            XCTFail("Export failed: \(String(describing: store.items.first?.failure))")
            throw CocoaError(.fileReadCorruptFile)
        }
        return output
    }
    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
