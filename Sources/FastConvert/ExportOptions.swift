import Foundation

struct MediaTrack: Equatable, Sendable, Identifiable {
    let index: Int
    let ordinal: Int
    let codec: String
    let language: String?
    let title: String?
    var bitRate: Int? = nil
    var sampleRate: String? = nil
    var channels: Int? = nil
    var channelLayout: String? = nil
    var timeBase: String? = nil
    var isDefault = false
    var id: Int { index }
    var label: String {
        (["\(ordinal + 1)", language, title, codec.uppercased()].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: " · ")
    }
    var supportsTextSubtitle: Bool {
        ["subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text"].contains(codec.lowercased())
    }
}

enum AudioSelection: String, CaseIterable, Codable, Sendable {
    case all, selected, first, none
    var title: String {
        switch self {
        case .first: L10n.text("第一路音轨")
        case .selected: L10n.text("选择音轨")
        case .all: L10n.text("全部音轨")
        case .none: L10n.text("静音")
        }
    }
}

enum SubtitleTreatment: String, CaseIterable, Codable, Sendable {
    case none, keep, burn
    var title: String {
        switch self {
        case .none: L10n.text("不保留字幕")
        case .keep: L10n.text("保留所选字幕")
        case .burn: L10n.text("烧录所选字幕")
        }
    }
}

/// Per-file choices are independent of translated labels and survive relaunch.
struct ExportOptions: Equatable, Codable, Sendable {
    var targetSizeMB: Double?
    var audio: AudioSelection = .all
    var audioStreamIndex: Int?
    var subtitles: SubtitleTreatment = .none
    var subtitleStreamIndex: Int?

    var normalized: ExportOptions {
        var result = self
        if audio != .selected { result.audioStreamIndex = nil }
        if subtitles == .none { result.subtitleStreamIndex = nil }
        return result
    }
    var isDefault: Bool { targetSizeMB == nil && audio == .all && subtitles == .none }
    /// Enabling the optional budget must not silently recommend a large
    /// reduction, especially for an already heavily compressed source.
    static func suggestedTargetMegabytes(sourceBytes: Int64?) -> Int {
        guard let sourceBytes, sourceBytes > 0 else { return 100 }
        return Int(min(100_000, max(1, (Double(sourceBytes) / 1_000_000).rounded(.up))))
    }
    var summary: String {
        var parts: [String] = []
        if let targetSizeMB, targetSizeMB.isFinite, (1...100_000).contains(targetSizeMB) { parts.append(L10n.format("目标约 %@ · 体积优先", L10n.byteCount(Int64((targetSizeMB * 1_000_000).rounded())))) }
        if audio != .all { parts.append(audio.title) }
        if subtitles != .none { parts.append(subtitles.title) }
        return L10n.list(parts)
    }

    func audioCount(in info: VideoInfo) -> Int {
        switch audio {
        case .none: 0
        case .all: info.audioTrackCount
        case .first, .selected: min(1, info.audioTrackCount)
        }
    }
    func chosenAudio(in info: VideoInfo) -> [MediaTrack] {
        switch audio {
        case .none: []
        case .all: info.audioTracks
        case .first: Array(info.audioTracks.prefix(1))
        case .selected: info.audioTracks.filter { $0.index == audioStreamIndex }
        }
    }
    func chosenSubtitle(in info: VideoInfo) -> MediaTrack? {
        info.subtitleTracks.first { $0.index == subtitleStreamIndex }
    }
    func supportsNativeEnhancement(info: VideoInfo) -> Bool {
        targetSizeMB == nil && subtitles == .none && (audio == .first || (audio == .all && info.audioTrackCount <= 1))
    }
    func validate(info: VideoInfo, trim: ClipRange?) throws -> TargetSizePlan? {
        if let trim {
            guard trim.isValid, info.duration.map({ !$0.isFinite || trim.end <= $0 + 0.15 }) != false else { throw ExportOptionError.invalidTrim }
        }
        if audio == .selected, chosenAudio(in: info).isEmpty { throw ExportOptionError.missingAudio }
        if subtitles != .none {
            guard let track = chosenSubtitle(in: info) else { throw ExportOptionError.missingSubtitle }
            guard track.supportsTextSubtitle else { throw ExportOptionError.unsupportedSubtitle }
        }
        guard let targetSizeMB else { return nil }
        return try TargetSizePlan(megabytes: targetSizeMB, duration: trim.map { $0.end - $0.start } ?? info.duration, audioTracks: audioCount(in: info), sourceVideoRate: info.videoRate)
    }

    var audioMaps: [String] {
        switch audio {
        case .first: ["-map", "0:a:0?"]
        case .selected: audioStreamIndex.map { ["-map", "0:\($0)"] } ?? []
        case .all: ["-map", "0:a?"]
        case .none: []
        }
    }
    func burnFilter(source: URL, info: VideoInfo, trim: ClipRange?) -> [String] {
        guard subtitles == .burn, let track = chosenSubtitle(in: info) else { return [] }
        let subtitle = "subtitles=filename=\(Self.escapeFilterOption(source.path)):si=\(track.ordinal)"
        guard let trim, trim.start > 0 else { return [subtitle] }
        let start = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), trim.start)
        return ["setpts=PTS+\(start)/TB", subtitle, "setpts=PTS-\(start)/TB"]
    }
    /// FFmpeg parses filter graphs and filter options separately. No shell is involved.
    static func escapeFilterOption(_ value: String) -> String {
        func escape(_ value: String, characters: String) -> String {
            value.reduce(into: "") { result, char in
                if characters.contains(char) { result.append("\\") }
                result.append(char)
            }
        }
        return escape(escape(value, characters: "\\':"), characters: "\\'[],;")
    }
}

struct TargetSizePlan: Equatable, Sendable {
    let targetBytes: Int64
    let videoRate: Int
    let audioRatePerTrack: Int
    init(megabytes: Double, duration: Double?, audioTracks: Int, sourceVideoRate: Int? = nil) throws {
        guard megabytes.isFinite, (1...100_000).contains(megabytes), (0...128).contains(audioTracks) else { throw ExportOptionError.invalidSize }
        guard let duration, duration.isFinite, duration > 0 else { throw ExportOptionError.unknownDuration }
        targetBytes = Int64((megabytes * 1_000_000).rounded())
        audioRatePerTrack = audioTracks == 0 ? 0 : 128_000
        let rate = Double(targetBytes) * 0.97 * 8 / duration - Double(audioRatePerTrack * audioTracks)
        guard rate.isFinite, rate >= 64_000 else { throw ExportOptionError.impracticalSize }
        // A generous size request must not allocate an unbounded encoder buffer.
        let sourceCeiling = sourceVideoRate.flatMap { $0 > 0 ? Double(max(64_000, $0)) : nil } ?? 100_000_000
        videoRate = Int(min(rate, sourceCeiling, 100_000_000).rounded(.down))
    }
}

enum ExportOptionError: Error, LocalizedError, CaseIterable {
    case invalidSize, invalidTrim, unknownDuration, impracticalSize, missingAudio, missingSubtitle, unsupportedSubtitle, incompatibleEnhancement, hdrEdits, inspectionUnavailable, missingRenderer
    var errorDescription: String? { L10n.text(reasonKey) }
    var reasonKey: String {
        switch self {
        case .invalidSize: "目标体积请输入 1–100000 MB。"
        case .invalidTrim: "剪切范围无效，请重新选择起止时间。"
        case .unknownDuration: "无法确认时长，暂不能估算目标体积。"
        case .impracticalSize: "目标体积不适合此时长，请调整目标或音轨数量。"
        case .missingAudio: "所选音轨不可用，请重新选择。"
        case .missingSubtitle: "所选字幕不可用，请重新选择。"
        case .unsupportedSubtitle: "此字幕格式暂不支持，请选择文字字幕或不保留。"
        case .incompatibleEnhancement: "这些导出选项暂不适用于智能增强，请使用智能转换。"
        case .hdrEdits: "HDR 暂不支持目标体积压缩或字幕烧录，请先转换为 SDR。"
        case .inspectionUnavailable: "无法读取音轨与字幕，请检查文件和 FFprobe。"
        case .missingRenderer: "当前 FFmpeg 不支持字幕烧录，可保留字幕或安装支持 libass 的版本。"
        }
    }
}
