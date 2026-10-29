import AVFoundation
import Foundation
import XCTest
@testable import FastConvert

final class AspectCorrectionTests: XCTestCase {
    func testCustomRatiosAreBoundedReducedAndLocaleIndependent() throws {
        let fourThirds = try XCTUnwrap(DisplayAspectRatio(width: 4, height: 3))
        XCTAssertEqual(DisplayAspectRatio(widthText: "1920.0000", heightText: "1440.0000"), fourThirds)
        XCTAssertEqual(DisplayAspectRatio(widthText: "2,39", heightText: "1")?.summary, "239:100")
        XCTAssertEqual(DisplayAspectRatio(widthText: " 16 ", heightText: "9")?.summary, "16:9")
        let precise = try XCTUnwrap(DisplayAspectRatio(widthText: "9999.9998", heightText: "9999.9999"))
        XCTAssertEqual(DisplayAspectRatio(widthText: String(precise.width), heightText: String(precise.height)), precise, "Reopening a reduced custom ratio must stay valid")
        for pair in [("0", "1"), ("1", "0"), ("nan", "1"), ("inf", "1"), ("-4", "3"),
                     ("1e3", "1"), ("16:9", "1"), ("１", "1"), ("1.00001", "1"),
                     ("10001", "1"), ("1", "11"), ("11", "1"), ("1;scale=2", "1")] {
            XCTAssertNil(DisplayAspectRatio(widthText: pair.0, heightText: pair.1), "\(pair)")
        }
        XCTAssertEqual(fourThirds.outputSize(height: 480)?.width, 640)
        XCTAssertEqual(fourThirds.outputSize(height: 481)?.height, 480)
        XCTAssertNil(fourThirds.outputSize(height: 0))
        XCTAssertNil(DisplayAspectRatio(width: 10, height: 1)?.outputSize(height: 2160))
        XCTAssertEqual(DisplayAspectRatio.approximating(9.0 / 16)?.summary, "9:16")
        XCTAssertEqual(DisplayAspectRatio.approximating(3.0 / 4)?.summary, "3:4")
        XCTAssertEqual(DisplayAspectRatio.approximating(4.0 / 3)?.summary, "4:3")
        XCTAssertEqual(DisplayAspectRatio.approximating(2.39)?.summary, "239:100")
        XCTAssertNil(DisplayAspectRatio.approximating(.infinity))
    }

    func testPreviewFitsWholeFrameAndKeepsPixelShapeThroughRotations() {
        let fitted = AspectPreviewLayout.fitted(ratio: 4.0 / 3, in: CGSize(width: 720, height: 240))
        XCTAssertEqual(fitted, CGRect(x: 200, y: 0, width: 320, height: 240))
        XCTAssertEqual(AspectPreviewLayout.fitted(ratio: .nan, in: CGSize(width: 720, height: 240)), .zero)
        XCTAssertEqual(AspectGeometry.displayRatio(width: 320, height: 240, pixelRatio: 4.0 / 3, rotation: nil), 16.0 / 9, accuracy: 0.00001)
        XCTAssertEqual(AspectGeometry.displayRatio(width: 320, height: 240, pixelRatio: 4.0 / 3, rotation: .clockwise), 9.0 / 16, accuracy: 0.00001)
        XCTAssertEqual(FFmpegHardwareRetryClassifier.hint(stderr: "Unrecognized option 'display_rotation:v'.", usedHardwarePipeline: true, usedHardwareEncoder: true), .cpuDecodeAndFilter)
        XCTAssertNil(FFmpegHardwareRetryClassifier.hint(stderr: "Unrecognized option 'display_rotation:v'.", usedHardwarePipeline: false, usedHardwareEncoder: true))
    }

    @MainActor
    func testSavingResettingAndCancellingGeometryDoNotLoseOtherEditsOrOutputs() throws {
        let store = ConverterStore()
        var item = ConversionItem(source: URL(fileURLWithPath: "/fixture.mp4"))
        let oldOutput = URL(fileURLWithPath: "/finished.mp4")
        item.state = .complete(oldOutput)
        item.rotation = .clockwise
        item.trimRange = ClipRange(start: 1, end: 2)
        store.items = [item]
        store.scheduleGeometry(item, crop: nil, aspectRatio: nil)
        XCTAssertEqual(store.items[0].state, .complete(oldOutput), "Unchanged confirmation must not requeue work")
        let ratio = try XCTUnwrap(DisplayAspectRatio(width: 4, height: 3))
        store.scheduleGeometry(item, crop: nil, aspectRatio: ratio)
        XCTAssertEqual(store.items[0].state, .waiting)
        XCTAssertEqual(store.items[0].rotation, .clockwise)
        XCTAssertEqual(store.items[0].trimRange, item.trimRange)
        XCTAssertEqual(store.items[0].aspectRatio, ratio)
        XCTAssertEqual(store.mergeCandidateCount, 0)
        store.scheduleGeometry(store.items[0], crop: nil, aspectRatio: nil)
        XCTAssertNil(store.items[0].aspectRatio)
    }

    @MainActor
    func testCorrectionReshapesWholeFrameAndCopiesAudio() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeStretchedFixture(in: directory, ffmpeg: tools.ffmpeg)
        let originalBytes = try Data(contentsOf: source)
        let sourceAudio = try capture(tools.ffmpeg, ["-v", "error", "-i", source.path, "-map", "0:a:0", "-c", "copy", "-f", "hash", "-"])
        for preset in [ConversionPreset.smartMP4, .remux, .h264Software, .h264Hardware] {
            let store = ConverterStore()
            store.preset = preset
            store.outputDirectory = directory
            store.items = [ConversionItem(source: source)]
            store.scheduleGeometry(store.items[0], crop: nil, aspectRatio: DisplayAspectRatio(width: 4, height: 3))
            store.start()
            let output = try await completedOutput(store)
            let video = try probeVideo(output, tools: tools)
            XCTAssertEqual(video.width, 240)
            XCTAssertEqual(video.height, 180)
            XCTAssertEqual(video.sar, "1:1")
            XCTAssertTrue(output.lastPathComponent.contains("aspect-4x3"))
            let pixels = try capture(tools.ffmpeg, ["-v", "error", "-i", output.path, "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"])
            try assertCircleAndCorners(pixels, width: 240, height: 180)
            XCTAssertEqual(try capture(tools.ffmpeg, ["-v", "error", "-i", output.path, "-map", "0:a:0", "-c", "copy", "-f", "hash", "-"]), sourceAudio)
            try decode(output, ffmpeg: tools.ffmpeg)
        }
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    }

    @MainActor
    func testCustomCorrectionAfterCropRotationTrimAndResize() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeStretchedFixture(in: directory, ffmpeg: tools.ffmpeg)
        for (ratio, width) in [(DisplayAspectRatio(width: 9, height: 16)!, 270), (DisplayAspectRatio(widthText: "2.39", heightText: "1")!, 1148)] {
            let store = ConverterStore()
            store.preset = .h264Software
            store.outputResolution = .p480
            store.outputDirectory = directory
            store.items = [ConversionItem(source: source)]
            store.scheduleGeometry(store.items[0], crop: CropRect(x: 16, y: 12, width: 288, height: 156), aspectRatio: ratio)
            store.scheduleRotation(store.items[0], rotation: .clockwise)
            store.scheduleTrim(store.items[0], start: 0.2, end: 0.8)
            store.start()
            let output = try await completedOutput(store)
            let video = try probeVideo(output, tools: tools)
            XCTAssertEqual(video.width, width)
            XCTAssertEqual(video.height, 480)
            XCTAssertEqual(video.sar, "1:1")
            let asset = AVURLAsset(url: output)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, 0.6, accuracy: 0.12)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            _ = try generator.copyCGImage(at: .zero, actualTime: nil)
            try decode(output, ffmpeg: tools.ffmpeg)
        }
    }

    @MainActor
    func testNormalConversionsKeepAspectAcrossMetadataAndManualRotations() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = directory.appendingPathComponent("anamorphic.mp4")
        try run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=12:duration=0.5", "-vf", "setsar=4/3", "-c:v", "libx264", "-preset", "ultrafast", raw.path])
        let rotated = directory.appendingPathComponent("display-matrix.mp4")
        try run(tools.ffmpeg, ["-v", "error", "-display_rotation:v:0", "90", "-i", raw.path, "-c", "copy", rotated.path])
        let metadata = try capture(tools.ffprobe, ["-v", "error", "-show_entries", "stream_side_data=rotation", "-of", "json", rotated.path])
        XCTAssertTrue(String(decoding: metadata, as: UTF8.self).contains("90"), "Verify that the fixture actually has a display rotation")
        for source in [raw, rotated] {
            for preset in [ConversionPreset.h264Software, .h264Hardware] {
                for resolution in [OutputResolution.original, .p480] {
                    for rotation in [nil, VideoRotation.clockwise, .counterclockwise, .upsideDown] {
                        let store = ConverterStore()
                        store.preset = preset
                        store.outputResolution = resolution
                        store.outputDirectory = directory
                        store.items = [ConversionItem(source: source)]
                        store.scheduleRotation(store.items[0], rotation: rotation)
                        store.start()
                        let output = try await completedOutput(store, context: "\(source.lastPathComponent)/\(preset)/\(resolution)/\(String(describing: rotation))")
                        let video = try probeVideo(output, tools: tools)
                        let isPortrait = (source == rotated) != (rotation?.swapsDimensions == true)
                        XCTAssertEqual(video.dar, isPortrait ? 9.0 / 16 : 16.0 / 9, accuracy: 0.003, "\(source.lastPathComponent)/\(preset)/\(resolution)/\(String(describing: rotation))")
                        try decode(output, ffmpeg: tools.ffmpeg)
                    }
                }
            }
        }
    }

    @MainActor
    func testMetadataRotationAndCorrectionMatchDecodedPixelOrientation() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeStretchedFixture(in: directory, ffmpeg: tools.ffmpeg)
        let rotated = directory.appendingPathComponent("camera-rotation.mp4")
        try run(tools.ffmpeg, ["-v", "error", "-display_rotation:v:0", "90", "-i", source.path, "-c", "copy", rotated.path])
        for (preset, rotation) in [(ConversionPreset.h264Hardware, Optional<VideoRotation>.none), (.h264Software, .clockwise)] {
            let store = ConverterStore()
            store.preset = preset
            store.outputDirectory = directory
            store.items = [ConversionItem(source: rotated)]
            store.scheduleGeometry(store.items[0], crop: nil, aspectRatio: rotation == nil ? DisplayAspectRatio(width: 3, height: 4) : DisplayAspectRatio(width: 4, height: 3))
            store.scheduleRotation(store.items[0], rotation: rotation)
            store.start()
            let output = try await completedOutput(store)
            let video = try probeVideo(output, tools: tools)
            let pixels = try capture(tools.ffmpeg, ["-v", "error", "-i", output.path, "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"])
            try assertCircleAndCorners(pixels, width: video.width, height: video.height, quarterTurn: rotation == nil)
            try decode(output, ffmpeg: tools.ffmpeg)
        }
    }

    @MainActor
    func testIncorrectExportGeometryFailsVerificationWithoutPublishing() async throws {
        let tools = try mediaTools()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeStretchedFixture(in: directory, ffmpeg: tools.ffmpeg)
        let wrapper = directory.appendingPathComponent("drops-filter-ffmpeg")
        // Emulate a tool that claims success but ignores the requested pixel
        // filter. The real output remains decodable and must still be rejected.
        let script = """
        #!/usr/bin/perl
        my @out;
        while (@ARGV) { my $a = shift @ARGV; if ($a eq '-vf') { shift @ARGV; next; } push @out, $a; }
        exec '\(tools.ffmpeg.path)', @out;
        """
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("ffprobe"), withDestinationURL: tools.ffprobe)
        let store = ConverterStore(ffmpegOverride: wrapper)
        store.preset = .h264Software
        store.outputDirectory = directory
        store.items = [ConversionItem(source: source)]
        store.scheduleGeometry(store.items[0], crop: nil, aspectRatio: DisplayAspectRatio(width: 4, height: 3))
        store.start()
        XCTAssertTrue(store.isRunning, "The verification fixture must actually launch")
        let deadline = Date().addingTimeInterval(20)
        while store.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        if store.isRunning { store.cancel(); return XCTFail("Verification fixture stalled") }
        XCTAssertEqual(store.items[0].failure?.diagnostic, "MP4Flow:aspect-mismatch")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.contains("Converted") || $0.contains("partial") })
    }

    private func assertCircleAndCorners(_ data: Data, width: Int, height: Int, quarterTurn: Bool = false) throws {
        XCTAssertEqual(data.count, width * height * 3)
        guard data.count == width * height * 3 else { return }
        let pixels = [UInt8](data)
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 3
            if pixels[i] > 200 && pixels[i + 1] > 200 && pixels[i + 2] > 200 { xs.append(x); ys.append(y) }
        } }
        let spanX = try XCTUnwrap(xs.max()) - XCTUnwrap(xs.min())
        let spanY = try XCTUnwrap(ys.max()) - XCTUnwrap(ys.min())
        XCTAssertEqual(Double(spanX) / Double(spanY), 1, accuracy: 0.06, "The stretched ellipse must become a circle in actual decoded pixels")
        func rgb(_ x: Int, _ y: Int) -> [UInt8] { let i = (y * width + x) * 3; return Array(pixels[i..<(i+3)]) }
        let tl = quarterTurn ? rgb(8, height-9) : rgb(8, 8)
        let tr = quarterTurn ? rgb(8, 8) : rgb(width-9, 8)
        let bl = quarterTurn ? rgb(width-9, height-9) : rgb(8, height-9)
        let br = quarterTurn ? rgb(width-9, 8) : rgb(width-9, height-9)
        XCTAssertTrue(tl[0] > 170 && tl[1] < 80 && tl[2] < 80)
        XCTAssertTrue(tr[1] > 170 && tr[0] < 80 && tr[2] < 80)
        XCTAssertTrue(bl[2] > 170 && bl[0] < 80 && bl[1] < 80)
        XCTAssertTrue(br[0] > 170 && br[1] > 170 && br[2] < 80, "All four corners must survive without cropping")
    }

    private func makeStretchedFixture(in directory: URL, ffmpeg: URL) throws -> URL {
        let image = directory.appendingPathComponent("circle.ppm")
        var pixels = Data("P6\n320 240\n255\n".utf8)
        for y in 0..<240 { for x in 0..<320 {
            var rgb: [UInt8] = [20, 20, 20]
            if x < 40 && y < 40 { rgb = [255, 0, 0] }
            if x >= 280 && y < 40 { rgb = [0, 255, 0] }
            if x < 40 && y >= 200 { rgb = [0, 0, 255] }
            if x >= 280 && y >= 200 { rgb = [255, 255, 0] }
            if (x-160)*(x-160)+(y-120)*(y-120) <= 36*36 { rgb = [255, 255, 255] }
            pixels.append(contentsOf: rgb)
        } }
        try pixels.write(to: image)
        let source = directory.appendingPathComponent("stretched.mp4")
        try run(ffmpeg, ["-v", "error", "-loop", "1", "-i", image.path, "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-vf", "scale=320:180,setsar=1", "-t", "1", "-r", "12", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "16", "-pix_fmt", "yuv420p", "-c:a", "aac", source.path])
        return source
    }

    @MainActor
    private func completedOutput(_ store: ConverterStore, context: String = "") async throws -> URL {
        let deadline = Date().addingTimeInterval(20)
        while store.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        if store.isRunning { store.cancel(); XCTFail("Geometry conversion exceeded 20 seconds") }
        guard case .complete(let output) = store.items.first?.state else {
            XCTFail("Geometry conversion failed [\(context)]: \(String(describing: store.items.first?.state)); \(String(describing: store.items.first?.failure))")
            throw NSError(domain: "AspectCorrectionTests", code: 1)
        }
        return output
    }

    private func probeVideo(_ source: URL, tools: (ffmpeg: URL, ffprobe: URL)) throws -> (width: Int, height: Int, sar: String, dar: Double) {
        let data = try capture(tools.ffprobe, ["-v", "error", "-select_streams", "V:0", "-show_streams", "-of", "json", source.path])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stream = try XCTUnwrap((object["streams"] as? [[String: Any]])?.first)
        let width = try XCTUnwrap(stream["width"] as? Int), height = try XCTUnwrap(stream["height"] as? Int)
        let sar = stream["sample_aspect_ratio"] as? String ?? "1:1"
        return (width, height, sar, Double(width) / Double(height) * AspectGeometry.pixelRatio(sar))
    }
    private func decode(_ source: URL, ffmpeg: URL) throws {
        try run(ffmpeg, ["-v", "error", "-xerror", "-i", source.path, "-map", "0:V:0", "-map", "0:a:0?", "-f", "null", "-"])
    }
    private func mediaTools() throws -> (ffmpeg: URL, ffprobe: URL) {
        for root in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let ffmpeg = URL(fileURLWithPath: root + "/ffmpeg"), ffprobe = URL(fileURLWithPath: root + "/ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffmpeg.path) && FileManager.default.isExecutableFile(atPath: ffprobe.path) { return (ffmpeg, ffprobe) }
        }
        throw XCTSkip("FFmpeg and ffprobe are required for geometry regression")
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-Aspect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func run(_ executable: URL, _ arguments: [String]) throws { _ = try capture(executable, arguments) }
    private func capture(_ executable: URL, _ arguments: [String]) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
        guard process.terminationStatus == 0 else { throw NSError(domain: "AspectTools", code: Int(process.terminationStatus)) }
        return data
    }
}
