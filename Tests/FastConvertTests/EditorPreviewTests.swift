import Darwin
import Foundation
import XCTest
@testable import FastConvert

final class EditorPreviewTests: XCTestCase {
    func testEditorProbeReadsDurationDimensionsAndFractionalFrameRate() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = directory.appendingPathComponent("synthetic probe response.json")
        let payload: [String: Any] = [
            "streams": [
                ["codec_type": "audio"],
                ["codec_type": "video", "width": 1920, "height": 1080, "r_frame_rate": "30000/1001"]
            ],
            "format": ["duration": "12.345"]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: response)
        let probe = try makeJSONProbe(in: directory)

        let result = await EditorMediaProbe.inspect(source: response, using: probe)
        let media = try XCTUnwrap(result)
        XCTAssertEqual(media.duration, 12.345, accuracy: 0.0001)
        XCTAssertEqual(media.width, 1920)
        XCTAssertEqual(media.height, 1080)
        XCTAssertEqual(media.frameRate, 30000.0 / 1001.0, accuracy: 0.000001)
        XCTAssertEqual(media.frameDuration, 1001.0 / 30000.0, accuracy: 0.000001)
    }

    func testEditorProbeRejectsMalformedAndUnusableMediaResponses() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("damaged input.json")
        let probe = try makeJSONProbe(in: directory)
        let invalidResponses = [
            "{truncated media response",
            #"{"streams":[],"format":{"duration":"2"}}"#,
            #"{"streams":[{"codec_type":"video","width":0,"height":1080}],"format":{"duration":"2"}}"#,
            #"{"streams":[{"codec_type":"video","width":1920,"height":1080}],"format":{"duration":"nan"}}"#
        ]
        for response in invalidResponses {
            try response.write(to: source, atomically: true, encoding: .utf8)
            let media = await EditorMediaProbe.inspect(source: source, using: probe)
            XCTAssertNil(media, "Malformed or unusable probe data must not create an editor timeline")
        }
    }

    func testEditorProbeUsesDisplayedCoordinatesAndPixelShape() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("rotated response.json")
        let payload = #"{"streams":[{"codec_type":"video","width":64,"height":64,"disposition":{"attached_pic":1}},{"codec_type":"video","width":320,"height":240,"sample_aspect_ratio":"4:3","side_data_list":[{"rotation":90}],"r_frame_rate":"12/1"}],"format":{"duration":"2"}}"#
        try payload.write(to: source, atomically: true, encoding: .utf8)
        let probe = try makeJSONProbe(in: directory)
        let result = await EditorMediaProbe.inspect(source: source, using: probe)
        let media = try XCTUnwrap(result)
        XCTAssertEqual(media.width, 240)
        XCTAssertEqual(media.height, 320)
        XCTAssertEqual(media.pixelRatio, 0.75, accuracy: 0.0001)
        XCTAssertEqual(Double(media.width) / Double(media.height) * media.pixelRatio, 9.0 / 16, accuracy: 0.0001)
    }

    func testClosingEditorCancelsSilentProbeAndReapsItsProcess() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
            throw XCTSkip("System Perl is required for the single-process cancellation fixture")
        }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("owned probe.pid")
        let probe = directory.appendingPathComponent("silent ffprobe")
        // A direct shebang interpreter is the owned process, with no shell or
        // descendants holding its pipes. Ignore TERM to exercise bounded KILL.
        let fixture = """
        #!/usr/bin/perl
        $SIG{TERM} = 'IGNORE';
        open(my $pid, '>', $ARGV[-1]) or die "cannot create pid marker";
        print $pid "$$";
        close($pid);
        while (1) { select(undef, undef, undef, 1); }
        """
        try fixture.write(to: probe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: probe.path)

        let inspection = Task { await EditorMediaProbe.inspect(source: pidFile, using: probe) }
        let launchDeadline = Date().addingTimeInterval(2)
        var processID: Int32?
        while Date() < launchDeadline {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text), pid > 1 {
                processID = pid
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let processID else {
            inspection.cancel()
            _ = await inspection.value
            return XCTFail("The silent probe must actually launch before testing cancellation")
        }
        defer {
            if Darwin.kill(processID, 0) == 0 { _ = Darwin.kill(processID, SIGKILL) }
        }
        XCTAssertEqual(Darwin.kill(processID, 0), 0, "The probe must still be running when the editor closes")
        let started = ProcessInfo.processInfo.systemUptime
        inspection.cancel()
        let media = await inspection.value

        XCTAssertNil(media)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2, "Cancellation must not wait for the five-second editor-probe timeout")
        errno = 0
        let processStatus = Darwin.kill(processID, 0)
        let processError = errno
        XCTAssertEqual(processStatus, -1, "A cancelled editor must not leave its probe alive")
        XCTAssertEqual(processError, ESRCH, "The owned child should have exited and been reaped before inspection returns")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-EditorPreview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeJSONProbe(in directory: URL) throws -> URL {
        let executable = directory.appendingPathComponent("JSON ffprobe")
        try "#!/bin/sh\nfor source in \"$@\"; do :; done\nexec /bin/cat \"$source\"\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
