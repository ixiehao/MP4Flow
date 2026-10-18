import Foundation
import XCTest
@testable import FastConvert

final class ProcessLifecycleTests: XCTestCase {
    func testLargeStdoutAndStderrDrainThroughEOF() async {
        let script = """
        i=0
        while [ "$i" -lt 4000 ]; do
          printf 'output-packet-0123456789012345678901234567890123456789\n'
          printf 'error-packet-01234567890123456789012345678901234567890\n' >&2
          i=$((i + 1))
        done
        printf 'final-output'
        printf 'final-error' >&2
        exit 7
        """
        let result = await shell(script).run()
        XCTAssertEqual(result.terminationStatus, 7)
        XCTAssertGreaterThan(result.standardOutput.count, 64 * 1_024)
        XCTAssertTrue(String(decoding: result.standardOutput, as: UTF8.self).hasSuffix("final-output"))
        XCTAssertTrue(result.standardError.hasSuffix("final-error"))
        XCTAssertLessThanOrEqual(result.standardError.utf8.count, 4_000)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.wasCancelled)
    }

    func testStderrNoiseCannotKeepStalledProcessAlive() async {
        let runner = shell(
            "trap '' TERM; while :; do printf 'decoder still waiting\\n' >&2; done",
            timeout: 0.2
        )
        let started = Date()
        let result = await runner.run()
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.standardError.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testCancellationEscalatesForUnresponsiveProcess() async throws {
        let runner = shell("trap '' TERM; while :; do :; done")
        let task = Task { await runner.run() }
        try await Task.sleep(nanoseconds: 100_000_000)
        let started = Date()
        runner.cancel()
        let result = await task.value
        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testRepeatedUnchangedProgressDoesNotHideStall() async {
        let runner = FFmpegProcessRunner(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; while :; do printf 'frame=1\\nout_time_us=1000\\ntotal_size=100\\nprogress=continue\\n'; done"],
            configuration: FFmpegProcessRunner.Configuration(
                inactivityTimeout: 0.2,
                terminationGrace: 0.05,
                pollingInterval: 0.02,
                activityPolicy: .advancingFFmpegProgress,
                maximumOutputBytes: 0
            )
        )
        let started = Date()
        let result = await runner.run()
        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(result.standardOutput.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testCancellationBeforeLaunchPreventsExecution() async {
        let runner = shell("printf 'must not execute'")
        runner.cancel()
        let result = await runner.run()
        XCTAssertTrue(result.wasCancelled)
        XCTAssertNil(result.terminationStatus)
        XCTAssertTrue(result.standardOutput.isEmpty)
    }

    func testCancellingInspectionTaskStopsItsOwnedProcess() async throws {
        let runner = shell("trap '' TERM; while :; do :; done")
        let task = Task {
            await ConverterStore.inspectMedia(
                at: URL(fileURLWithPath: "/unused-media"),
                using: URL(fileURLWithPath: "/bin/sh"),
                runner: runner
            )
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let started = Date()
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result.probeSucceeded)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testLaunchFailureCompletesPipeDrains() async {
        let runner = FFmpegProcessRunner(executable: URL(fileURLWithPath: "/MP4Flow-nonexistent-executable"), arguments: [])
        let started = Date()
        let result = await runner.run()
        XCTAssertNotNil(result.launchError)
        XCTAssertNil(result.terminationStatus)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testCompletedRunnerReleasesWatchdogPromptly() async throws {
        var runner: FFmpegProcessRunner? = shell("printf 'complete'", timeout: 60)
        let reference = WeakProcessRunnerReference(runner)
        let result = await runner!.run()
        XCTAssertTrue(result.succeeded)
        runner = nil
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(reference.value, "A completed subprocess must not stay retained until its old watchdog deadline")
    }

    @MainActor
    func testCancelledMergeCanRestartAndPublishVerifiedOutput() async throws {
        guard let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
            .map({ URL(fileURLWithPath: $0) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path)
                && FileManager.default.isExecutableFile(atPath: $0.deletingLastPathComponent().appendingPathComponent("ffprobe").path) }) else {
            throw XCTSkip("FFmpeg and ffprobe are required for the merge integration check")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-MergeLifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.mp4")
        let second = directory.appendingPathComponent("second.mp4")
        let generation = await FFmpegProcessRunner(
            executable: ffmpeg,
            arguments: ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=red:s=64x48:r=8:d=2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-y", first.path]
        ).run()
        guard generation.succeeded else { throw XCTSkip("libx264 is required to create the merge fixture") }
        try FileManager.default.copyItem(at: first, to: second)

        let controlledFFmpeg = directory.appendingPathComponent("ffmpeg")
        let quotedFFmpeg = "'" + ffmpeg.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // exec replaces the wrapper process so cancellation targets FFmpeg
        // itself and no shell child can keep its inherited pipes open.
        try "#!/bin/sh\nexec \(quotedFFmpeg) -re \"$@\"\n".write(to: controlledFFmpeg, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: controlledFFmpeg.path)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("ffprobe"),
            withDestinationURL: ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        )

        let store = ConverterStore(ffmpegOverride: controlledFFmpeg)
        store.outputDirectory = directory
        store.items = [ConversionItem(source: first), ConversionItem(source: second)]
        store.mergeWaitingItems()
        XCTAssertTrue(store.isMerging)
        let runningDeadline = Date().addingTimeInterval(5)
        var runningPartial: URL?
        while store.isMerging && Date() < runningDeadline {
            let partial = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
                .first { $0.lastPathComponent.hasPrefix(".MP4Flow-") && $0.lastPathComponent.hasSuffix(".partial.mp4") }
            if let partial, (try partial.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0,
               (store.mergeProgress ?? 0) > 0 {
                runningPartial = partial
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(runningPartial, "Cancel must exercise a running writer, not merely the initial probe")
        store.cancel()
        try await waitForMerge(store)
        XCTAssertNil(store.mergeOutput)
        if let runningPartial { XCTAssertFalse(FileManager.default.fileExists(atPath: runningPartial.path)) }
        let afterCancel = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }
        XCTAssertEqual(Set(afterCancel.map(\.lastPathComponent)), Set([first.lastPathComponent, second.lastPathComponent]), "A cancelled merge must not publish its partial output")

        store.mergeWaitingItems()
        try await waitForMerge(store)
        let output = try XCTUnwrap(store.mergeOutput, store.mergeNotice)
        let info = await ConverterStore.inspectMedia(at: output, using: ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe"))
        XCTAssertTrue(info.probeSucceeded)
        XCTAssertTrue(info.hasVideo)
        XCTAssertEqual(info.duration ?? 0, 4, accuracy: 0.15)
        let leftovers = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".MP4Flow-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    private func shell(_ script: String, timeout: TimeInterval = 5) -> FFmpegProcessRunner {
        FFmpegProcessRunner(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            configuration: FFmpegProcessRunner.Configuration(
                inactivityTimeout: timeout,
                terminationGrace: 0.05,
                pollingInterval: 0.02
            )
        )
    }

    @MainActor
    private func waitForMerge(_ store: ConverterStore) async throws {
        let deadline = Date().addingTimeInterval(10)
        while store.isMerging && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if store.isMerging {
            store.cancel()
            XCTFail("The merge did not finish within its test deadline")
        }
    }
}

private final class WeakProcessRunnerReference {
    weak var value: FFmpegProcessRunner?
    init(_ value: FFmpegProcessRunner?) { self.value = value }
}
