import AVFoundation
import CoreImage
import Foundation
import XCTest
@testable import FastConvert

final class ImageAdjustmentTests: XCTestCase {
    func testSettingsAreBoundedAndNeutralReallyBypassesProcessing() {
        XCTAssertTrue(ImageAdjustment().isIdentity)
        XCTAssertNil(ImageAdjustment().ffmpegFilter)
        XCTAssertNil(ImageAdjustment().composition(for: AVMutableComposition()))
        XCTAssertEqual(ImageAdjustment(brightness: .min, shadows: .max), ImageAdjustment(brightness: -100, shadows: 100))
        let lift = ImageAdjustment(shadows: 70)
        XCTAssertGreaterThan(lift.adjusted(0.15), 0.15)
        XCTAssertEqual(lift.adjusted(0), 0)
        XCTAssertEqual(lift.adjusted(1), 1)
        XCTAssertEqual(ImageAdjustment(brightness: -100).adjusted(0.01), 0)
        XCTAssertEqual(ImageAdjustment(brightness: 100).adjusted(0.99), 1)
        XCTAssertFalse(ImageAdjustment(denoise: true).isIdentity)
        XCTAssertNotNil(ImageAdjustment(denoise: true).ffmpegFilter)
    }

    func testGentleShadowCurveProtectsTheNoiseFloorAndIsMonotonic() {
        let setting = ImageAdjustment(shadows: 100)
        var previous = 0.0
        for i in 1...10_000 {
            let x = Double(i) / 10_000, y = setting.adjusted(x)
            XCTAssertGreaterThan(y, previous)
            XCTAssertLessThan((y - previous) * 10_000, 1.9)
            previous = y
        }
        XCTAssertLessThan(setting.adjusted(0.01), 0.012)
        XCTAssertGreaterThan(setting.adjusted(0.2), 0.3)
        XCTAssertLessThan(setting.adjusted(0.9) - 0.9, 0.02)
        let oldNoiseRange = pow(0.009, 1 / 1.8) - pow(0.003, 1 / 1.8)
        let newNoiseRange = setting.adjusted(0.009) - setting.adjusted(0.003)
        XCTAssertLessThan(newNoiseRange, oldNoiseRange * 0.35)
    }

    func testLightDenoiseMatchesPreviewReducesGrainAndKeepsEdges() throws {
        let tools = try tools(), directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let width = 64, height = 48
        var seed: UInt32 = 7, rgb = [UInt8]()
        for _ in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    seed = 1_664_525 &* seed &+ 1_013_904_223
                    let noise = Int((seed >> 16) % 17) - 8
                    let base = (x < 32 ? [18,24,30] : [65,80,95])[channel]
                    rgb.append(UInt8(x == 48 || x == 49 ? 200 : base + noise))
                }
            }
        }
        let source = directory.appendingPathComponent("grain.rgb")
        try Data(rgb).write(to: source)
        let rgba = rgb.enumerated().flatMap { i, value -> [UInt8] in i % 3 == 2 ? [value,255] : [value] }
        let image = CIImage(bitmapData: Data(rgba), bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: nil)
        func exported(_ setting: ImageAdjustment) throws -> Data {
            try capture(tools.ffmpeg, ["-v","error","-f","rawvideo","-pix_fmt","rgb24","-s","64x48","-i",source.path,"-frames:v","1","-vf",try XCTUnwrap(setting.ffmpegFilter) + ",format=rgb24","-f","rawvideo","-"])
        }
        for setting in [ImageAdjustment(denoise: true), ImageAdjustment(shadows: 70, denoise: true), ImageAdjustment(brightness: 12, shadows: 70, denoise: true)] {
            let output = try exported(setting)
            var preview = [UInt8](repeating: 0, count: width * height * 4)
            ImageAdjustment.previewContext.render(setting.previewImage(image), toBitmap: &preview, rowBytes: width * 4, bounds: image.extent, format: .RGBA8, colorSpace: nil)
            XCTAssertEqual(output.count, rgb.count)
            var largestError = 0.0
            for i in 0..<(width * height) {
                for c in 0..<3 { largestError = max(largestError, abs(Double(preview[i*4+c]) - Double(output[i*3+c]))) }
            }
            XCTAssertLessThanOrEqual(largestError, 2, "Preview/export denoise: \(setting)")
        }
        let lifted = try exported(ImageAdjustment(shadows: 70))
        let cleaned = try exported(ImageAdjustment(shadows: 70, denoise: true))
        func values(_ data: Data, xs: Range<Int>) -> [Double] {
            (6..<42).flatMap { y in xs.map { x in Double(data[(y*width+x)*3]) } }
        }
        func deviation(_ data: [Double]) -> Double {
            let mean = data.reduce(0,+) / Double(data.count)
            return sqrt(data.reduce(0) { $0 + pow($1-mean,2) } / Double(data.count))
        }
        let before = deviation(values(lifted, xs: 6..<26)), after = deviation(values(cleaned, xs: 6..<26))
        XCTAssertLessThan(after, before * 0.9)
        print("Light denoise grain deviation: \(before) -> \(after)")
        let detail = values(cleaned, xs: 48..<50)
        XCTAssertGreaterThan(detail.reduce(0,+) / Double(detail.count), 190)
        let right = values(cleaned, xs: 35..<44), left = values(cleaned, xs: 6..<26)
        XCTAssertGreaterThan(right.reduce(0,+)/Double(right.count) - left.reduce(0,+)/Double(left.count), 45)
    }

    func testDenoiseDoesNotLeaveTrailsAcrossMovingFrames() throws {
        let tools = try tools(), directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let width = 64, height = 32, stride = width * height * 3
        var frames = Data()
        let positions = [8, 28, 48]
        for position in positions {
            var bytes = [UInt8](repeating: 0, count: stride)
            for y in 10..<22 {
                for x in position..<(position+8) {
                    for c in 0..<3 { bytes[(y*width+x)*3+c] = 220 }
                }
            }
            frames.append(contentsOf: bytes)
        }
        let source = directory.appendingPathComponent("moving.rgb")
        try frames.write(to: source)
        let filter = try XCTUnwrap(ImageAdjustment(denoise: true).ffmpegFilter)
        let output = try capture(tools.ffmpeg, ["-v","error","-f","rawvideo","-pix_fmt","rgb24","-s","64x32","-r","24","-i",source.path,"-vf",filter+",format=rgb24","-f","rawvideo","-"])
        XCTAssertEqual(output.count, frames.count)
        for (frame, position) in positions.enumerated() {
            XCTAssertEqual(output[frame*stride + (16*width+position+4)*3], 220, accuracy: 1)
            for oldPosition in positions where oldPosition != position {
                XCTAssertEqual(output[frame*stride + (16*width+oldPosition+4)*3], 0)
            }
        }
    }

    func testPreviewAndFFmpegMatchOnDarkColorsAndHighlightClipping() throws {
        let tools = try tools(), directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let colors: [[UInt8]] = [[0,0,0], [20,40,70], [65,30,15], [90,120,150], [210,230,250], [255,255,255]]
        let rgb = Data(colors.flatMap { $0 }), rgba = Data(colors.flatMap { $0 + [255] })
        let source = directory.appendingPathComponent("patches.rgb")
        try rgb.write(to: source)
        let image = CIImage(bitmapData: rgba, bytesPerRow: colors.count * 4, size: CGSize(width: colors.count, height: 1), format: .RGBA8, colorSpace: nil)
        for setting in [ImageAdjustment(brightness: 20), ImageAdjustment(shadows: 60), ImageAdjustment(brightness: 20, shadows: 60), ImageAdjustment(brightness: -30, shadows: 20)] {
            var preview = [UInt8](repeating: 0, count: colors.count * 4)
            ImageAdjustment.previewContext.render(setting.previewImage(image), toBitmap: &preview, rowBytes: colors.count * 4, bounds: image.extent, format: .RGBA8, colorSpace: nil)
            let filtered = try capture(tools.ffmpeg, ["-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "6x1", "-i", source.path, "-frames:v", "1", "-vf", try XCTUnwrap(setting.ffmpegFilter) + ",format=rgb24", "-f", "rawvideo", "-"])
            XCTAssertEqual(filtered.count, rgb.count)
            for i in colors.indices {
                for c in 0..<3 {
                    XCTAssertEqual(Double(preview[i * 4 + c]), Double(filtered[i * 3 + c]), accuracy: 2, "\(setting): patch \(i), channel \(c)")
                    XCTAssertEqual(Double(preview[i * 4 + c]), setting.adjusted(Double(colors[i][c]) / 255) * 255, accuracy: 2)
                }
            }
        }
    }

    @MainActor
    func testSaveNoOpResetAndGeometryEditsRetainIndependentSettings() {
        let store = ConverterStore()
        var original = ConversionItem(source: URL(fileURLWithPath: "/fixture.mp4"))
        original.state = .complete(URL(fileURLWithPath: "/finished.mp4"))
        original.trimRange = ClipRange(start: 1, end: 2)
        original.rotation = .clockwise
        store.items = [original]
        store.scheduleFrameEdits(original, crop: nil, aspectRatio: nil, imageAdjustment: ImageAdjustment())
        XCTAssertEqual(store.items[0], original)
        let adjustment = ImageAdjustment(brightness: 15, shadows: 40, denoise: true)
        store.scheduleFrameEdits(original, crop: nil, aspectRatio: nil, imageAdjustment: adjustment)
        XCTAssertEqual(store.items[0].state, .waiting)
        XCTAssertEqual(store.items[0].imageAdjustment, adjustment)
        XCTAssertEqual(store.items[0].trimRange, original.trimRange)
        XCTAssertEqual(store.items[0].rotation, original.rotation)
        let ratio = DisplayAspectRatio(width: 4, height: 3)
        store.scheduleGeometry(store.items[0], crop: nil, aspectRatio: ratio)
        XCTAssertEqual(store.items[0].imageAdjustment, adjustment)
        store.scheduleFrameEdits(store.items[0], crop: nil, aspectRatio: ratio, imageAdjustment: ImageAdjustment())
        XCTAssertTrue(store.items[0].imageAdjustment.isIdentity)
        XCTAssertEqual(store.items[0].aspectRatio, ratio)
        var waiting = ConversionItem(source: original.source)
        waiting.imageAdjustment = adjustment
        store.items = [waiting]
        XCTAssertEqual(store.mergeCandidateCount, 0)
        store.scheduleFrameEdits(waiting, crop: nil, aspectRatio: nil, imageAdjustment: ImageAdjustment())
        XCTAssertEqual(store.mergeCandidateCount, 1)
        store.scheduleFrameEdits(waiting, crop: nil, aspectRatio: nil, imageAdjustment: ImageAdjustment(denoise: true))
        XCTAssertEqual(store.mergeCandidateCount, 0)
    }

    @MainActor
    func testActualConversionsBrightenWithoutLosingAudioOrSource() async throws {
        let tools = try tools(), directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory, ffmpeg: tools.ffmpeg)
        let original = try Data(contentsOf: source)
        let audio = try capture(tools.ffmpeg, ["-v", "error", "-i", source.path, "-map", "0:a:0", "-c", "copy", "-f", "hash", "-"])
        let input = try pixels(source, ffmpeg: tools.ffmpeg)
        for preset in [ConversionPreset.smartMP4, .remux, .h264Software, .h264Hardware, .hevcHardware] {
            let store = ConverterStore()
            store.preset = preset; store.outputDirectory = directory
            store.items = [ConversionItem(source: source)]
            let setting = ImageAdjustment(brightness: 12, shadows: 60, denoise: true)
            store.scheduleFrameEdits(store.items[0], crop: nil, aspectRatio: nil, imageAdjustment: setting)
            store.start(); try await wait(store)
            guard case .complete(let output) = store.items[0].state else { return XCTFail("\(preset): \(store.items[0].state)") }
            let result = try pixels(output, ffmpeg: tools.ffmpeg)
            XCTAssertEqual(result.count, input.count)
            XCTAssertGreaterThan(Double(result[100]), Double(input[100]) + 8)
            XCTAssertEqual(Double(result[100]), setting.adjusted(Double(input[100]) / 255) * 255, accuracy: 7)
            XCTAssertEqual(try capture(tools.ffmpeg, ["-v", "error", "-i", output.path, "-map", "0:a:0", "-c", "copy", "-f", "hash", "-"]), audio)
            _ = try capture(tools.ffmpeg, ["-v", "error", "-xerror", "-i", output.path, "-f", "null", "-"])
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertTrue(output.lastPathComponent.contains("adjusted"))
        }
        // Neutral edits do not force an otherwise compatible video to encode.
        let neutral = ConverterStore(); neutral.outputDirectory = directory
        neutral.items = [ConversionItem(source: source)]
        neutral.start(); try await wait(neutral)
        guard case .complete(let output) = neutral.items[0].state else { return XCTFail("Neutral conversion failed") }
        let videoHash: (URL) throws -> Data = { try self.capture(tools.ffmpeg, ["-v","error","-i",$0.path,"-map","0:V:0","-c","copy","-f","hash","-"]) }
        XCTAssertEqual(try videoHash(source), try videoHash(output))
    }

    @MainActor
    func testCombinedEditsKeepShapeAndFirstFrame() async throws {
        let tools = try tools(), directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory, ffmpeg: tools.ffmpeg)
        let store = ConverterStore(); store.preset = .h264Software; store.outputDirectory = directory
        store.items = [ConversionItem(source: source)]
        store.scheduleTrim(store.items[0], start: 0.2, end: 1.2)
        store.scheduleRotation(store.items[0], rotation: .clockwise)
        store.scheduleFrameEdits(store.items[0], crop: CropRect(x: 20, y: 20, width: 240, height: 160), aspectRatio: DisplayAspectRatio(width: 4, height: 3), imageAdjustment: ImageAdjustment(shadows: 60, denoise: true))
        store.start(); try await wait(store)
        guard case .complete(let output) = store.items[0].state else { return XCTFail("\(store.items[0].state)") }
        let inspection = await EditorMediaProbe.inspect(source: output)
        let media = try XCTUnwrap(inspection)
        XCTAssertEqual(media.width, 320); XCTAssertEqual(media.height, 240)
        XCTAssertEqual(media.duration, 1, accuracy: 0.08)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output)); generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let first = try generator.copyCGImage(at: .zero, actualTime: nil)
        XCTAssertEqual(first.width, 320); XCTAssertEqual(first.height, 240)
        _ = try capture(tools.ffmpeg, ["-v", "error", "-xerror", "-i", output.path, "-f", "null", "-"])
    }

    @MainActor
    func testNativeVideoCompositionMatchesExportedFrame() async throws {
        let tools = try tools(), directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory, ffmpeg: tools.ffmpeg)
        for (name, params) in [("bt709", "colorprim=bt709:transfer=bt709:colormatrix=bt709"),
                               ("srgb", "colorprim=bt709:transfer=iec61966-2-1:colormatrix=bt709"),
                               ("sd601", "colorprim=smpte170m:transfer=smpte170m:colormatrix=smpte170m"),
                               ("untagged", ""), ("rotated", "colorprim=bt709:transfer=bt709:colormatrix=bt709"),
                               ("grain", "colorprim=bt709:transfer=bt709:colormatrix=bt709")] {
        var candidate = directory.appendingPathComponent(name + ".mp4")
        let pixelMetadata = name == "untagged" ? "setparams=color_primaries=unknown:color_trc=unknown:colorspace=unknown"
            : (name == "grain" ? "noise=alls=8:allf=t+u:all_seed=7" : "null")
        _ = try capture(tools.ffmpeg, ["-v","error","-i",source.path,"-vf",pixelMetadata,"-c:v","libx264","-x264-params",params,"-c:a","copy",candidate.path])
        if name == "rotated" {
            let rotated = directory.appendingPathComponent("camera-rotated.mp4")
            _ = try capture(tools.ffmpeg, ["-v","error","-display_rotation:v:0","90","-i",candidate.path,"-c","copy",rotated.path])
            candidate = rotated
        }
        let setting = ImageAdjustment(brightness: 12, shadows: 60, denoise: true)
        let store = ConverterStore(); store.preset = .h264Software; store.outputDirectory = directory
        store.items = [ConversionItem(source: candidate)]
        store.scheduleFrameEdits(store.items[0], crop: nil, aspectRatio: nil, imageAdjustment: setting)
        store.start(); try await wait(store)
        guard case .complete(let output) = store.items[0].state else { return XCTFail("Export failed") }
        let asset = AVURLAsset(url: candidate)
        _ = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let composition = try XCTUnwrap(setting.composition(for: asset))
        XCTAssertEqual(composition.colorPrimaries, AVVideoColorPrimaries_ITU_R_709_2)
        XCTAssertEqual(composition.colorTransferFunction, AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(composition.colorYCbCrMatrix, AVVideoYCbCrMatrix_ITU_R_709_2)
        generator.videoComposition = composition
        let preview = try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        let outputGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        outputGenerator.appliesPreferredTrackTransform = true
        let exported = try outputGenerator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        func sample(_ image: CGImage) -> [UInt8] {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CIContext(options: [.workingColorSpace: space])
            var bytes = [UInt8](repeating: 0, count: 4)
            context.render(CIImage(cgImage: image), toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 40, y: 40, width: 1, height: 1), format: .RGBA8, colorSpace: space)
            return bytes
        }
        XCTAssertEqual(preview.width, exported.width, name)
        XCTAssertEqual(preview.height, exported.height, name)
        let actualPreview = sample(preview), actualExport = sample(exported)
        print("Color regression \(name): preview \(actualPreview) \(String(describing: preview.colorSpace?.name)), export \(actualExport) \(String(describing: exported.colorSpace?.name))")
        for channel in 0..<3 { XCTAssertEqual(Double(actualPreview[channel]), Double(actualExport[channel]), accuracy: 6, "\(name): preview vs export channel \(channel)") }
        }
    }

    @MainActor
    func testHDRAdjustmentFailsClearlyWithoutPublishing() async throws {
        let tools = try tools(), directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory, ffmpeg: tools.ffmpeg)
        let hdr = directory.appendingPathComponent("hdr.mp4")
        _ = try capture(tools.ffmpeg, ["-v","error","-i",source.path,"-c:v","libx264","-pix_fmt","yuv420p","-vf","setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc","-x264-params","colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc","-c:a","copy",hdr.path])
        let inspected = await EditorMediaProbe.inspect(source: hdr)
        XCTAssertTrue(try XCTUnwrap(inspected).isHDR)
        let store = ConverterStore(); store.outputDirectory = directory; store.items = [ConversionItem(source: hdr)]
        store.scheduleFrameEdits(store.items[0], crop: nil, aspectRatio: nil, imageAdjustment: ImageAdjustment(shadows: 30))
        store.start(); try await wait(store)
        guard case .failed = store.items[0].state else { return XCTFail("HDR should fail rather than silently lose color") }
        XCTAssertEqual(store.items[0].failure?.diagnostic, "adjustment:hdr")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.contains("adjusted") || $0.contains("partial") })
    }

    @MainActor private func wait(_ store: ConverterStore) async throws {
        let deadline = Date().addingTimeInterval(30)
        while store.isBusy && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(store.isBusy)
        if store.isBusy { store.cancel(); throw NSError(domain: "ImageAdjustmentTimeout", code: 1) }
    }
    private func fixture(in directory: URL, ffmpeg: URL) throws -> URL {
        let url = directory.appendingPathComponent("dark.mp4")
        _ = try capture(ffmpeg, ["-v","error","-f","lavfi","-i","color=c=0x202830:s=320x240:r=24:d=2","-f","lavfi","-i","sine=frequency=440:sample_rate=48000:duration=2","-c:v","libx264","-pix_fmt","yuv420p","-x264-params","colorprim=bt709:transfer=bt709:colormatrix=bt709","-c:a","aac","-shortest",url.path])
        return url
    }
    private func pixels(_ url: URL, ffmpeg: URL) throws -> Data {
        try capture(ffmpeg, ["-v","error","-i",url.path,"-frames:v","1","-pix_fmt","rgb24","-f","rawvideo","-"])
    }
    private func tools() throws -> (ffmpeg: URL, ffprobe: URL) {
        for root in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let ffmpeg = URL(fileURLWithPath: root + "/ffmpeg"), ffprobe = URL(fileURLWithPath: root + "/ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffmpeg.path) && FileManager.default.isExecutableFile(atPath: ffprobe.path) { return (ffmpeg, ffprobe) }
        }
        throw XCTSkip("FFmpeg and ffprobe are required")
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-Image-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func capture(_ executable: URL, _ arguments: [String]) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
        guard process.terminationStatus == 0 else { throw NSError(domain: "ImageAdjustmentTool", code: Int(process.terminationStatus)) }
        return data
    }
}
