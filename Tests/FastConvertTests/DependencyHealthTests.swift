import Foundation
import XCTest
@testable import FastConvert

final class DependencyHealthTests: XCTestCase {
    func testRepeatedFastHealthCommandsFinishWithoutBlockingExitWait() async throws {
        let started = Date()
        for _ in 0..<16 {
            let result = await DependencyHealthCommand.run(
                URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["ffmpeg version test\\n"], timeout: 2
            )
            XCTAssertTrue(result.succeeded)
            XCTAssertEqual(String(decoding: result.standardOutput, as: UTF8.self), "ffmpeg version test\n")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testHealthProbeDrainsLargeOutputAndBoundsRetainedDiagnostics() async throws {
        let result = await DependencyHealthCommand.run(
            try perl(), arguments: ["-e", "print 'o' x 262144; print STDERR 'e' x 131072;"], timeout: 3
        )
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput.count, 128 * 1_024)
        XCTAssertEqual(result.standardError.utf8.count, 16 * 1_024)
    }

    func testHealthProbeDeadlineStopsEvenContinuouslyPrintingTool() async throws {
        let started = Date()
        let result = await DependencyHealthCommand.run(
            try perl(),
            arguments: ["-e", "$|=1; $SIG{TERM}=sub{}; while(1){print qq{output\\n}; select(undef,undef,undef,0.02)}"],
            timeout: 0.2
        )
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.wasCancelled || result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "Output activity must not postpone a health probe's total deadline")
    }

    func testCancellingHealthProbeReapsItsProcess() async throws {
        let executable = try perl()
        let started = Date()
        let task = Task {
            await DependencyHealthCommand.run(executable, arguments: ["-e", "$SIG{TERM}=sub{}; sleep 30"], timeout: 30)
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.wasCancelled)
        XCTAssertNotNil(result.terminationStatus)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testIncompleteInstallationDoesNotHideACompleteSiblingPair() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeBinDirectory("first", in: directory)
        let second = try makeBinDirectory("second", in: directory)
        let preferredFFmpeg = try makeExecutable("ffmpeg", in: first)
        let completeFFmpeg = try makeExecutable("ffmpeg", in: second)
        let completeProbe = try makeExecutable("ffprobe", in: second)

        let tools = DependencyToolResolver.resolve(in: [first, second])
        XCTAssertEqual(tools.ffmpeg, completeFFmpeg)
        XCTAssertEqual(tools.ffprobe, completeProbe, "The chosen tools must be a complete pair from one installation")

        let sibling = try makeExecutable("ffprobe", in: first)
        XCTAssertEqual(DependencyToolResolver.resolve(in: [first, second]).ffmpeg, preferredFFmpeg)
        XCTAssertEqual(DependencyToolResolver.resolve(in: [first, second]).ffprobe, sibling)
    }

    func testProbeFromDifferentInstallationIsNeverBorrowed() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeBinDirectory("first", in: directory)
        let second = try makeBinDirectory("unrelated-probe", in: directory)
        let ffmpeg = try makeExecutable("ffmpeg", in: first)
        _ = try makeExecutable("ffprobe", in: second)
        let tools = DependencyToolResolver.resolve(in: [first, second])
        XCTAssertEqual(tools.ffmpeg, ffmpeg)
        XCTAssertNil(tools.ffprobe, "A standalone probe cannot complete another installation")
    }

    func testNonExecutableProbeDoesNotHideLaterCompleteInstallation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeBinDirectory("partial", in: directory)
        let second = try makeBinDirectory("complete", in: directory)
        _ = try makeExecutable("ffmpeg", in: first)
        try Data().write(to: first.appendingPathComponent("ffprobe"))
        let ffmpeg = try makeExecutable("ffmpeg", in: second)
        let probe = try makeExecutable("ffprobe", in: second)
        let tools = DependencyToolResolver.resolve(in: [first, second])
        XCTAssertEqual(tools.ffmpeg, ffmpeg)
        XCTAssertEqual(tools.ffprobe, probe)
    }

    func testDefaultDirectoriesPreferTheExecutableArchitecture() {
#if arch(arm64)
        let prefix = "/opt/homebrew"
#else
        let prefix = "/usr/local"
#endif
        XCTAssertEqual(DependencyToolResolver.defaultDirectories.prefix(2).map(\.path),
                       [prefix + "/opt/ffmpeg-full/bin", prefix + "/bin"])
        XCTAssertEqual(Set(DependencyToolResolver.defaultDirectories).count, DependencyToolResolver.defaultDirectories.count)
    }

    func testAnUnrelatedProbeWithoutFFmpegCannotReportAUsableInstallation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeExecutable("ffprobe", in: directory)
        let tools = DependencyToolResolver.resolve(in: [directory])
        XCTAssertNil(tools.ffmpeg)
        XCTAssertNil(tools.ffprobe)
    }

    func testNonExecutableSiblingProbeIsRetainedForFailureDiagnostics() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeExecutable("ffmpeg", in: directory)
        let probe = directory.appendingPathComponent("ffprobe")
        try Data().write(to: probe)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: probe.path)
        XCTAssertEqual(DependencyToolResolver.resolve(in: [directory]).ffprobe, probe)
        XCTAssertFalse(FileManager.default.isExecutableFile(atPath: probe.path))
    }

    func testExecutableInstallationTakesPriorityOverAnEarlierBrokenCandidate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeBinDirectory("broken", in: directory)
        let second = try makeBinDirectory("working", in: directory)
        let broken = first.appendingPathComponent("ffmpeg")
        try Data().write(to: broken)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: broken.path)
        XCTAssertEqual(DependencyToolResolver.resolve(in: [first]).ffmpeg, broken)
        let working = try makeExecutable("ffmpeg", in: second)
        XCTAssertEqual(DependencyToolResolver.resolve(in: [first, second]).ffmpeg, working)
    }

    private func perl() throws -> URL {
        let executable = URL(fileURLWithPath: "/usr/bin/perl")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("System Perl is required for a single-process health probe fixture")
        }
        return executable
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-ToolResolution-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeBinDirectory(_ name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func makeExecutable(_ name: String, in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }
}
