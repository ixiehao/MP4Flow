import Foundation
import XCTest
@testable import FastConvert

final class MergeGeometryTests: XCTestCase {
    @MainActor
    func testCompatibleMergeNormalizesAnamorphicPixelsWithoutStretchingContent() async throws {
        try await checkAnamorphicMerge(rotateFirst: false)
    }

    @MainActor
    func testCompatibleMergeUsesRotatedDisplayCanvasWithoutStretchingContent() async throws {
        try await checkAnamorphicMerge(rotateFirst: true)
    }

    @MainActor
    private func checkAnamorphicMerge(rotateFirst: Bool) async throws {
        let tools = try mediaTools()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("anamorphic.mp4")
        let second = directory.appendingPathComponent("square.mp4")
        try await makeVideo(first, sar: "4/3", ffmpeg: tools.ffmpeg)
        try await makeVideo(second, sar: "1", ffmpeg: tools.ffmpeg)
        let displayedFirst: URL
        if rotateFirst {
            displayedFirst = directory.appendingPathComponent("rotated-anamorphic.mp4")
            let rotation = await FFmpegProcessRunner(executable: tools.ffmpeg, arguments: [
                "-v", "error", "-nostdin", "-display_rotation:v:0", "90", "-i", first.path, "-c", "copy", "-y", displayedFirst.path
            ]).run()
            XCTAssertTrue(rotation.succeeded)
        } else {
            displayedFirst = first
        }

        let store = ConverterStore()
        store.outputDirectory = directory
        store.items = [ConversionItem(source: displayedFirst), ConversionItem(source: second)]
        store.mergeWaitingItems()
        try await waitForMerge(store)
        XCTAssertTrue(store.showCompatibleMergePrompt, "Different pixel aspect ratios must not be stream-concatenated")
        XCTAssertNil(store.mergeOutput)
        guard store.showCompatibleMergePrompt else { return }

        store.startCompatibleMerge()
        try await waitForMerge(store)
        let output = try XCTUnwrap(store.mergeOutput, store.mergeNotice)
        let info = await ConverterStore.inspectMedia(at: output, using: tools.ffprobe)
        XCTAssertTrue(info.hasVideo)
        XCTAssertEqual(info.duration ?? 0, 2, accuracy: 0.15)
        XCTAssertEqual(info.displayGeometry?.hasSquarePixels, true)
        let width = try XCTUnwrap(info.width)
        let height = try XCTUnwrap(info.height)
        XCTAssertEqual(Double(width) / Double(height), rotateFirst ? 9.0 / 16 : 16.0 / 9, accuracy: 0.01)
        let frame = await FFmpegProcessRunner(executable: tools.ffmpeg, arguments: [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-i", output.path,
            "-frames:v", "1", "-vf", "format=gray", "-f", "rawvideo", "-"
        ]).run()
        XCTAssertTrue(frame.succeeded)
        XCTAssertEqual(frame.standardOutput.count, width * height)
        guard frame.standardOutput.count == width * height else { return }
        let pixels = [UInt8](frame.standardOutput)
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] > 180 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThan(maxX, minX)
        XCTAssertGreaterThan(maxY, minY)
        XCTAssertEqual(Double(maxX - minX + 1) / Double(maxY - minY + 1), 1, accuracy: 0.04,
                       "The 60×80 encoded marker is a displayed square at SAR 4:3 and must remain square")
        let decode = await FFmpegProcessRunner(executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-xerror", "-i", output.path, "-f", "null", "-"]).run()
        XCTAssertTrue(decode.succeeded)
    }

    @MainActor
    func testLosslessMergeRejectsDifferentVideoTimeBasesAndDisplayRotations() async throws {
        let tools = try mediaTools()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("baseline.mp4")
        let clock = directory.appendingPathComponent("different-clock.mp4")
        let rotated = directory.appendingPathComponent("rotated.mp4")
        try await makeVideo(first, sar: "1", ffmpeg: tools.ffmpeg)
        let retimed = await FFmpegProcessRunner(executable: tools.ffmpeg, arguments: [
            "-v", "error", "-nostdin", "-i", first.path, "-c", "copy", "-video_track_timescale", "90000", "-y", clock.path
        ]).run()
        XCTAssertTrue(retimed.succeeded)
        let rotation = await FFmpegProcessRunner(executable: tools.ffmpeg, arguments: [
            "-v", "error", "-nostdin", "-display_rotation:v:0", "90", "-i", first.path, "-c", "copy", "-y", rotated.path
        ]).run()
        XCTAssertTrue(rotation.succeeded)
        for second in [clock, rotated] {
            let store = ConverterStore()
            store.outputDirectory = directory
            store.items = [ConversionItem(source: first), ConversionItem(source: second)]
            store.mergeWaitingItems()
            try await waitForMerge(store)
            XCTAssertTrue(store.showCompatibleMergePrompt, "Different stream clocks or display orientation require normalized merging")
            XCTAssertNil(store.mergeOutput)
        }
    }

    private func mediaTools() throws -> (ffmpeg: URL, ffprobe: URL) {
        for root in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let ffmpeg = URL(fileURLWithPath: root).appendingPathComponent("ffmpeg")
            let ffprobe = URL(fileURLWithPath: root).appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffmpeg.path), FileManager.default.isExecutableFile(atPath: ffprobe.path) { return (ffmpeg, ffprobe) }
        }
        throw XCTSkip("FFmpeg and ffprobe are required")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-MergeGeometry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeVideo(_ output: URL, sar: String, ffmpeg: URL) async throws {
        let encoders = await FFmpegProcessRunner(executable: ffmpeg, arguments: ["-hide_banner", "-encoders"]).run()
        guard encoders.succeeded, String(decoding: encoders.standardOutput, as: UTF8.self).contains(" libx264 ") else { throw XCTSkip("libx264 is required") }
        let result = await FFmpegProcessRunner(executable: ffmpeg, arguments: [
            "-v", "error", "-nostdin", "-f", "lavfi", "-i", "color=black:size=320x240:rate=12:duration=1",
            "-vf", "drawbox=x=100:y=80:w=60:h=80:color=white:t=fill,setsar=\(sar)",
            "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-y", output.path
        ]).run()
        XCTAssertTrue(result.succeeded, "Synthetic merge fixture generation must succeed")
    }

    @MainActor
    private func waitForMerge(_ store: ConverterStore) async throws {
        let deadline = Date().addingTimeInterval(20)
        while store.isMerging && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        if store.isMerging { store.cancel(); XCTFail("Merge did not finish within the test deadline") }
    }
}
