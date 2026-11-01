import Foundation

/// One parser and one bounded subprocess policy for editors, export and verification.
enum MediaInspector {
    /// Keep process I/O independent of the store so media inspection can be
    /// exercised with a stream-rich ffprobe response in integration tests.
    nonisolated static func inspect(at source: URL, using probe: URL, runner suppliedRunner: FFmpegProcessRunner? = nil) async -> VideoInfo {
        let runner = suppliedRunner ?? FFmpegProcessRunner(
            executable: probe,
            arguments: arguments(for: source),
            configuration: FFmpegProcessRunner.Configuration(inactivityTimeout: 30)
        )
        let result = await runner.run()
        return result.succeeded
            ? (decode(result.standardOutput) ?? unavailable())
            : unavailable()
    }

    static func arguments(for source: URL) -> [String] {
        ["-v", "error", "-show_entries", "stream=index,id,codec_type,codec_name,bit_rate,width,height,r_frame_rate,avg_frame_rate,time_base,pix_fmt,sample_rate,channels,channel_layout,color_transfer,color_space,color_primaries,color_range,sample_aspect_ratio:stream_disposition=attached_pic,timed_thumbnails,default:stream_side_data=rotation:stream_tags=rotate,language,title:chapter=id:format=duration,bit_rate,format_name,size", "-of", "json", source.path]
    }

    static func unavailable() -> VideoInfo {
        VideoInfo(duration: nil, videoRate: nil, audioRate: nil, width: nil, height: nil, hasVideo: false, videoCodec: nil, audioCodec: nil, frameRate: nil, pixelFormat: nil, audioSampleRate: nil, audioChannels: nil, audioTrackCount: 0, subtitleTrackCount: 0, colorTransfer: nil, probeSucceeded: false)
    }

    nonisolated private static func decode(_ data: Data) -> VideoInfo? {
        guard let response = try? JSONDecoder().decode(ProbeResponse.self, from: data) else { return nil }
        let videoStreams = response.streams.filter(\.isMovieVideo)
        let video = videoStreams.first
        let audioStreams = response.streams.filter { $0.codecType == "audio" }
        let subtitleStreams = response.streams.filter { $0.codecType == "subtitle" }
        let audio = audioStreams.first
        let videoRate = Int(video?.bitRate ?? "") ?? response.format.flatMap { format -> Int? in
            guard videoStreams.count == 1, let total = Double(format.bitRate ?? ""), total.isFinite, total > 0 else { return nil }
            let audioTotal = audioStreams.compactMap { Double($0.bitRate ?? "") }.filter { $0.isFinite && $0 > 0 }.reduce(0, +)
            let estimate = max(total - audioTotal, 1)
            guard estimate.isFinite, estimate < Double(Int.max) else { return nil }
            return Int(estimate)
        }
        var info = VideoInfo(duration: Double(response.format?.duration ?? ""), videoRate: videoRate, audioRate: Int(audio?.bitRate ?? ""), width: video?.width, height: video?.height, hasVideo: video != nil, videoCodec: video?.codecName, audioCodec: audio?.codecName, frameRate: video?.rFrameRate, pixelFormat: video?.pixelFormat, audioSampleRate: audio?.sampleRate, audioChannels: audio?.channels, audioTrackCount: audioStreams.count, subtitleTrackCount: subtitleStreams.count, colorTransfer: video?.colorTransfer, probeSucceeded: true)
        info.fileSize = response.format?.size.flatMap(Int64.init).flatMap { $0 >= 0 ? $0 : nil }
        info.colorSpace = video?.colorSpace
        info.colorPrimaries = video?.colorPrimaries
        info.colorRange = video?.colorRange
        info.averageFrameRate = video?.avgFrameRate
        let rotationTag = video?.tags?["rotate"]
        let rotation = video?.sideDataList?.compactMap(\.rotation).first ?? rotationTag.flatMap(Double.init)
        if rotationTag == nil || rotation != nil {
            info.displayGeometry = VideoGeometry.displayed(width: video?.width, height: video?.height, sampleAspectRatio: video?.sampleAspectRatio, rotation: rotation)
        }
        info.timeBase = video?.timeBase
        info.sampleAspectRatio = video?.sampleAspectRatio
        info.displayRotation = rotation
        info.videoTrackCount = videoStreams.count
        info.selectedVideoStreamIndex = video?.index.flatMap { $0 >= 0 ? $0 : nil }
        info.selectedVideoTrackID = response.format?.usesNativeTrackIDs == true ? video?.nativeTrackID : nil
        info.streamLayout = response.streams.map {
            MediaStreamLayout(index: $0.index, type: $0.codecType, codec: $0.codecName, isAuxiliaryImage: $0.disposition?.isAuxiliaryImage == true)
        }
        func tracks(_ streams: [ProbeStream]) -> [MediaTrack] {
            streams.enumerated().compactMap { ordinal, stream in
                guard let index = stream.index, index >= 0 else { return nil }
                return MediaTrack(index: index, ordinal: ordinal, codec: stream.codecName ?? "", language: stream.tags?["language"], title: stream.tags?["title"], bitRate: stream.bitRate.flatMap(Int.init), sampleRate: stream.sampleRate, channels: stream.channels, channelLayout: stream.channelLayout, timeBase: stream.timeBase, isDefault: stream.disposition?.defaultTrack == 1)
            }
        }
        info.audioTracks = tracks(audioStreams)
        info.subtitleTracks = tracks(subtitleStreams)
        info.chapterCount = response.chapters?.count ?? 0
        return info
    }

}

private struct ProbeResponse: Decodable, Sendable { let streams: [ProbeStream]; let format: ProbeFormat?; let chapters: [ProbeChapter]? }
private struct ProbeChapter: Decodable, Sendable {}
private struct ProbeStream: Decodable, Sendable {
    let index: Int?, id: String?, disposition: MediaStreamDisposition?
    let codecType: String?, codecName: String?, bitRate: String?, width: Int?, height: Int?
    let rFrameRate: String?, avgFrameRate: String?, pixelFormat: String?, sampleRate: String?, channels: Int?, channelLayout: String?, colorTransfer: String?
    let colorSpace: String?, colorPrimaries: String?, colorRange: String?
    let sampleAspectRatio: String?, timeBase: String?, sideDataList: [ProbeSideData]?, tags: [String: String]?
    enum CodingKeys: String, CodingKey {
        case index, id, disposition
        case codecType = "codec_type", codecName = "codec_name", bitRate = "bit_rate"
        case rFrameRate = "r_frame_rate", pixelFormat = "pix_fmt", sampleRate = "sample_rate", channels, width, height
        case avgFrameRate = "avg_frame_rate", channelLayout = "channel_layout"
        case colorTransfer = "color_transfer", colorSpace = "color_space", colorPrimaries = "color_primaries", colorRange = "color_range"
        case sampleAspectRatio = "sample_aspect_ratio", timeBase = "time_base", sideDataList = "side_data_list", tags
    }

    var isMovieVideo: Bool { codecType == "video" && disposition?.isAuxiliaryImage != true }

    var nativeTrackID: Int32? {
        guard let id else { return nil }
        let value = id.lowercased()
        let parsed = value.hasPrefix("0x") ? UInt32(value.dropFirst(2), radix: 16) : UInt32(value)
        return parsed.flatMap { $0 != 0 ? Int32(bitPattern: $0) : nil }
    }
}
private struct ProbeSideData: Decodable, Sendable { let rotation: Double? }
private struct ProbeFormat: Decodable, Sendable {
    let duration: String?, bitRate: String?, name: String?, size: String?
    enum CodingKeys: String, CodingKey { case duration, bitRate = "bit_rate", name = "format_name", size }

    // MPEG-TS IDs are PIDs, not AVFoundation persistent track IDs. Only the
    // MOV/MP4 family guarantees that these identifiers refer to the same track.
    var usesNativeTrackIDs: Bool { name?.split(separator: ",").contains("mov") == true }
}

/// Only retry a full transcode when FFmpeg clearly identifies a VideoToolbox
/// component that can be replaced. Generic decode, mux, timeout, and I/O errors
/// are deliberately not retried: replaying a long file would waste time and
/// would not address the underlying failure.
