import Foundation
import XCTest
@testable import FastConvert

final class MediaNoticeTests: XCTestCase {
    func testOrdinaryFilesAndVideoOnlyFilesHaveNoNotice() {
        for preset in [ConversionPreset.remux, .h264Hardware, .h264Software, .smartEnhanceUpscale] {
            XCTAssertNil(ConverterStore.mediaHandlingNotice(for: fixture(), preset: preset))
            XCTAssertNil(ConverterStore.mediaHandlingNotice(for: fixture(audioTracks: 0), preset: preset), "Video-only input is a supported format, not a warning")
        }
    }

    func testNoticesDescribeOnlyRealContentLoss() throws {
        let notice = try XCTUnwrap(ConverterStore.mediaHandlingNotice(for: fixture(videoTracks: 2, audioTracks: 3, subtitles: 2, chapters: 4), preset: .remux))
        XCTAssertEqual(notice.issues, [.extraVideo(2), .extraAudio(3), .subtitles(2), .chapters(4)])
        XCTAssertTrue(notice.summary.isEmpty)
        XCTAssertEqual(notice.warnings, [
            L10n.format("检测到 %d 路视频；仅保留第一路。", 2),
            L10n.format("检测到 %d 路音频；仅保留第一路。", 3),
            L10n.format("检测到 %d 条字幕；输出不保留字幕。", 2),
            L10n.format("检测到 %d 个章节；输出不保留章节。", 4)
        ])
        XCTAssertFalse(notice.detail.hasPrefix("\n"))
        XCTAssertFalse(notice.detail.contains(L10n.text("容器元数据和章节将被移除。")), "Routine metadata cleanup belongs in the policy detail, not every queue row")
    }

    func testHDRWarnsForReencodingButNotForUntouchedVideoCopy() throws {
        let hdr = fixture(colorTransfer: "smpte2084")
        XCTAssertNil(ConverterStore.mediaHandlingNotice(for: hdr, preset: .remux))
        let notice = try XCTUnwrap(ConverterStore.mediaHandlingNotice(for: hdr, preset: .h264Hardware))
        XCTAssertEqual(notice.warnings, [L10n.format("HDR 将重新编码，色彩或动态范围可能改变；如需保留，请保持原尺寸并使用「%@」。", ConversionPreset.remux.title)])
    }

    func testNormalRotationIsQuietAndNonstandardReencodingIsExplained() throws {
        XCTAssertNil(ConverterStore.mediaHandlingNotice(for: fixture(rotation: 90), preset: .h264Hardware))
        XCTAssertNil(ConverterStore.mediaHandlingNotice(for: fixture(rotation: 45), preset: .remux))
        let notice = try XCTUnwrap(ConverterStore.mediaHandlingNotice(for: fixture(rotation: 45), preset: .h264Hardware))
        XCTAssertEqual(notice.warnings, [L10n.text("非标准旋转角度将重绘画面；请核对输出方向与边缘。")])
    }

    func testUnconfirmedProbeIsNotPresentedAsSafe() throws {
        let failed = try XCTUnwrap(ConverterStore.mediaHandlingNotice(for: fixture(probeSucceeded: false), preset: .remux))
        XCTAssertEqual(failed.summary, L10n.text("素材信息尚未确认"))
        XCTAssertFalse(failed.warnings.isEmpty)
        XCTAssertNotNil(ConverterStore.mediaHandlingNotice(for: fixture(videoTracks: 0), preset: .remux))
    }

    func testMissingSourceDoesNotBecomeAPermissionError() {
        let failure = ConverterStore.failure(from: "MP4Flow:missing-source")
        XCTAssertEqual(failure.reasonKey, "源文件已移动、删除或无法访问")
        XCTAssertEqual(failure.solutionKey, "请在访达中确认源文件仍存在，重新添加后再试。")
        XCTAssertEqual(failure.diagnostic, "ffmpeg:missing-source")
        XCTAssertEqual(failure.reason, L10n.text("源文件已移动、删除或无法访问"))
        XCTAssertEqual(failure.solution, L10n.text("请在访达中确认源文件仍存在，重新添加后再试。"))
        XCTAssertNotEqual(failure.reason, ConverterStore.failure(from: "MP4Flow:permission").reason)
    }

    func testRetainedFailuresAndNoticesResolveLanguageWhenRead() throws {
        let failure = ConverterStore.failure(from: "MP4Flow:missing-source")
        let notice = try XCTUnwrap(ConverterStore.mediaHandlingNotice(for: fixture(audioTracks: 2, colorTransfer: "smpte2084"), preset: .h264Hardware))
        let unknown = try XCTUnwrap(ConverterStore.mediaHandlingNotice(for: fixture(probeSucceeded: false), preset: .remux))
        XCTAssertEqual(failure.reasonKey, "源文件已移动、删除或无法访问")
        XCTAssertEqual(failure.solutionKey, "请在访达中确认源文件仍存在，重新添加后再试。")
        XCTAssertEqual(notice.issues, [.extraAudio(2), .hdrReencoding])
        XCTAssertEqual(unknown.issues, [.unconfirmed])

        // Override only the process's volatile argument domain. Do not change
        // persistent app preferences while exercising an in-memory result.
        let defaults = UserDefaults.standard
        let domainName = "NSArgumentDomain"
        let originalDomain = defaults.volatileDomain(forName: domainName)
        defer { defaults.setVolatileDomain(originalDomain, forName: domainName) }
        for language in AppLanguage.allCases {
            var domain = originalDomain
            domain["appLanguage"] = language.rawValue
            defaults.setVolatileDomain(domain, forName: domainName)
            XCTAssertEqual(failure.reason, L10n.text(failure.reasonKey))
            XCTAssertEqual(failure.solution, L10n.text(failure.solutionKey))
            XCTAssertEqual(failure, ConverterStore.failure(from: "MP4Flow:missing-source"), "Storage must remain language-independent")
            XCTAssertEqual(notice.warnings, [
                L10n.format("检测到 %d 路音频；仅保留第一路。", 2),
                L10n.format("HDR 将重新编码，色彩或动态范围可能改变；如需保留，请保持原尺寸并使用「%@」。", ConversionPreset.remux.title)
            ])
            XCTAssertEqual(unknown.summary, L10n.text("素材信息尚未确认"))
            XCTAssertEqual(unknown.warnings, [L10n.text("请确认文件可播放后重试；检测完成前不会开始转换。")])
        }
    }

    func testProbeCountsVideoTracksAndActualChapters() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-notices-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("probe.json")
        let json = """
        {"streams":[
          {"codec_type":"video","codec_name":"h264","width":1280,"height":720,"sample_aspect_ratio":"1:1"},
          {"codec_type":"video","codec_name":"h264","width":1280,"height":720},
          {"codec_type":"audio","codec_name":"aac"}
        ],"format":{"duration":"1.0"},"chapters":[{"id":0},{"id":1}]}
        """
        try json.write(to: source, atomically: true, encoding: .utf8)
        let probe = directory.appendingPathComponent("ffprobe")
        try "#!/bin/sh\nfor argument in \"$@\"; do :; done\nexec /bin/cat \"$argument\"\n".write(to: probe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: probe.path)
        let info = await ConverterStore.inspectMedia(at: source, using: probe)
        XCTAssertTrue(info.probeSucceeded)
        XCTAssertEqual(info.videoTrackCount, 2)
        XCTAssertEqual(info.chapterCount, 2)
        let notice = try XCTUnwrap(ConverterStore.mediaHandlingNotice(for: info, preset: .remux))
        XCTAssertEqual(notice.warnings.count, 2)
    }

#if compiler(>=6.4)
    func testEnhancementErrorsKeepTheirCauseWithoutExposingPrivateDetails() throws {
        guard #available(macOS 27.0, *) else { throw XCTSkip("The native enhancement error type requires macOS 27") }
        let writer = ConverterStore.enhancementFailure(for: .writer("Private path /private/customer/video.mp4: failed"))
        XCTAssertEqual(writer.diagnostic, "enhance:write-failed")
        XCTAssertEqual(writer.reason, L10n.text("无法写入智能增强输出文件。"))
        XCTAssertEqual(writer.solution, L10n.text("请检查剩余空间和输出文件夹权限，或改用本地文件夹后重试。"))
        XCTAssertFalse([writer.reason, writer.solution, writer.diagnostic ?? ""].joined().contains("customer"))
        XCTAssertEqual(ConverterStore.enhancementFailure(for: .reader("private details")).diagnostic, "enhance:unreadable-source")
        XCTAssertEqual(ConverterStore.enhancementFailure(for: .unavailable).diagnostic, "enhance:unavailable")
        XCTAssertEqual(ConverterStore.enhancementFailure(for: .processingTimeout).diagnostic, "enhance:processing-timeout")
        XCTAssertEqual(ConverterStore.enhancementFailure(for: .finalizationTimeout).diagnostic, "enhance:finalization-timeout")
    }
#endif

    private func fixture(videoTracks: Int = 1, audioTracks: Int = 1, subtitles: Int = 0, chapters: Int = 0, colorTransfer: String? = nil, rotation: Double? = nil, probeSucceeded: Bool = true) -> VideoInfo {
        var info = VideoInfo(duration: 1, videoRate: 1_000_000, audioRate: audioTracks > 0 ? 128_000 : nil, width: 1280, height: 720, hasVideo: videoTracks > 0, videoCodec: "h264", audioCodec: audioTracks > 0 ? "aac" : nil, frameRate: "30/1", pixelFormat: "yuv420p", audioSampleRate: "48000", audioChannels: 2, audioTrackCount: audioTracks, subtitleTrackCount: subtitles, colorTransfer: colorTransfer, probeSucceeded: probeSucceeded)
        info.videoTrackCount = videoTracks
        info.chapterCount = chapters
        info.displayRotation = rotation
        return info
    }
}
