import Foundation

struct CompatibleMergeTarget: Sendable {
    let width: Int
    let height: Int
    let frameRate: String

    var summary: String { "\(width) × \(height)" }
}

struct CompatibleMergePlan: Sendable {
    let sources: [URL]
    let infos: [VideoInfo]
    let target: CompatibleMergeTarget
    let audio: MergeAudioPlan

    init(sources: [URL], infos: [VideoInfo]) throws {
        guard sources.count >= 2, sources.count == infos.count, infos.allSatisfy({ $0.probeSucceeded && $0.hasVideo }),
              let target = MergeCommandBuilder.target(infos) else { throw MergePlanningError.invalidMedia }
        if infos.contains(where: \.isHDR) { throw MergePlanningError.hdr }
        guard (2...16384).contains(target.width), (2...16384).contains(target.height), Double(target.width) * Double(target.height) <= 67_108_864 else { throw MergePlanningError.geometry }
        self.sources = sources; self.infos = infos; self.target = target
        audio = try MergeAudioPlan(infos: infos)
    }
}

enum MergeCommandBuilder {
    static func losslessArguments(listURL: URL, info: VideoInfo, output: URL) -> [String] {
        ["-hide_banner", "-nostdin", "-y", "-f", "concat", "-safe", "0", "-i", listURL.path,
         "-map", "0:\(info.videoStreamSpecifier)", "-map", "0:a?", "-map_metadata", "-1", "-map_chapters", "-1", "-c:v", "copy"]
        + AudioExportPlan(options: ExportOptions(), info: info, target: nil).arguments
        + ["-sn", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
    }
    /// Normalize to the largest displayed square-pixel frame rather than to the first file in
    /// queue. Smaller clips are scaled up proportionally; differing aspect
    /// ratios are centered on a black canvas, never stretched or cropped.
    static func target(_ infos: [VideoInfo]) -> CompatibleMergeTarget? {
        let displayed = infos.map { info -> (info: VideoInfo, width: Int, height: Int) in
            let width = info.width ?? 1920, height = info.height ?? 1080
            let scaledWidth = Double(width) * info.mergePixelAspectRatio
            let normalizedWidth = scaledWidth.isFinite && scaledWidth >= 2 && scaledWidth < Double(Int.max)
                ? even(Int(scaledWidth)) : even(width)
            let geometry = VideoGeometry.displayed(width: normalizedWidth, height: height, sampleAspectRatio: "1:1", rotation: info.displayRotation)
            return (info, even(geometry?.width ?? normalizedWidth), even(geometry?.height ?? height))
        }
        // Keep tuple comparison simple enough for the older Swift toolchain
        // used by CI; area is calculated in Double to avoid Int overflow.
        guard let largest = displayed.max(by: { left, right in
            let leftArea = Double(left.width) * Double(left.height)
            let rightArea = Double(right.width) * Double(right.height)
            return leftArea < rightArea
        }) else { return nil }
        return CompatibleMergeTarget(
            width: largest.width,
            height: largest.height,
            frameRate: validFrameRate(largest.info.frameRate)
        )
    }

    static func compatibleArguments(plan: CompatibleMergePlan, output: URL, preferHardwareEncoder: Bool) -> [String] {
        let sources = plan.sources, infos = plan.infos, target = plan.target, audio = plan.audio
        var args = ["-hide_banner", "-nostdin", "-y"]
        for source in sources { args += ["-i", source.path] }

        var filters: [String] = []
        for (index, info) in infos.enumerated() {
            // Fit/pad works in encoded pixels. Normalize each autorotated
            // input's pixel aspect ratio first so setsar=1 cannot stretch it.
            // The explicit scale expression also works with older FFmpeg.
            filters.append("[\(index):\(info.videoStreamSpecifier)]scale=w='max(2,trunc(iw*if(gt(sar,0),sar,1)/2)*2)':h=ih,setsar=1,scale=\(target.width):\(target.height):force_original_aspect_ratio=decrease:force_divisible_by=2,pad=\(target.width):\(target.height):(ow-iw)/2:(oh-ih)/2:color=black,fps=\(target.frameRate),setsar=1,format=yuv420p[v\(index)]")
            for slot in 0..<audio.count {
                let layout = audio.channelLayouts[slot]
                if info.audioTrackCount > 0 {
                    filters.append("[\(index):a:\(slot)]aresample=48000:first_pts=0,aformat=channel_layouts=\(layout)[a\(index)_\(slot)]")
                } else {
                    filters.append("anullsrc=r=48000:cl=\(layout),atrim=duration=\(FFmpegNumber.time(info.duration ?? 0)),asetpts=PTS-STARTPTS[a\(index)_\(slot)]")
                }
            }
        }
        let concatInputs = infos.indices.map { index in
            "[v\(index)]" + (0..<audio.count).map { "[a\(index)_\($0)]" }.joined()
        }.joined()
        let audioOutputs = (0..<audio.count).map { "[aout\($0)]" }.joined()
        filters.append("\(concatInputs)concat=n=\(infos.count):v=1:a=\(audio.count)[vout]\(audioOutputs)")
        let videoRate = infos.map(\.fallbackRate).max() ?? 4_000_000
        args += ["-filter_complex", filters.joined(separator: ";"), "-map", "[vout]", "-map_metadata", "-1", "-map_chapters", "-1"]
        for slot in 0..<audio.count { args += ["-map", "[aout\(slot)]"] }
        args += audio.metadataArguments
        if preferHardwareEncoder {
            args += ["-c:v", "h264_videotoolbox", "-prio_speed", "1"]
        } else {
            args += ["-c:v", "libx264", "-preset", "veryfast"]
        }
        args += ["-b:v", rate(videoRate), "-maxrate", rate(Int(Double(videoRate) * 1.25)), "-bufsize", rate(videoRate * 2), "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-sn", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
        return args
    }

    private static func rate(_ bits: Int) -> String { "\(max(64, bits / 1_000))k" }

    private static func even(_ value: Int) -> Int { max(2, value - value % 2) }

    private static func validFrameRate(_ value: String?) -> String {
        guard let value else { return "30" }
        let fields = value.split(separator: "/")
        let rate: Double?
        if fields.count == 2, let n = Double(fields[0]), let d = Double(fields[1]), d > 0 { rate = n / d }
        else { rate = Double(value) }
        guard let rate, rate.isFinite, (0.1...240).contains(rate) else { return "30" }
        return value
    }
}
