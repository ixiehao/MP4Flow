import XCTest
@testable import FastConvert

final class DependencyInstallerTests: XCTestCase {
    func testMissingHomebrewDoesNotRunInstaller() async {
        let result = await DependencyInstaller.install(candidates: [URL(fileURLWithPath: "/nonexistent/mp4flow-brew")]) { _, _ in
            XCTFail("Installer must not run without Homebrew")
            return .init(succeeded: false, detail: "")
        }
        XCTAssertEqual(result, .homebrewMissing)
    }

    func testMissingFormulaIsInstalled() async {
        let result = await DependencyInstaller.install(candidates: [URL(fileURLWithPath: "/usr/bin/true")]) { _, arguments in
            .init(succeeded: arguments == ["install", "ffmpeg"], detail: "")
        }
        XCTAssertEqual(result, .installed)
    }

    func testExistingFormulaIsReinstalled() async {
        let result = await DependencyInstaller.install(candidates: [URL(fileURLWithPath: "/usr/bin/true")]) { _, arguments in
            .init(succeeded: arguments == ["list", "--versions", "ffmpeg"] || arguments == ["reinstall", "ffmpeg"], detail: "")
        }
        XCTAssertEqual(result, .installed)
    }

    func testFailureIsReported() async {
        let result = await DependencyInstaller.install(candidates: [URL(fileURLWithPath: "/usr/bin/true")]) { _, _ in
            .init(succeeded: false, detail: "network error")
        }
        XCTAssertEqual(result, .failed("network error"))
    }

    func testRealProcessRunsOnlyTheExpectedCommands() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let brew = directory.appendingPathComponent("brew")
        let script = """
        #!/bin/sh
        case "$*" in
        'list --versions ffmpeg') exit 1 ;;
        'install ffmpeg') exit 0 ;;
        *) exit 37 ;;
        esac
        """
        try Data(script.utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let result = await DependencyInstaller.install(candidates: [brew])
        XCTAssertEqual(result, .installed)
    }
}
