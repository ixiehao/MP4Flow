import Foundation

/// Track order is part of the merge contract. Unknown or conflicting layouts
/// are rejected before encoding rather than discarding or relabeling tracks.
struct MergeAudioPlan: Sendable {
    let tracks: [MediaTrack]
    let channelLayouts: [String]
    var count: Int { tracks.count }

    init(infos: [VideoInfo]) throws {
        guard let reference = infos.max(by: { $0.audioTracks.count < $1.audioTracks.count }) else { throw MergePlanningError.audioLayout }
        tracks = reference.audioTracks
        guard tracks.count <= 128 else { throw MergePlanningError.audioLayout }
        var layouts: [String] = []
        for info in infos {
            guard info.audioTrackCount == 0 || (info.audioTrackCount == tracks.count && info.audioTracks.count == tracks.count) else { throw MergePlanningError.audioLayout }
            if !tracks.isEmpty && info.audioTrackCount == 0 {
                guard let duration = info.duration, duration.isFinite, duration > 0 else { throw MergePlanningError.unknownDuration }
            }
        }
        for slot in tracks.indices {
            let candidates = infos.compactMap { $0.audioTracks.indices.contains(slot) ? $0.audioTracks[slot] : nil }
            let languages = Set(candidates.compactMap { track -> String? in
                guard let language = track.language?.lowercased(), !language.isEmpty, language != "und" else { return nil }
                return language
            })
            guard languages.count <= 1 else { throw MergePlanningError.audioLayout }
            let widest = candidates.max { ($0.channels ?? 2) < ($1.channels ?? 2) } ?? tracks[slot]
            let channels = widest.channels ?? 2
            if channels == 1 { layouts.append("mono") }
            else if channels == 2 { layouts.append("stereo") }
            else if (3...8).contains(channels), let layout = widest.channelLayout,
                    !layout.isEmpty, layout.allSatisfy({ "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._()+-".contains($0) }) {
                layouts.append(layout)
            } else { throw MergePlanningError.audioLayout }
        }
        channelLayouts = layouts
    }

    var metadataArguments: [String] {
        tracks.enumerated().flatMap { slot, track in
            var args = ["-disposition:a:\(slot)", track.isDefault || count == 1 ? "default" : "0"]
            if let language = track.language { args += ["-metadata:s:a:\(slot)", "language=\(language)"] }
            return args
        }
    }
}

enum MergePlanningError: Error, LocalizedError {
    case audioLayout, unknownDuration, hdr, geometry, invalidMedia
    var errorDescription: String? {
        switch self {
        case .audioLayout: L10n.text("合并音轨不一致，请先统一音轨数量和顺序。")
        case .unknownDuration: L10n.text("片段时长不可用，暂不能补齐静音。")
        case .hdr: L10n.text("HDR 片段暂不支持兼容合并，请先转换为 SDR。")
        case .geometry: L10n.text("合并画面尺寸过大，请先降低分辨率。")
        case .invalidMedia: L10n.text("兼容合并失败：存在无法读取的视频流。")
        }
    }
}
