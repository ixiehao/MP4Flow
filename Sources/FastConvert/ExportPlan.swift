import Foundation

/// An output track owns its encoder and metadata. One incompatible stream must
/// not force the other AAC tracks through another lossy encode.
struct AudioExportPlan: Sendable {
    let tracks: [MediaTrack]
    let arguments: [String]
    let canCopyAll: Bool

    init(options: ExportOptions, info: VideoInfo, target: TargetSizePlan?, forceAAC: Bool = false) {
        tracks = options.chosenAudio(in: info)
        let mustEncode = target != nil || forceAAC
        canCopyAll = !mustEncode && (options.audio == .none || (tracks.isEmpty ? info.audioCodec == nil || info.audioCodec?.lowercased() == "aac" : tracks.allSatisfy { $0.codec.lowercased() == "aac" }))
        guard options.audio != .none else { arguments = ["-an"]; return }
        var args: [String] = []
        for (offset, track) in tracks.enumerated() {
            let copy = !mustEncode && track.codec.lowercased() == "aac"
            if copy { args += ["-c:a:\(offset)", "copy"] }
            else {
                let rate = target?.audioRatePerTrack ?? (forceAAC ? 192_000 : min(max(track.bitRate ?? info.safeAudioRate, 64_000), 192_000))
                args += ["-c:a:\(offset)", "aac", "-b:a:\(offset)", "\(rate)"]
            }
            if let language = track.language { args += ["-metadata:s:a:\(offset)", "language=\(language)"] }
            args += ["-disposition:a:\(offset)", track.isDefault || tracks.count == 1 ? "default" : "0"]
        }
        // Legacy/test metadata can omit stream descriptors. Real probe results
        // always supply them; retain a safe default rather than emit no codec.
        if tracks.isEmpty {
            args += canCopyAll ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "\(target?.audioRatePerTrack ?? info.safeAudioRate)"]
        }
        arguments = args
    }
}

/// Shared validation for the sheet and worker. The immutable result is reused
/// by every retry instead of interpreting UI choices again during encoding.
struct ExportPlan: Sendable {
    let options: ExportOptions
    let targetSize: TargetSizePlan?
    let audio: AudioExportPlan
    let subtitle: MediaTrack?

    init(options: ExportOptions, info: VideoInfo, trim: ClipRange?, preset: ConversionPreset, canBurnSubtitles: Bool) throws {
        self.options = options.normalized
        targetSize = try options.validate(info: info, trim: trim)
        if preset == .smartEnhanceUpscale && !options.supportsNativeEnhancement(info: info) { throw ExportOptionError.incompatibleEnhancement }
        if info.isHDR && (options.targetSizeMB != nil || options.subtitles == .burn) { throw ExportOptionError.hdrEdits }
        if options.subtitles == .burn && !canBurnSubtitles { throw ExportOptionError.missingRenderer }
        audio = AudioExportPlan(options: options, info: info, target: targetSize, forceAAC: preset == .h264Cap8)
        subtitle = options.chosenSubtitle(in: info)
    }

    var expectedSubtitleCount: Int { options.subtitles == .keep ? 1 : 0 }

    /// File-size budgets need efficient offline compression, rather than a
    /// real-time encoder tuned for throughput. Keep an explicit HEVC choice;
    /// every H.264 size-budget route shares the same quality-aware encoder.
    func encodingPreset(for preset: ConversionPreset) -> ConversionPreset {
        guard targetSize != nil, preset != .hevcHardware, preset != .smartEnhanceUpscale else { return preset }
        return .h264Software
    }
    var outputArguments: [String] {
        var args = audio.arguments
        if options.subtitles == .keep, let subtitle {
            args += ["-c:s", "mov_text", "-disposition:s:0", "0"]
            if let language = subtitle.language { args += ["-metadata:s:s:0", "language=\(language)"] }
        } else { args += ["-sn"] }
        return args
    }
}

enum FFmpegNumber {
    static func time(_ seconds: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), seconds)
    }
}
