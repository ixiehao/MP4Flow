import Foundation
import XCTest
@testable import FastConvert

final class DependencyHealthTests: XCTestCase {
    func testProbeMustBelongToTheFirstSelectedFFmpegInstallation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeBinDirectory("first", in: directory)
        let second = try makeBinDirectory("second", in: directory)
        let selectedFFmpeg = try makeExecutable("ffmpeg", in: first)
        _ = try makeExecutable("ffmpeg", in: second)
        _ = try makeExecutable("ffprobe", in: second)

        let tools = DependencyToolResolver.resolve(in: [first, second])
        XCTAssertEqual(tools.ffmpeg, selectedFFmpeg)
        XCTAssertNil(tools.ffprobe, "A probe from another installation would falsely report the converter ready")

        let sibling = try makeExecutable("ffprobe", in: first)
        XCTAssertEqual(DependencyToolResolver.resolve(in: [first, second]).ffprobe, sibling)
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
