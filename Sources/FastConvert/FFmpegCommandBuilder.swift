import Foundation

/// Pure command construction. No UI state, process ownership or fallback side effects.
enum FFmpegCommandBuilder {
    static func arguments(source: URL, output: URL, info: VideoInfo, preset: ConversionPreset, quality: ConversionQuality, resolution: OutputResolution, trim: ClipRange?, rotation: VideoRotation?, crop: CropRect?, aspectRatio: DisplayAspectRatio?, imageAdjustment: ImageAdjustment, copyVideoAndEncodeAudio: Bool, preferHardwarePipeline: Bool, preferHardwareEncoder: Bool, exportPlan: ExportPlan) -> [String] {
        let preset = exportPlan.encodingPreset(for: preset)
        let exportOptions = exportPlan.options
        // Privacy-first default: never copy source metadata or chapters, which
        // may contain title, author, device, location, or editing information.
        var args = ["-hide_banner", "-nostdin", "-y", "-thread_queue_size", "1024"]
        let hardwarePipeline = preferHardwarePipeline && exportOptions.subtitles != .burn && canUseVideoToolboxPipeline(info: info, preset: preset, crop: crop, imageAdjustment: imageAdjustment)
        // For H.264/HEVC without CPU-only edits, keep decoded frames inside
        // VideoToolbox all the way to the encoder. This also benefits an
        // original-size conversion: not just resizes.
        if hardwarePipeline {
            args += ["-init_hw_device", "videotoolbox=vt", "-filter_hw_device", "vt", "-hwaccel", "videotoolbox", "-hwaccel_output_format", "videotoolbox_vld"]
            if info.hardwareDisplayRotation != nil {
                // Hardware decoding does not reliably apply display matrices.
                // Clear the input matrix and apply its known transform below;
                // otherwise pixels can stay sideways or the matrix applies twice.
                args += ["-display_rotation:v", "0"]
            }
        }
        // Input seeking decodes only from the preceding keyframe, including
        // accurate discarding during re-encoding. Output seeking would decode
        // the entire prefix of a long video before producing the first frame.
        // Stream-copy cuts still begin near a keyframe, as the editor explains.
        if let trim {
            args += ["-ss", FFmpegNumber.time(trim.start), "-i", source.path]
        } else {
            args += ["-i", source.path]
        }
        args += ["-map", "0:\(info.videoStreamSpecifier)"] + exportOptions.audioMaps
        if exportOptions.subtitles == .keep, let track = exportOptions.chosenSubtitle(in: info) { args += ["-map", "0:\(track.index)"] }
        args += ["-map_metadata", "-1", "-map_chapters", "-1"]
        let targetPlan = exportPlan.targetSize
        if let trim {
            args += ["-t", FFmpegNumber.time(trim.end - trim.start)]
        }
        if copyVideoAndEncodeAudio {
            args += ["-c:v", "copy"]
            if info.videoCodec?.lowercased() == "hevc" { args += ["-tag:v", "hvc1"] }
            return args + exportPlan.outputArguments + ["-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
        }
        // Crop coordinates are chosen in the source orientation; rotate before
        // resizing so a selected output height always applies to the final
        // orientation. `transpose_vt` leaves a non-square input SAR unchanged,
        // unlike the CPU transpose filter, so invert it after a 90° turn.
        let editedGeometry = info.geometry(crop: crop, rotation: rotation)
        let rotatedSourceHeight = editedGeometry?.height
        var filters = [crop?.filter].compactMap { $0 }
        if hardwarePipeline, let displayRotation = info.hardwareDisplayRotation {
            filters.append(displayRotation.videoToolboxFilter)
            if displayRotation.swapsDimensions { filters.append("setsar=1/sar") }
        }
        if preset != .remux, let trim, trim.start > 0, let firstFrameFilter = info.trimmedFirstFrameFilter {
            filters.append(firstFrameFilter)
        }
        if let rotation {
            filters.append(hardwarePipeline ? rotation.videoToolboxFilter : rotation.filter)
            if hardwarePipeline && rotation.swapsDimensions {
                filters.append("setsar=1/sar")
            }
        }
        if let aspectRatio, let size = aspectRatio.outputSize(height: resolution.targetHeight ?? rotatedSourceHeight ?? 0) {
            // A correction intentionally reshapes the complete edited frame.
            // Export square pixels so players agree on the corrected geometry.
            filters.append(hardwarePipeline
                ? "scale_vt=w=\(size.width):h=\(size.height)"
                : "scale=\(size.width):\(size.height):flags=bicubic")
            filters.append("setsar=1")
        } else if let resolutionFilter = resolution.filter(sourceHeight: rotatedSourceHeight, quality: quality, useVideoToolbox: hardwarePipeline, canSkipUnchangedSize: editedGeometry?.canSkipUnchangedSize == true) {
            filters.append(resolutionFilter)
        }
        if let adjustmentFilter = imageAdjustment.ffmpegFilter {
            filters.append(info.imageAdjustmentColorNormalization)
            filters.append(adjustmentFilter)
        }
        filters += exportOptions.burnFilter(source: source, info: info, trim: trim)
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
        if preset != .remux, let timeBase = info.encodingTimeBase {
            args += ["-enc_time_base:v", timeBase]
        }
        let videoRate = targetPlan?.videoRate ?? info.outputRate(preset: preset, quality: quality, resolution: resolution, sourceHeight: rotatedSourceHeight)
        switch preset {
        case .qualityTop:
            args += preferHardwareEncoder
                ? hardware(codec: "h264_videotoolbox", videoRate: videoRate, keepsVideoToolboxFrames: hardwarePipeline)
                : softwareBitrate(videoRate: videoRate)
        case .h264Cap8:
            args += preferHardwareEncoder
                ? hardware(codec: "h264_videotoolbox", videoRate: videoRate, keepsVideoToolboxFrames: hardwarePipeline)
                : softwareBitrate(videoRate: videoRate)
        case .smartMP4, .smartEnhanceUpscale: preconditionFailure("智能预设必须在探测后解析为具体编码路径")
        case .h264Hardware:
            args += preferHardwareEncoder
                ? hardware(codec: "h264_videotoolbox", videoRate: videoRate, keepsVideoToolboxFrames: hardwarePipeline)
                : softwareBitrate(videoRate: videoRate)
        case .hevcHardware:
            args += preferHardwareEncoder
                ? hardware(codec: "hevc_videotoolbox", videoRate: videoRate, keepsVideoToolboxFrames: hardwarePipeline) + ["-tag:v", "hvc1"]
                : softwareBitrate(videoRate: videoRate)
        case .h264Software:
            if let targetPlan {
                // ABR allocates this approximate budget across the complete
                // file. A live-stream VBV ceiling starves complex scenes and
                // is unnecessary for a local file-size goal.
                args += ["-c:v", "libx264", "-preset", quality.targetCompressionPreset, "-b:v", rate(targetPlan.videoRate), "-pix_fmt", "yuv420p"]
            } else {
                args += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "\(quality.crf)", "-pix_fmt", "yuv420p"]
            }
        case .remux: args += ["-c:v", "copy"]
        }
        if !imageAdjustment.isIdentity, preset != .remux {
            // Match the chosen working transfer in both encoder and container;
            // inherited tags must not reinterpret the normalized RGB values.
            args += ["-color_primaries", "bt709", "-color_trc", info.imageAdjustmentWorkingSpace.rawValue, "-colorspace", "bt709", "-color_range", "tv"]
        }
        return args + exportPlan.outputArguments + ["-movflags", "+faststart", "-progress", "pipe:1", "-nostats", output.path]
    }

    static func usesVideoToolboxEncoder(_ preset: ConversionPreset) -> Bool {
        preset == .qualityTop || preset == .h264Cap8 || preset == .h264Hardware || preset == .hevcHardware
    }

    static func canUseVideoToolboxPipeline(info: VideoInfo, preset: ConversionPreset, crop: CropRect?, imageAdjustment: ImageAdjustment) -> Bool {
        usesVideoToolboxEncoder(preset)
            && crop == nil && imageAdjustment.isIdentity
            && (info.displayRotation == nil || info.displayGeometry != nil)
            && ["h264", "hevc"].contains(info.videoCodec?.lowercased() ?? "")
    }

    private static func hardware(codec: String, videoRate: Int, keepsVideoToolboxFrames: Bool = false) -> [String] {
        var args = ["-c:v", codec, "-prio_speed", "1", "-b:v", rate(videoRate), "-maxrate", rate(Int(Double(videoRate) * 1.25)), "-bufsize", rate(videoRate * 2)]
        if !keepsVideoToolboxFrames { args += ["-pix_fmt", "yuv420p"] }
        return args
    }
    private static func softwareBitrate(videoRate: Int) -> [String] {
        ["-c:v", "libx264", "-preset", "veryfast", "-b:v", rate(videoRate), "-maxrate", rate(Int(Double(videoRate) * 1.25)), "-bufsize", rate(videoRate * 2), "-pix_fmt", "yuv420p"]
    }
    private static func rate(_ bits: Int) -> String { "\(max(64, bits / 1_000))k" }
}
