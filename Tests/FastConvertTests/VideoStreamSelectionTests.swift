import AVFoundation
import XCTest
@testable import FastConvert

final class VideoStreamSelectionTests: XCTestCase {
    func testCoverAndThumbnailsBeforeTheMovieDoNotAffectSelectionOrEditorGeometry() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("cover-first.json")
        let response = """
        {"streams":[
          {"index":0,"codec_type":"video","codec_name":"mjpeg","width":1600,"height":1600,
           "disposition":{"attached_pic":1}},
          {"index":1,"codec_type":"video","width":160,"height":90,
           "disposition":{"timed_thumbnails":1}},
          {"index":7,"id":"0x2a","codec_type":"video","codec_name":"mjpeg","width":320,"height":240,
           "r_frame_rate":"12/1","sample_aspect_ratio":"1:1","time_base":"1/12000",
           "disposition":{"attached_pic":0}},
          {"index":8,"codec_type":"audio","codec_name":"aac"}
        ],"format":{"duration":"2","format_name":"mov,mp4,m4a,3gp,3g2,mj2"}}
        """
        try Data(response.utf8).write(to: source)
        let probe = try script("#!/bin/sh\nfor argument in \"$@\"; do :; done\nexec /bin/cat \"$argument\"\n", at: directory.appendingPathComponent("ffprobe"))
        let info = await ConverterStore.inspectMedia(at: source, using: probe)
        XCTAssertTrue(info.hasVideo)
        XCTAssertEqual(info.videoTrackCount, 1)
        XCTAssertEqual(info.selectedVideoStreamIndex, 7)
        XCTAssertEqual(info.videoStreamSpecifier, "7")
        XCTAssertEqual(info.selectedVideoTrackID, 42)
        XCTAssertEqual(info.width, 320)
        XCTAssertEqual(info.height, 240)
        XCTAssertEqual(info.videoCodec, "mjpeg", "MJPEG camera video must not be mistaken for cover art")
        XCTAssertNil(ConverterStore.mediaHandlingNotice(for: info, preset: .remux))
        let editor = await EditorMediaProbe.inspect(source: source, using: probe)
        XCTAssertEqual(editor?.width, 320)
        XCTAssertEqual(editor?.height, 240)
        XCTAssertEqual(editor?.frameRate, 12)

        try Data(response.replacingOccurrences(of: "mov,mp4,m4a,3gp,3g2,mj2", with: "mpegts").utf8).write(to: source)
        let transportStream = await ConverterStore.inspectMedia(at: source, using: probe)
        XCTAssertNil(transportStream.selectedVideoTrackID, "A transport-stream PID must not be used as a native track ID")
        XCTAssertEqual(transportStream.selectedVideoStreamIndex, 7)

        let coverOnly = #"{"streams":[{"index":0,"codec_type":"video","width":1600,"height":1600,"disposition":{"attached_pic":1}}],"format":{"duration":"2"}}"#
        try Data(coverOnly.utf8).write(to: source)
        let onlyImage = await ConverterStore.inspectMedia(at: source, using: probe)
        XCTAssertFalse(onlyImage.hasVideo)
        XCTAssertEqual(onlyImage.videoTrackCount, 0)
        let noEditor = await EditorMediaProbe.inspect(source: source, using: probe)
        XCTAssertNil(noEditor)
    }

    func testNativeTrackSelectionUsesTheInspectedTrackIDAndRejectsAmbiguity() async throws {
        let asset = AVMutableComposition()
        let first = try XCTUnwrap(asset.addMutableTrack(withMediaType: .video, preferredTrackID: 10))
        let second = try XCTUnwrap(asset.addMutableTrack(withMediaType: .video, preferredTrackID: 42))
        let selected = try await NativeVideoTrackSelection.select(from: asset, trackID: 42)
        XCTAssertEqual(selected?.trackID, second.trackID)
        XCTAssertNotEqual(selected?.trackID, first.trackID)
        let ambiguous = try await NativeVideoTrackSelection.select(from: asset, trackID: nil)
        let missing = try await NativeVideoTrackSelection.select(from: asset, trackID: 99)
        XCTAssertNil(ambiguous)
        XCTAssertNil(missing, "A missing selected track must not silently fall back to the first one")
    }

    @MainActor
    func testRealEmbeddedCoverIsIgnoredByCopyTranscodeAndBothMergeRoutes() async throws {
        let tools = try tools()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = try await makeMedia(in: directory, tools: tools)
        let info = await ConverterStore.inspectMedia(at: media.covered, using: tools.probe)
        XCTAssertEqual(info.videoTrackCount, 1)
        XCTAssertEqual(info.selectedVideoStreamIndex, 1, "The fixture deliberately stores audio before the movie")
        XCTAssertEqual(info.width, 320)
        XCTAssertEqual(info.height, 240)
        XCTAssertNil(ConverterStore.mediaHandlingNotice(for: info, preset: .remux))
        let sourceHash = try await capture(tools.ffmpeg, ["-v", "error", "-i", media.covered.path, "-map", "0:V:0", "-c:v", "copy", "-f", "hash", "-"])

        for preset in [ConversionPreset.remux, .h264Software, .h264Hardware] {
            let store = ConverterStore()
            store.preset = preset
            store.outputDirectory = directory
            let item = ConversionItem(source: media.covered)
            store.items = [item]
            if preset != .remux { store.scheduleRotation(item, rotation: .clockwise) }
            store.start()
            try await wait(store)
            guard case .complete(let output) = store.items[0].state else {
                return XCTFail("Covered input must convert: \(store.items[0].state)")
            }
            try await assertMovie(output, frames: 24, duration: 2, tools: tools)
            let outputInfo = await ConverterStore.inspectMedia(at: output, using: tools.probe)
            XCTAssertEqual(outputInfo.width, preset == .remux ? 320 : 240)
            XCTAssertEqual(outputInfo.height, preset == .remux ? 240 : 320)
            if preset == .remux {
                let hash = try await capture(tools.ffmpeg, ["-v", "error", "-i", output.path, "-map", "0:V:0", "-c:v", "copy", "-f", "hash", "-"])
                XCTAssertEqual(hash, sourceHash, "Stream copy must preserve the movie bytes, not the JPEG cover")
            }
        }

        let lossless = ConverterStore()
        lossless.outputDirectory = directory
        lossless.items = [ConversionItem(source: media.covered), ConversionItem(source: media.covered)]
        lossless.mergeWaitingItems()
        try await wait(lossless)
        let merged = try XCTUnwrap(lossless.mergeOutput, lossless.mergeNotice)
        try await assertMovie(merged, frames: 48, duration: 4, tools: tools)

        let compatible = ConverterStore()
        compatible.outputDirectory = directory
        compatible.items = [ConversionItem(source: media.covered), ConversionItem(source: media.plain)]
        compatible.mergeWaitingItems()
        try await wait(compatible)
        XCTAssertTrue(compatible.showCompatibleMergePrompt, "Concat must reject different stream layouts even when movie geometry matches")
        guard compatible.showCompatibleMergePrompt else { return }
        compatible.startCompatibleMerge()
        try await wait(compatible)
        let normalized = try XCTUnwrap(compatible.mergeOutput, compatible.mergeNotice)
        try await assertMovie(normalized, frames: 48, duration: 4, tools: tools)
    }

    @MainActor
    func testCoverOnlyInputAndCoverOnlyOutputAreRejectedWithoutPublishing() async throws {
        let tools = try tools()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = try await makeMedia(in: directory, tools: tools)
        let coverOnly = directory.appendingPathComponent("audio-and-cover.mp4")
        _ = try await capture(tools.ffmpeg, ["-v", "error", "-i", media.covered.path, "-map", "0:a:0", "-map", "0:v:1", "-c", "copy", "-disposition:v:0", "attached_pic", coverOnly.path])

        let input = ConverterStore()
        input.outputDirectory = directory
        input.items = [ConversionItem(source: coverOnly)]
        input.start()
        try await wait(input)
        XCTAssertEqual(input.items[0].failure?.diagnostic, "probe:no-video")

        // A successful child exit with a cover-only file must still fail the
        // output gate. Keep the real ffprobe, replace only this owned encoder.
        let bin = directory.appendingPathComponent("fake-bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let fake = try script("#!/bin/sh\nfor output in \"$@\"; do :; done\nexec /bin/cp \(quote(coverOnly.path)) \"$output\"\n", at: bin.appendingPathComponent("ffmpeg"))
        _ = try script("#!/bin/sh\nexec \(quote(tools.probe.path)) \"$@\"\n", at: bin.appendingPathComponent("ffprobe"))
        let output = ConverterStore(ffmpegOverride: fake)
        output.outputDirectory = directory
        output.items = [ConversionItem(source: media.covered)]
        output.start()
        try await wait(output)
        XCTAssertEqual(output.items[0].failure?.diagnostic, "verify:no-video-stream")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { $0.lastPathComponent.contains(".partial.mp4") })
        XCTAssertFalse(files.contains { $0.lastPathComponent.hasPrefix("covered-MP4FlowConverted")
            || $0.lastPathComponent.hasPrefix("audio-and-cover-MP4FlowConverted") })
    }

    private struct Tools { let ffmpeg: URL; let probe: URL }

    private func tools() throws -> Tools {
        for directory in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let root = URL(fileURLWithPath: directory)
            let ffmpeg = root.appendingPathComponent("ffmpeg"), probe = root.appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffmpeg.path), FileManager.default.isExecutableFile(atPath: probe.path) {
                return Tools(ffmpeg: ffmpeg, probe: probe)
            }
        }
        throw XCTSkip("FFmpeg and ffprobe are required")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-streams-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeMedia(in directory: URL, tools: Tools) async throws -> (plain: URL, covered: URL) {
        let plain = directory.appendingPathComponent("plain.mp4"), covered = directory.appendingPathComponent("covered.mp4")
        let cover = directory.appendingPathComponent("cover.jpg")
        _ = try await capture(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=12:duration=2", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-map", "1:a", "-map", "0:v", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", plain.path])
        _ = try await capture(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "color=red:size=640x480", "-frames:v", "1", cover.path])
        _ = try await capture(tools.ffmpeg, ["-v", "error", "-i", plain.path, "-i", cover.path, "-map", "0", "-map", "1:v", "-c", "copy", "-disposition:v:1", "attached_pic", covered.path])
        return (plain, covered)
    }

    private func assertMovie(_ source: URL, frames: Int, duration: Double, tools: Tools) async throws {
        let info = await ConverterStore.inspectMedia(at: source, using: tools.probe)
        XCTAssertTrue(info.hasVideo)
        XCTAssertEqual(info.videoTrackCount, 1)
        XCTAssertEqual(info.duration ?? 0, duration, accuracy: 0.15)
        let hashes = try await capture(tools.ffmpeg, ["-v", "error", "-xerror", "-i", source.path, "-map", "0:V:0", "-fps_mode", "passthrough", "-f", "framemd5", "-"])
        let rows = hashes.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(rows.count, frames)
        let distinctFrames = Set(rows.compactMap { $0.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) })
        XCTAssertGreaterThan(distinctFrames.count, 2, "The result must contain changing movie frames, not a repeated cover")
    }

    private func capture(_ binary: URL, _ arguments: [String]) async throws -> String {
        let result = await FFmpegProcessRunner(executable: binary, arguments: arguments).run()
        guard result.succeeded else {
            throw NSError(domain: "VideoStreamSelectionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: result.standardError])
        }
        return String(decoding: result.standardOutput, as: UTF8.self)
    }

    private func script(_ contents: String, at url: URL) throws -> URL {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @MainActor
    private func wait(_ store: ConverterStore) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while store.isBusy && ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        if store.isBusy { store.cancel(); XCTFail("Small media task exceeded the test deadline") }
    }
}
