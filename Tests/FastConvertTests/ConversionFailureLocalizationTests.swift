import Foundation
import XCTest
@testable import FastConvert

final class ConversionFailureLocalizationTests: XCTestCase {
    func testStallAndHardwareFailuresKeepTheSameClassificationInEveryLanguage() {
        let defaults = UserDefaults.standard
        let domainName = "NSArgumentDomain"
        let originalDomain = defaults.volatileDomain(forName: domainName)
        defer { defaults.setVolatileDomain(originalDomain, forName: domainName) }

        for language in AppLanguage.allCases {
            var domain = originalDomain
            domain["appLanguage"] = language.rawValue
            defaults.setVolatileDomain(domain, forName: domainName)

            let stalled = ConverterStore.failure(from: "MP4Flow:stalled")
            XCTAssertEqual(stalled.reasonKey, "转换长时间无进度，已安全停止", language.rawValue)
            XCTAssertEqual(stalled.solutionKey, "请确认视频可播放、磁盘可用后重试；仍失败请使用「最稳妥转换」。", language.rawValue)
            XCTAssertEqual(stalled.diagnostic, "ffmpeg:stalled", language.rawValue)
            XCTAssertEqual(stalled.reason, L10n.text(stalled.reasonKey))
            XCTAssertEqual(stalled.solution, L10n.text(stalled.solutionKey))

            for stderr in [
                "Unknown encoder 'h264_videotoolbox'",
                "[hevc_videotoolbox] Encoder not available",
                "VTCompressionSessionCreate failed with error -12903"
            ] {
                let message = ConverterStore.ffmpegFailureMessage(stderr)
                XCTAssertEqual(message, "MP4Flow:hardware-encoder", language.rawValue)
                let hardware = ConverterStore.failure(from: message)
                XCTAssertEqual(hardware.reasonKey, "硬件编码不可用", language.rawValue)
                XCTAssertEqual(hardware.solutionKey, "请重试；仍失败请使用「最稳妥转换」。", language.rawValue)
                XCTAssertEqual(hardware.diagnostic, "ffmpeg:hardware-encoder", language.rawValue)
                XCTAssertEqual(hardware.reason, L10n.text(hardware.reasonKey))
                XCTAssertEqual(hardware.solution, L10n.text(hardware.solutionKey))
            }
            let software = ConverterStore.ffmpegFailureMessage("Unknown encoder 'libx264'")
            XCTAssertNotEqual(software, "MP4Flow:hardware-encoder", "A missing software encoder must not be described as hardware failure")
            let disk = ConverterStore.ffmpegFailureMessage("[h264_videotoolbox] Error submitting frame\nNo space left on device")
            XCTAssertEqual(disk, "MP4Flow:disk-full", "A terminal I/O failure must keep priority over hardware markers")
        }
    }

    func testKnownMediaToolAndContainerErrorsStayTypedInEveryLanguage() {
        let cases: [(stderr: String?, sentinel: String, reason: String, solution: String, diagnostic: String)] = [
            (
                "Invalid data found when processing input: /private/customer/video.mp4",
                "MP4Flow:unreadable-media",
                "无法读取此视频的媒体数据",
                "请确认文件可播放，或使用「智能转换」生成新文件后重试。",
                "ffmpeg:unreadable-media"
            ),
            (
                "moov atom not found",
                "MP4Flow:unreadable-media",
                "无法读取此视频的媒体数据",
                "请确认文件可播放，或使用「智能转换」生成新文件后重试。",
                "ffmpeg:unreadable-media"
            ),
            (
                "Unknown encoder 'libx264'",
                "MP4Flow:software-encoder",
                "软件编码器不可用",
                "请更新或重新安装 FFmpeg，或改用「智能转换」后重试。",
                "ffmpeg:software-encoder"
            ),
            (
                "Could not find tag for codec pcm_s16le in stream #1, codec not currently supported in container",
                "MP4Flow:container-incompatible",
                "此视频流无法直接写入 MP4",
                "请使用「智能转换」重新编码后重试；仍失败请使用「最稳妥转换」。",
                "ffmpeg:container-incompatible"
            ),
            (
                nil,
                "MP4Flow:launch-failed",
                "无法启动转换工具",
                "请在「环境体检」检查 FFmpeg，修复安装或权限后重试。",
                "ffmpeg:launch-failed"
            ),
            (
                "Unexpected muxer diagnostic involving /private/customer/video.mp4",
                "MP4Flow:conversion-failed",
                "转换未完成",
                "请重试；仍失败请使用「最稳妥转换」。",
                "ffmpeg:failed"
            )
        ]
        let defaults = UserDefaults.standard
        let domainName = "NSArgumentDomain"
        let originalDomain = defaults.volatileDomain(forName: domainName)
        defer { defaults.setVolatileDomain(originalDomain, forName: domainName) }
        for language in AppLanguage.allCases {
            var domain = originalDomain
            domain["appLanguage"] = language.rawValue
            defaults.setVolatileDomain(domain, forName: domainName)
            for sample in cases {
                let message = sample.stderr.map { ConverterStore.ffmpegFailureMessage($0) } ?? sample.sentinel
                XCTAssertEqual(message, sample.sentinel, language.rawValue)
                let failure = ConverterStore.failure(from: message)
                XCTAssertEqual(failure.reasonKey, sample.reason, language.rawValue)
                XCTAssertEqual(failure.solutionKey, sample.solution, language.rawValue)
                XCTAssertEqual(failure.diagnostic, sample.diagnostic, language.rawValue)
                XCTAssertFalse([failure.reason, failure.solution, failure.diagnostic ?? ""].joined().contains("customer"))
                XCTAssertEqual(failure.reason, L10n.text(sample.reason))
                XCTAssertEqual(failure.solution, L10n.text(sample.solution))
            }
            XCTAssertEqual(
                ConverterStore.ffmpegFailureMessage("Could not find tag for codec pcm_s16le\nPermission denied"),
                "MP4Flow:permission",
                "Permission failures take priority over codec/container context"
            )
        }
    }
}
