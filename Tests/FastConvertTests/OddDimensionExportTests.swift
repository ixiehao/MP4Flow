import Foundation
import XCTest
@testable import FastConvert

@MainActor final class OddDimensionExportTests: XCTestCase {
    func testUntrustedPresentationDimensionsCannotTrapTheQueue() {
        let invalid: [CGFloat] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude, 0, CGFloat(Int.max)]
        for value in invalid {
            XCTAssertNil(VideoPresentation.pixelDimension(value))
        }
        XCTAssertEqual(VideoPresentation.pixelDimension(-1920), 1920)
        XCTAssertEqual(VideoPresentation.pixelDimension(1079.8), 1080)
    }

    func testInvalidDurationsRemainAbsentInRestoredAndInspectedFacts() {
        let invalid = [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, Double(Int.max), -1, 0]
        for duration in invalid {
            XCTAssertEqual(VideoPresentation.boundedDuration(duration), 0)
            let presentation = VideoPresentation(duration: duration, fileSize: nil, thumbnail: nil, width: nil, height: nil)
            XCTAssertTrue(presentation.factFields.isEmpty)
            // VideoInfo's immutable duration comes from ffprobe, including a
            // successfully parsed but unrepresentable finite numeric string.
            let info = VideoInfo(duration: duration, videoRate: nil, audioRate: nil, width: nil, height: nil, hasVideo: true, videoCodec: "h264", audioCodec: nil, frameRate: nil, pixelFormat: nil, audioSampleRate: nil, audioChannels: nil, audioTrackCount: 0, subtitleTrackCount: 0, colorTransfer: nil, probeSucceeded: true)
            XCTAssertEqual(VideoPresentation.inspected(info, previous: nil).duration, 0)
        }
        XCTAssertEqual(VideoPresentation.boundedDuration(86_400), 86_400)
    }

    func testOriginalSizeOddFramesEncodeWithoutCroppingOrStretching() async throws {
        let ffmpeg = try XCTUnwrap(DependencyToolResolver.resolve().ffmpeg)
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-odd-regression-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("odd-lossless.mkv")
        // Full-range RGB marks all four source edges; FFV1 permits odd sizes.
        _ = try await run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "color=white:s=319x179:r=12:d=0.5,format=rgb24", "-vf", "drawbox=x=158:y=10:w=3:h=159:color=black:t=fill,drawbox=x=10:y=88:w=299:h=3:color=black:t=fill", "-c:v", "ffv1", source.path])
        let before = try Data(contentsOf: source)
        let probed = await MediaInspector.inspect(at: source, using: ffprobe)
        XCTAssertEqual(probed.width, 319)
        XCTAssertEqual(probed.height, 179)
        for preset in [ConversionPreset.h264Software, .h264Hardware] {
            for rotation: VideoRotation? in [nil, .clockwise] {
                let store = ConverterStore(ffmpegOverride: ffmpeg)
                store.preset = preset
                store.outputDirectory = directory
                var item = ConversionItem(source: source)
                item.rotation = rotation
                store.items = [item]
                store.start()
                let deadline = TestDeadline(seconds: 30)
                while store.isRunning && deadline.hasTimeRemaining { try await Task.sleep(nanoseconds: 20_000_000) }
                if store.isRunning { store.cancel(); XCTFail("Odd-sized export timed out") }
                guard case .complete(let output) = store.items.first?.state else {
                    XCTFail("\(preset)/\(String(describing: rotation)): \(String(describing: store.items.first?.failure))")
                    throw CocoaError(.fileReadCorruptFile)
                }
                let result = await MediaInspector.inspect(at: output, using: ffprobe)
                XCTAssertEqual(result.width, rotation == nil ? 320 : 180)
                XCTAssertEqual(result.height, rotation == nil ? 180 : 320)
                XCTAssertEqual(try XCTUnwrap(result.duration), 0.5, accuracy: 0.1)
                _ = try await run(ffmpeg, ["-v", "error", "-xerror", "-i", output.path, "-f", "null", "-"])
                let width = try XCTUnwrap(result.width), height = try XCTUnwrap(result.height)
                let frame = try await run(ffmpeg, ["-v", "error", "-i", output.path, "-frames:v", "1", "-vf", "format=gray", "-f", "rawvideo", "-"]).standardOutput
                XCTAssertEqual(frame.count, width * height)
                guard frame.count == width * height else { continue }
                let pixels = [UInt8](frame)
                // A one-pixel pad keeps the center cross and all four white
                // source corners; no aspect-fitting scale or crop is allowed.
                let points = rotation == nil ? [(1, 1), (317, 1), (1, 177), (317, 177)] : [(1, 1), (177, 1), (1, 317), (177, 317)]
                for (x, y) in points { XCTAssertGreaterThan(pixels[y * width + x], 200) }
                XCTAssertLessThan(pixels[(height / 2 - 1) * width + width / 2 - 1], 60)
            }
        }
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.contains(".partial") })
    }

    private func run(_ executable: URL, _ arguments: [String]) async throws -> FFmpegProcessRunner.Result {
        let result = await FFmpegProcessRunner(executable: executable, arguments: arguments, configuration: .init(inactivityTimeout: 30)).run()
        guard result.succeeded else { XCTFail(result.standardError); throw CocoaError(.fileReadCorruptFile) }
        return result
    }
}
