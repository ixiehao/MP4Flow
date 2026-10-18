import Foundation
import XCTest
@testable import FastConvert

final class GeometryRegressionTests: XCTestCase {
    @MainActor
    func testSoftwareRotationAndResizePreserveAnamorphicDisplayRatio() async throws {
        try await checkAnamorphicRotation(preset: .h264Software)
    }

    @MainActor
    func testHardwareRotationAndResizePreserveAnamorphicDisplayRatio() async throws {
        let ffmpeg = try mediaTools().ffmpeg
        guard try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-nostdin",
            "-f", "lavfi", "-i", "color=size=320x240:rate=12:duration=0.1",
            "-c:v", "h264_videotoolbox", "-allow_sw", "0", "-frames:v", "1", "-f", "null", "-"
        ]).status == 0 else {
            throw XCTSkip("A working VideoToolbox H.264 hardware encoder is required")
        }
        try await checkAnamorphicRotation(preset: .h264Hardware)
    }

    @MainActor
    private func checkAnamorphicRotation(preset: ConversionPreset) async throws {
        let tools = try mediaTools()
        let encoders = try run(tools.ffmpeg, ["-hide_banner", "-encoders"])
        guard encoders.status == 0, String(decoding: encoders.output, as: UTF8.self).contains(" libx264 ") else {
            throw XCTSkip("FFmpeg libx264 is required to generate the anamorphic fixture")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-GeometryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("anamorphic.mp4")
        let fixture = try run(tools.ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-nostdin",
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=12:duration=1.2",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1.2",
            "-vf", "setsar=4/3", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-shortest", "-y", source.path
        ])
        guard fixture.status == 0 else { return XCTFail("Generating the anamorphic fixture failed with code \(fixture.status)") }
        let original = try probe(source, using: tools.ffprobe)
        let sourceVideo = try XCTUnwrap(original.streams.first { $0["codec_type"] as? String == "video" })
        XCTAssertEqual(sourceVideo["sample_aspect_ratio"] as? String, "4:3")
        XCTAssertEqual(sourceVideo["display_aspect_ratio"] as? String, "16:9")

        for resolution: OutputResolution in [.original, .p480] {
            let store = ConverterStore()
            store.preset = preset
            store.outputResolution = resolution
            store.outputDirectory = directory
            let item = ConversionItem(source: source)
            store.items = [item]
            store.scheduleRotation(item, rotation: .clockwise)
            store.start()
            let deadline = Date().addingTimeInterval(20)
            while store.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if store.isRunning {
                store.cancel()
                return XCTFail("The anamorphic conversion did not complete within 20 seconds")
            }
            guard case .complete(let output) = store.items[0].state else {
                return XCTFail("Expected \(preset.rawValue)/\(resolution.rawValue) to complete; got \(store.items[0].state)")
            }

            let result = try probe(output, using: tools.ffprobe)
            let video = try XCTUnwrap(result.streams.first { $0["codec_type"] as? String == "video" })
            let audio = try XCTUnwrap(result.streams.first { $0["codec_type"] as? String == "audio" })
            let width = try XCTUnwrap(video["width"] as? Int)
            let height = try XCTUnwrap(video["height"] as? Int)
            let sar = try XCTUnwrap(ratio(video["sample_aspect_ratio"] as? String))
            let displayRatio = Double(width) / Double(height) * sar
            XCTAssertEqual(displayRatio, 9.0 / 16.0, accuracy: 0.001, "A quarter turn must invert the displayed 16:9 ratio")
            XCTAssertEqual(try XCTUnwrap(ratio(video["display_aspect_ratio"] as? String)), 9.0 / 16.0, accuracy: 0.001)
            XCTAssertEqual(height, resolution == .original ? 320 : 480)
            XCTAssertEqual(audio["codec_name"] as? String, "aac")
            XCTAssertEqual(result.duration, original.duration, accuracy: 0.15)
            XCTAssertEqual(try XCTUnwrap(Double(audio["duration"] as? String ?? "")), result.duration, accuracy: 0.15)
            XCTAssertEqual(try run(tools.ffmpeg, ["-v", "error", "-nostdin", "-xerror", "-i", output.path, "-map", "0:v:0", "-map", "0:a:0", "-f", "null", "-"]).status, 0)
        }
    }

    private func mediaTools() throws -> (ffmpeg: URL, ffprobe: URL) {
        for root in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let ffmpeg = URL(fileURLWithPath: root).appendingPathComponent("ffmpeg")
            let ffprobe = URL(fileURLWithPath: root).appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffmpeg.path), FileManager.default.isExecutableFile(atPath: ffprobe.path) {
                return (ffmpeg, ffprobe)
            }
        }
        throw XCTSkip("FFmpeg and ffprobe are required")
    }

    private func probe(_ source: URL, using ffprobe: URL) throws -> (streams: [[String: Any]], duration: Double) {
        let result = try run(ffprobe, ["-v", "error", "-show_streams", "-show_format", "-of", "json", source.path])
        XCTAssertEqual(result.status, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result.output) as? [String: Any])
        let streams = try XCTUnwrap(object["streams"] as? [[String: Any]])
        let format = try XCTUnwrap(object["format"] as? [String: Any])
        return (streams, try XCTUnwrap(Double(format["duration"] as? String ?? "")))
    }

    private func ratio(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 else { return nil }
        return numerator / denominator
    }

    private func run(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: Data) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}
