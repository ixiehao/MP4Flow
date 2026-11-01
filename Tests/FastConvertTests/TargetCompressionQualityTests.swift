import Foundation
import XCTest
@testable import FastConvert

@MainActor final class TargetCompressionQualityTests: XCTestCase {
    private var ffmpeg: URL { DependencyToolResolver.resolve().ffmpeg ?? URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg") }
    private var ffprobe: URL { ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe") }

    func testSizeBudgetUsesQualityAwareOfflineEncodingAndLeavesNormalPathsUnchanged() throws {
        let info = fixtureInfo()
        let limited = try ExportPlan(options: ExportOptions(targetSizeMB: 8), info: info, trim: nil, preset: .smartMP4, canBurnSubtitles: false)
        let unlimited = try ExportPlan(options: ExportOptions(), info: info, trim: nil, preset: .smartMP4, canBurnSubtitles: false)
        for preset in [ConversionPreset.smartMP4, .h264Hardware, .h264Software, .qualityTop, .h264Cap8, .remux] {
            XCTAssertEqual(limited.encodingPreset(for: preset), .h264Software)
            XCTAssertEqual(unlimited.encodingPreset(for: preset), preset)
        }
        XCTAssertEqual(limited.encodingPreset(for: .hevcHardware), .hevcHardware)
        for (quality, effort) in [(ConversionQuality.compact, "fast"), (.balanced, "medium"), (.high, "slow")] {
            let args = arguments(info: info, plan: limited, preset: .h264Hardware, quality: quality)
            XCTAssertEqual(option("-preset", in: args), effort, "A size budget must not ignore the quality selection")
            XCTAssertEqual(option("-c:v", in: args), "libx264")
            XCTAssertFalse(args.contains("-hwaccel"))
            XCTAssertFalse(args.contains("-crf"))
            XCTAssertFalse(args.contains("-maxrate"), "A file-size budget is not a real-time streaming ceiling")
        }
        let hardware = arguments(info: info, plan: unlimited, preset: .h264Hardware, quality: .high)
        XCTAssertEqual(option("-c:v", in: hardware), "h264_videotoolbox")
        let software = arguments(info: info, plan: unlimited, preset: .h264Software, quality: .high)
        XCTAssertEqual(option("-crf", in: software), "18")
    }

    func testEnablingSizeLimitDoesNotSuggestAnImplicitReductionOrDisableQuality() {
        XCTAssertNil(ExportOptions().targetSizeMB)
        XCTAssertEqual(ExportOptions.suggestedTargetMegabytes(sourceBytes: 11_038_774), 12)
        XCTAssertEqual(ExportOptions.suggestedTargetMegabytes(sourceBytes: 5_000_000_000), 5_000)
        XCTAssertEqual(ExportOptions.suggestedTargetMegabytes(sourceBytes: 1), 1)
        XCTAssertEqual(ExportOptions.suggestedTargetMegabytes(sourceBytes: Int64.max), 100_000)
        XCTAssertEqual(ExportOptions.suggestedTargetMegabytes(sourceBytes: nil), 100)
        let store = ConverterStore()
        store.preset = .remux
        XCTAssertTrue(store.usesFixedQuality)
        var item = ConversionItem(source: URL(fileURLWithPath: "/tmp/quality.mp4"))
        item.exportOptions.targetSizeMB = 8
        store.items = [item]
        XCTAssertFalse(store.usesFixedQuality)
        XCTAssertEqual(store.qualityDescription, L10n.text("目标体积优先，高画质更慢。"))
        XCTAssertTrue(item.exportOptions.summary.contains(L10n.format("目标约 %@ · 体积优先", L10n.byteCount(8_000_000))))
    }

    func testCompressedPicturesImproveAgainstThePreviousSpeedFirstEncoder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("motion.mp4")
        _ = try await run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=25:duration=16", "-f", "lavfi", "-i", "sine=frequency=660:duration=16", "-c:v", "libx264", "-preset", "medium", "-crf", "24", "-c:a", "aac", "-b:a", "128k", source.path])
        let info = await MediaInspector.inspect(at: source, using: ffprobe)
        let plan = try TargetSizePlan(megabytes: 1, duration: info.duration, audioTracks: 1, sourceVideoRate: info.videoRate)
        let old = directory.appendingPathComponent("speed-first.mp4")
        _ = try await run(ffmpeg, ["-v", "error", "-i", source.path, "-c:v", "h264_videotoolbox", "-prio_speed", "1", "-b:v", "\(plan.videoRate)", "-maxrate", "\(Int(Double(plan.videoRate) * 1.25))", "-bufsize", "\(plan.videoRate * 2)", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", old.path])
        let output = try await converted(source, directory: directory, megabytes: 1)
        let before = try await similarity(source, old)
        let after = try await similarity(source, output)
        XCTAssertGreaterThan(after, before + 0.01, "The regression must check decoded detail, not just a playable file: \(before) -> \(after)")
        let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(bytes, 700_000)
        XCTAssertLessThan(bytes, 1_150_000)
        print("Synthetic size-budget SSIM: \(before) -> \(after); bytes: \(bytes)")
    }

    func testAuthorizedLowBitrateSourceAtEightMegabytesAndUnlimitedPacketCopy() async throws {
        guard let path = ProcessInfo.processInfo.environment["MP4FLOW_QUALITY_INPUT"] else {
            throw XCTSkip("Set MP4FLOW_QUALITY_INPUT to an authorized low-bitrate source")
        }
        let source = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: source)
        let directory: URL
        let retained = ProcessInfo.processInfo.environment["MP4FLOW_QUALITY_ARTIFACTS"]
        if let retained {
            directory = URL(fileURLWithPath: retained, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } else { directory = try temporaryDirectory() }
        defer { if retained == nil { try? FileManager.default.removeItem(at: directory) } }
        let output = try await converted(source, directory: directory, megabytes: 8)
        let actual = await MediaInspector.inspect(at: output, using: ffprobe)
        let reference = await MediaInspector.inspect(at: source, using: ffprobe)
        XCTAssertEqual(actual.width, reference.width)
        XCTAssertEqual(actual.height, reference.height)
        XCTAssertEqual(actual.audioTrackCount, reference.audioTrackCount)
        XCTAssertEqual(try XCTUnwrap(actual.duration), try XCTUnwrap(reference.duration), accuracy: 0.15)
        let score = try await similarity(source, output)
        XCTAssertGreaterThan(score, 0.98)
        let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(bytes, 7_000_000)
        XCTAssertLessThan(bytes, 8_500_000)
        let copied = try await converted(source, directory: directory, megabytes: nil)
        for stream in ["v:0", "a:0"] {
            let sourceHash = try await run(ffmpeg, ["-v", "error", "-i", source.path, "-map", "0:\(stream)", "-c", "copy", "-f", "hash", "-hash", "sha256", "-"]).standardOutput
            let copiedHash = try await run(ffmpeg, ["-v", "error", "-i", copied.path, "-map", "0:\(stream)", "-c", "copy", "-f", "hash", "-hash", "sha256", "-"]).standardOutput
            XCTAssertEqual(sourceHash, copiedHash, "Without the optional limit, Smart Convert must preserve the original packets")
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        print("Authorized full-source target export: \(bytes) bytes; SSIM \(score); unlimited video/audio hashes unchanged")
    }

    private func converted(_ source: URL, directory: URL, megabytes: Double?) async throws -> URL {
        let store = ConverterStore(ffmpegOverride: ffmpeg)
        store.preset = .smartMP4; store.quality = .high; store.outputDirectory = directory
        var item = ConversionItem(source: source)
        item.exportOptions.targetSizeMB = megabytes
        store.items = [item]; store.start()
        var sawSoftware = false
        let deadline = TestDeadline(seconds: 180)
        while store.isRunning && deadline.hasTimeRemaining {
            sawSoftware = sawSoftware || store.items.first?.phase == .softwareTranscoding
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if store.isRunning { store.cancel(); XCTFail("Quality export timed out") }
        if megabytes != nil { XCTAssertTrue(sawSoftware, "The displayed phase must match the actual encoder") }
        guard case .complete(let output) = store.items.first?.state else {
            XCTFail("Export failed: \(String(describing: store.items.first?.failure))")
            throw TestError.failed
        }
        return output
    }

    private func similarity(_ source: URL, _ output: URL) async throws -> Double {
        let result = try await run(ffmpeg, ["-hide_banner", "-nostats", "-i", source.path, "-i", output.path, "-lavfi", "[0:v]setpts=PTS-STARTPTS[r];[1:v]setpts=PTS-STARTPTS[t];[r][t]ssim", "-an", "-f", "null", "-"])
        let marker = try XCTUnwrap(result.standardError.range(of: "All:", options: .backwards))
        return try XCTUnwrap(Double(result.standardError[marker.upperBound...].prefix { $0.isNumber || $0 == "." }))
    }
    private func run(_ executable: URL, _ args: [String]) async throws -> FFmpegProcessRunner.Result {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw XCTSkip("FFmpeg is required") }
        let result = await FFmpegProcessRunner(executable: executable, arguments: args, configuration: .init(inactivityTimeout: 90)).run()
        guard result.succeeded else { XCTFail("Media command failed: \(result.standardError)"); throw TestError.failed }
        return result
    }
    private func arguments(info: VideoInfo, plan: ExportPlan, preset: ConversionPreset, quality: ConversionQuality) -> [String] {
        FFmpegCommandBuilder.arguments(source: URL(fileURLWithPath: "/tmp/source.mp4"), output: URL(fileURLWithPath: "/tmp/output.mp4"), info: info, preset: preset, quality: quality, resolution: .original, trim: nil, rotation: nil, crop: nil, aspectRatio: nil, imageAdjustment: ImageAdjustment(), copyVideoAndEncodeAudio: false, preferHardwarePipeline: true, preferHardwareEncoder: true, exportPlan: plan)
    }
    private func option(_ name: String, in args: [String]) -> String? { args.firstIndex(of: name).map { args[$0 + 1] } }
    private func fixtureInfo() -> VideoInfo {
        VideoInfo(duration: 140, videoRate: 495_453, audioRate: 128_000, width: 1280, height: 720, hasVideo: true, videoCodec: "h264", audioCodec: "aac", frameRate: "25/1", pixelFormat: "yuv420p", audioSampleRate: "48000", audioChannels: 2, audioTrackCount: 1, subtitleTrackCount: 0, colorTransfer: nil, probeSucceeded: true)
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-quality-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private enum TestError: Error { case failed }
}
