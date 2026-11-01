import Foundation
import XCTest
@testable import FastConvert

@MainActor final class MergeAudioRegressionTests: XCTestCase {
    private var ffmpeg: URL {
        if let override = ProcessInfo.processInfo.environment["MP4FLOW_TEST_FFMPEG"] { return URL(fileURLWithPath: override) }
        return DependencyToolResolver.resolve().ffmpeg ?? URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    }
    private var probe: URL { ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe") }

    func testLosslessMergeKeepsBothAudioTracksAndAcceptsQuotedFilename() async throws {
        try await verifyMerge(compatible: false, videoOnly: false)
    }
    func testCompatibleMergeKeepsBothAudioTracks() async throws {
        try await verifyMerge(compatible: true, videoOnly: false)
    }
    func testCompatibleVideoOnlyMergeDoesNotInventAudio() async throws {
        try await verifyMerge(compatible: true, videoOnly: true)
    }
    func testCompatibleMergeFillsMissingSoundWithoutDroppingOtherTracks() async throws {
        try await verifyMerge(compatible: true, videoOnly: false, silentSecond: true)
    }
    func testCompatibleMergePreservesAnIntentionalAudioStartDelay() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await fixture(directory.appendingPathComponent("original.mp4"), size: "320x240", audio: true)
        let delayed = directory.appendingPathComponent("delayed.mp4")
        _ = try await run(["-v", "error", "-i", first.path, "-itsoffset", "0.4", "-i", first.path, "-map", "0:v", "-map", "1:a", "-c", "copy", delayed.path])
        let second = try await fixture(directory.appendingPathComponent("second.mp4"), size: "640x360", audio: true)
        let store = ConverterStore(ffmpegOverride: ffmpeg)
        store.outputDirectory = directory; store.items = [ConversionItem(source: delayed), ConversionItem(source: second)]
        store.mergeWaitingItems(); try await wait(store)
        XCTAssertTrue(store.showCompatibleMergePrompt)
        store.startCompatibleMerge(); try await wait(store)
        let output = try XCTUnwrap(store.mergeOutput, store.mergeNotice)
        func rms(_ data: Data) -> Double {
            let bytes = [UInt8](data)
            let samples = stride(from: 0, to: bytes.count - 1, by: 2).map { index in Double(Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)) / 32768 }
            return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(max(1, samples.count)))
        }
        let leading = try await run(["-v", "error", "-ss", "0.1", "-i", output.path, "-t", "0.1", "-map", "0:a:0", "-c:a", "pcm_s16le", "-f", "s16le", "-"])
        let sounding = try await run(["-v", "error", "-ss", "0.6", "-i", output.path, "-t", "0.1", "-map", "0:a:0", "-c:a", "pcm_s16le", "-f", "s16le", "-"])
        XCTAssertLessThan(rms(leading), 0.005, "The intentional leading silence must not be reset away")
        XCTAssertGreaterThan(rms(sounding), 0.02)
    }
    func testConflictingTrackOrderAndHDRAreRejectedBeforeEncoding() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try await fixture(directory.appendingPathComponent("one.mp4"), size: "320x240", audio: true)
        for hdr in [false, true] {
            let b = try await fixture(directory.appendingPathComponent(hdr ? "hdr.mp4" : "swapped.mp4"), size: "640x360", audio: true, swapped: !hdr, hdr: hdr)
            let probed = await MediaInspector.inspect(at: b, using: probe)
            XCTAssertEqual(probed.isHDR, hdr, "The fixture must actually carry the intended color transfer")
            let store = ConverterStore(ffmpegOverride: ffmpeg)
            store.outputDirectory = directory; store.items = [ConversionItem(source: a), ConversionItem(source: b)]
            store.mergeWaitingItems(); try await wait(store)
            XCTAssertTrue(store.showCompatibleMergePrompt)
            store.startCompatibleMerge(); try await wait(store)
            XCTAssertNil(store.mergeOutput)
            XCTAssertEqual(store.mergeNotice, hdr ? MergePlanningError.hdr.localizedDescription : MergePlanningError.audioLayout.localizedDescription)
            XCTAssertTrue(store.items.allSatisfy { $0.state == .waiting })
        }
    }

    private func verifyMerge(compatible: Bool, videoOnly: Bool, silentSecond: Bool = false) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await fixture(directory.appendingPathComponent("it's [one], \\camera.mp4"), size: "320x240", audio: !videoOnly)
        let second = try await fixture(directory.appendingPathComponent("第二个.mp4"), size: compatible ? "640x360" : "320x240", audio: !videoOnly && !silentSecond)
        let before = try Data(contentsOf: first)
        let store = ConverterStore(ffmpegOverride: ffmpeg)
        store.items = [ConversionItem(source: first), ConversionItem(source: second)]; store.outputDirectory = directory
        store.mergeWaitingItems(); try await wait(store)
        if compatible {
            XCTAssertTrue(store.showCompatibleMergePrompt)
            store.startCompatibleMerge(); try await wait(store)
        }
        let output = try XCTUnwrap(store.mergeOutput, store.mergeNotice)
        let info = await MediaInspector.inspect(at: output, using: probe)
        XCTAssertEqual(info.audioTrackCount, videoOnly ? 0 : 2)
        if !videoOnly {
            XCTAssertEqual(info.audioTracks.map(\.language), ["eng", "jpn"])
            XCTAssertEqual(info.audioTracks.map(\.isDefault), [false, true])
        }
        XCTAssertEqual(try XCTUnwrap(info.duration), 2, accuracy: 0.15)
        _ = try await run(["-v", "error", "-xerror", "-i", output.path, "-f", "null", "-"])
        XCTAssertEqual(try Data(contentsOf: first), before)
        let leftovers = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".partial") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    private func fixture(_ url: URL, size: String, audio: Bool, swapped: Bool = false, hdr: Bool = false) async throws -> URL {
        var args = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=s=\(size):r=25:d=1"]
        if audio { args += ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1", "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000:duration=1"] }
        args += ["-map", "0:v"]
        if audio { args += ["-map", "1:a", "-map", "2:a", "-c:a", "aac", "-metadata:s:a:0", "language=\(swapped ? "jpn" : "eng")", "-metadata:s:a:1", "language=\(swapped ? "eng" : "jpn")", "-disposition:a:0", "0", "-disposition:a:1", "default"] }
        args += ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p"]
        if hdr { args += ["-vf", "setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc", "-x264-params", "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc", "-color_trc", "smpte2084", "-color_primaries", "bt2020", "-colorspace", "bt2020nc"] }
        args += [url.path]; _ = try await run(args)
        return url
    }
    private func run(_ arguments: [String]) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else { throw XCTSkip("FFmpeg is required") }
        let result = await FFmpegProcessRunner(executable: ffmpeg, arguments: arguments, configuration: .init(inactivityTimeout: 30)).run()
        guard result.succeeded else { XCTFail(result.standardError); throw CocoaError(.fileReadCorruptFile) }
        return result.standardOutput
    }
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-merge-audit-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory
    }
    private func wait(_ store: ConverterStore) async throws {
        let deadline = TestDeadline(seconds: 30)
        while store.isMerging && deadline.hasTimeRemaining { try await Task.sleep(nanoseconds: 25_000_000) }
        if store.isMerging { store.cancel(); XCTFail("Merge timed out") }
    }
}
