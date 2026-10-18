import Foundation
import XCTest
@testable import FastConvert

final class RealtimeProgressTests: XCTestCase {
    func testSmallProgressPacketsArriveWhileChildIsStillRunning() async throws {
        let perl = try systemPerl()
        let observed = RealtimeProgressObservations()
        let started = ProcessInfo.processInfo.systemUptime
        let result = await FFmpegProcessRunner(
            executable: perl,
            arguments: ["-e", periodicProgressScript(packetCount: 8, interval: 0.18)],
            configuration: FFmpegProcessRunner.Configuration(inactivityTimeout: 5)
        ).run { data in
            observed.record(data, elapsed: ProcessInfo.processInfo.systemUptime - started)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let snapshot = observed.snapshot()
        if let first = snapshot.firstCallback {
            print(String(format: "Live pipe first packet: %.3f s; callbacks: %d", first, snapshot.callbackCount))
        }

        XCTAssertTrue(result.succeeded, result.standardError)
        XCTAssertGreaterThanOrEqual(elapsed, 1.2, "The producer must stay alive long enough to distinguish streaming from EOF-only reads")
        XCTAssertLessThan(try XCTUnwrap(snapshot.firstCallback), 0.5, "A small progress packet must not wait for a 64 KB buffer or process EOF")
        XCTAssertGreaterThanOrEqual(snapshot.callbackCount, 3, "Periodic small writes should produce multiple live callbacks")
        XCTAssertTrue(snapshot.text.contains("progress=end"), "The final packet must still be drained")
    }

    func testAdvancingSmallPacketsPreventFalseInactivityTimeout() async throws {
        let perl = try systemPerl()
        let observed = RealtimeProgressObservations()
        let started = ProcessInfo.processInfo.systemUptime
        let result = await FFmpegProcessRunner(
            executable: perl,
            arguments: ["-e", periodicProgressScript(packetCount: 10, interval: 0.15)],
            configuration: FFmpegProcessRunner.Configuration(
                inactivityTimeout: 0.6,
                terminationGrace: 0.05,
                pollingInterval: 0.02,
                activityPolicy: .advancingFFmpegProgress,
                maximumOutputBytes: 0
            )
        ).run { data in
            observed.record(data, elapsed: ProcessInfo.processInfo.systemUptime - started)
        }

        XCTAssertFalse(result.timedOut, "A healthy producer emits advancing packets throughout a run longer than the inactivity window")
        XCTAssertTrue(result.succeeded, result.standardError)
        XCTAssertGreaterThan(ProcessInfo.processInfo.systemUptime - started, 1.2)
        XCTAssertGreaterThanOrEqual(observed.snapshot().callbackCount, 3)
        XCTAssertTrue(result.standardOutput.isEmpty, "Realtime delivery must work without retaining conversion stdout")
    }

    @MainActor
    func testRealtime1080pTo720pShowsProgressBeforePublishingAndDecodes() async throws {
        let ffmpeg = try availableFFmpeg()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-RealtimeProgress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("synthetic 1080p.mp4")
        let encoders = await FFmpegProcessRunner(executable: ffmpeg, arguments: ["-hide_banner", "-encoders"]).run()
        let encoderText = String(decoding: encoders.standardOutput, as: UTF8.self)
        let encoder: String
        if encoderText.contains(" libx264 ") { encoder = "libx264" }
        else if encoderText.contains(" h264_videotoolbox ") { encoder = "h264_videotoolbox" }
        else { throw XCTSkip("An H.264 encoder is required to generate the synthetic fixture") }

        var arguments = [
            "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24:duration=3",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3",
            "-c:v", encoder
        ]
        if encoder == "libx264" { arguments += ["-preset", "ultrafast"] }
        else { arguments += ["-b:v", "4M"] }
        arguments += ["-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "-y", source.path]
        let fixture = await FFmpegProcessRunner(executable: ffmpeg, arguments: arguments).run()
        XCTAssertTrue(fixture.succeeded, fixture.standardError)
        guard fixture.succeeded else { return }

        let wrapper = directory.appendingPathComponent("ffmpeg")
        let quotedFFmpeg = "'" + ffmpeg.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // Replace the shell with the real process; no descendant keeps the
        // progress pipe open or escapes the converter's cancellation owner.
        try "#!/bin/sh\nexec \(quotedFFmpeg) -re \"$@\"\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("ffprobe"), withDestinationURL: ffprobe)

        let store = ConverterStore(ffmpegOverride: wrapper)
        store.outputResolution = .p720
        store.outputDirectory = directory
        store.items = [ConversionItem(source: source)]
        let started = ProcessInfo.processInfo.systemUptime
        store.start()
        var firstLiveProgress: TimeInterval?
        let deadline = Date().addingTimeInterval(15)
        while store.isRunning && Date() < deadline {
            if case .running(let progress) = store.items[0].state,
               let progress, progress > 0, progress < 0.999,
               store.items[0].phase == .hardwareTranscoding || store.items[0].phase == .softwareTranscoding {
                firstLiveProgress = firstLiveProgress ?? ProcessInfo.processInfo.systemUptime - started
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if store.isRunning {
            store.cancel()
            XCTFail("Synthetic realtime conversion did not finish within its deadline")
            return
        }
        let firstProgress = try XCTUnwrap(firstLiveProgress, "Conversion must show positive progress during transcoding, before verification/publication")
        print(String(format: "Synthetic 1080p-to-720p first positive progress: %.3f s", firstProgress))
        XCTAssertLessThan(firstProgress, 2.8)
        guard case .complete(let output) = store.items[0].state else {
            return XCTFail("Expected a complete 720p output; got \(store.items[0].state)")
        }
        let info = await ConverterStore.inspectMedia(at: output, using: ffprobe)
        XCTAssertTrue(info.probeSucceeded)
        XCTAssertEqual(info.width, 1280)
        XCTAssertEqual(info.height, 720)
        XCTAssertEqual(info.audioCodec, "aac")
        XCTAssertEqual(info.duration ?? 0, 3, accuracy: 0.15)
        let decoded = await FFmpegProcessRunner(
            executable: ffmpeg,
            arguments: ["-v", "error", "-i", output.path, "-map", "0:v:0", "-map", "0:a:0?", "-f", "null", "-"]
        ).run()
        XCTAssertTrue(decoded.succeeded, "The published video and audio must decode completely: \(decoded.standardError)")
    }

    private func periodicProgressScript(packetCount: Int, interval: Double) -> String {
        """
        $| = 1;
        for my $frame (1..\(packetCount)) {
            my $time = $frame * 100000;
            my $state = $frame == \(packetCount) ? 'end' : 'continue';
            print "frame=$frame\\nout_time_us=$time\\nprogress=$state\\n";
            select(undef, undef, undef, \(interval));
        }
        """
    }

    private func systemPerl() throws -> URL {
        let perl = URL(fileURLWithPath: "/usr/bin/perl")
        guard FileManager.default.isExecutableFile(atPath: perl.path) else {
            throw XCTSkip("System Perl is required for the single-process periodic-output fixture")
        }
        return perl
    }

    private func availableFFmpeg() throws -> URL {
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"] {
            let ffmpeg = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: path),
               FileManager.default.isExecutableFile(atPath: ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe").path) {
                return ffmpeg
            }
        }
        throw XCTSkip("FFmpeg and ffprobe are required for the synthetic conversion test")
    }
}

private final class RealtimeProgressObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var firstCallback: TimeInterval?
    private var callbackCount = 0
    private var text = ""

    func record(_ data: Data, elapsed: TimeInterval) {
        lock.lock()
        if firstCallback == nil { firstCallback = elapsed }
        callbackCount += 1
        text += String(decoding: data, as: UTF8.self)
        lock.unlock()
    }

    func snapshot() -> (firstCallback: TimeInterval?, callbackCount: Int, text: String) {
        lock.lock()
        defer { lock.unlock() }
        return (firstCallback, callbackCount, text)
    }
}
