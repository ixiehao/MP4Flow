import AVFoundation
import XCTest
@testable import FastConvert

private final class LockedCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

final class SmartEnhanceTests: XCTestCase {
    func testShortVideoWithAudioExportsAndRetriesAfterCancellation() async throws {
#if compiler(>=6.4)
        guard #available(macOS 27.0, *), SmartEnhanceExporter.isSupported else {
            throw XCTSkip("Native super-resolution is unavailable on this SDK or Mac.")
        }
        guard let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("FFmpeg is unavailable for the generated media fixture.")
        }

        let info = VideoInfo(
            duration: 1, videoRate: 500_000, audioRate: 128_000,
            width: 320, height: 240, hasVideo: true,
            videoCodec: "mpeg4", audioCodec: "aac", frameRate: "12/1",
            pixelFormat: "yuv420p", audioSampleRate: "48000", audioChannels: 1,
            audioTrackCount: 1, subtitleTrackCount: 0,
            colorTransfer: nil, probeSucceeded: true
        )
        guard let target = SmartEnhancePlan.availableTargets(sourceWidth: 320, sourceHeight: 240).first,
              let plan = SmartEnhancePlan.make(info: info, target: target) else {
            throw XCTSkip("The installed VideoToolbox scaler has no supported target for this fixture.")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mp4flow-enhance-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.mp4")
        let source = directory.appendingPathComponent("source-with-cover.mp4")
        let cover = directory.appendingPathComponent("cover.jpg")
        let output = directory.appendingPathComponent("enhanced.mp4")
        let generator = Process()
        generator.executableURL = URL(fileURLWithPath: ffmpeg)
        generator.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=12",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
            "-t", "1", "-c:v", "mpeg4", "-q:v", "5",
            "-c:a", "aac", "-shortest", original.path
        ]
        try generator.run()
        generator.waitUntilExit()
        guard generator.terminationStatus == 0 else {
            XCTFail("Could not generate the input fixture (exit \(generator.terminationStatus)).")
            return
        }

        let tool = URL(fileURLWithPath: ffmpeg)
        let picture = await FFmpegProcessRunner(executable: tool, arguments: [
            "-v", "error", "-f", "lavfi", "-i", "color=red:size=640x480", "-frames:v", "1", cover.path
        ]).run()
        let attach = await FFmpegProcessRunner(executable: tool, arguments: [
            "-v", "error", "-i", original.path, "-i", cover.path, "-map", "0", "-map", "1:v",
            "-c", "copy", "-disposition:v:1", "attached_pic", source.path
        ]).run()
        XCTAssertTrue(picture.succeeded && attach.succeeded)
        let inspected = await ConverterStore.inspectMedia(at: source, using: tool.deletingLastPathComponent().appendingPathComponent("ffprobe"))
        XCTAssertEqual(inspected.videoTrackCount, 1)
        let trackID = try XCTUnwrap(inspected.selectedVideoTrackID)

        let started = ProcessInfo.processInfo.systemUptime
        try await SmartEnhanceExporter().export(
            source: source, output: output, plan: plan, trim: nil,
            videoBitRate: 1_000_000, videoTrackID: trackID, shouldCancel: { false }, onProgress: { _ in }
        )
        print("Smart Enhance native export completed in \(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - started)) seconds")

        let asset = AVURLAsset(url: output)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertEqual(audio.count, 1)
        let size = try await video[0].load(.naturalSize)
        XCTAssertEqual(Int(size.width), plan.targetWidth)
        XCTAssertEqual(Int(size.height), plan.targetHeight)
        XCTAssertGreaterThan(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)

        let playbackReader = try AVAssetReader(asset: asset)
        let decodedVideo = AVAssetReaderTrackOutput(track: video[0], outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        let decodedAudio = AVAssetReaderTrackOutput(track: audio[0], outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM
        ])
        playbackReader.add(decodedVideo)
        playbackReader.add(decodedAudio)
        XCTAssertTrue(playbackReader.startReading())
        XCTAssertNotNil(decodedVideo.copyNextSampleBuffer(), "The enhanced video must decode.")
        XCTAssertNotNil(decodedAudio.copyNextSampleBuffer(), "The output audio must decode.")
        playbackReader.cancelReading()

        let cancelledOutput = directory.appendingPathComponent("cancelled.mp4")
        let cancellation = LockedCancellationFlag()
        do {
            try await SmartEnhanceExporter().export(
                source: source, output: cancelledOutput, plan: plan, trim: nil,
                videoBitRate: 1_000_000, videoTrackID: trackID,
                shouldCancel: { cancellation.isCancelled() },
                onProgress: { _ in cancellation.cancel() }
            )
            XCTFail("The in-progress export should have stopped after its first frame.")
        } catch is CancellationError {
            // Cancellation is expected; the next export must start cleanly.
        }
        try? FileManager.default.removeItem(at: cancelledOutput)
        try await SmartEnhanceExporter().export(
            source: source, output: cancelledOutput, plan: plan, trim: nil,
            videoBitRate: 1_000_000, videoTrackID: trackID, shouldCancel: { false }, onProgress: { _ in }
        )
        XCTAssertGreaterThan(try cancelledOutput.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
        let retryAsset = AVURLAsset(url: cancelledOutput)
        let retryTracks = try await retryAsset.loadTracks(withMediaType: .video)
        guard let retryTrack = retryTracks.first else {
            XCTFail("The retry must contain a video track.")
            return
        }
        let retryReader = try AVAssetReader(asset: retryAsset)
        let retryVideo = AVAssetReaderTrackOutput(track: retryTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        retryReader.add(retryVideo)
        XCTAssertTrue(retryReader.startReading())
        XCTAssertNotNil(retryVideo.copyNextSampleBuffer(), "The retry must produce decodable video.")
        retryReader.cancelReading()

        // A source display matrix must survive enhancement even though the
        // reader returns unrotated pixels and the encoded dimensions change.
        for angle in [90, 180] {
            let rotated = directory.appendingPathComponent("source-\(angle).mp4")
            let enhanced = directory.appendingPathComponent("enhanced-\(angle).mp4")
            let rotation = await FFmpegProcessRunner(executable: tool, arguments: [
                "-v", "error", "-display_rotation:v:0", "\(angle)", "-i", source.path,
                "-map", "0:V:0", "-map", "0:a:0?", "-c", "copy", rotated.path
            ]).run()
            XCTAssertTrue(rotation.succeeded)
            let rotatedAsset = AVURLAsset(url: rotated)
            let sourceTracks = try await rotatedAsset.loadTracks(withMediaType: .video)
            let sourceTrack = try XCTUnwrap(sourceTracks.first)
            let expected = try await sourceTrack.load(.preferredTransform)
            let inspected = await ConverterStore.inspectMedia(at: rotated, using: tool.deletingLastPathComponent().appendingPathComponent("ffprobe"))
            try await SmartEnhanceExporter().export(
                source: rotated, output: enhanced, plan: plan, trim: nil,
                videoBitRate: 1_000_000, videoTrackID: inspected.selectedVideoTrackID,
                shouldCancel: { false }, onProgress: { _ in }
            )
            let outputAsset = AVURLAsset(url: enhanced)
            let outputTracks = try await outputAsset.loadTracks(withMediaType: .video)
            let outputTrack = try XCTUnwrap(outputTracks.first)
            let actual = try await outputTrack.load(.preferredTransform)
            for (actualValue, expectedValue) in zip([actual.a, actual.b, actual.c, actual.d], [expected.a, expected.b, expected.c, expected.d]) {
                XCTAssertEqual(actualValue, expectedValue, accuracy: 0.001, "Enhancement must retain source orientation: \(angle)°")
            }
            let encodedBounds = CGRect(x: 0, y: 0, width: CGFloat(plan.targetWidth), height: CGFloat(plan.targetHeight))
            let displayedBounds = encodedBounds.applying(actual)
            let expectedBounds = encodedBounds.applying(expected)
            XCTAssertEqual(displayedBounds.minX, 0, accuracy: 0.01)
            XCTAssertEqual(displayedBounds.minY, 0, accuracy: 0.01)
            XCTAssertEqual(displayedBounds.width, expectedBounds.width, accuracy: 0.01)
            XCTAssertEqual(displayedBounds.height, expectedBounds.height, accuracy: 0.01)
            let decoded = await FFmpegProcessRunner(executable: tool, arguments: [
                "-v", "error", "-xerror", "-i", enhanced.path, "-f", "null", "-"
            ]).run()
            XCTAssertTrue(decoded.succeeded, "Rotated enhancement output must decode")
        }
#else
        throw XCTSkip("The compiler lacks the native super-resolution API.")
#endif
    }
}
