import Foundation

struct EditorMediaInfo: Sendable {
    let duration: Double
    let width: Int
    let height: Int
    let frameRate: Double
    var pixelRatio: Double = 1
    var isHDR: Bool = false
    var colorTransfer: String? = nil

    var frameDuration: Double { 1 / frameRate }

    init?(info: VideoInfo) {
        // Editor timecodes use milliseconds and frame-step indices. Reject
        // corrupt, unrepresentable durations before converting them to Int.
        guard info.probeSucceeded, info.hasVideo,
              let duration = info.duration, duration.isFinite, duration > 0,
              duration < Double(Int.max) / 1_000,
              let geometry = info.displayGeometry else { return nil }
        self.duration = duration
        width = geometry.width
        height = geometry.height
        let sar = AspectGeometry.pixelRatio(info.sampleAspectRatio)
        let swapped = abs(((info.displayRotation ?? 0) / 90).rounded().truncatingRemainder(dividingBy: 2)) == 1
        pixelRatio = swapped ? 1 / sar : sar
        isHDR = info.isHDR
        colorTransfer = info.colorTransfer
        // VFR's nominal value may describe a 90 kHz clock, not the cadence.
        frameRate = [info.averageFrameRate, info.frameRate].compactMap(Self.parseFrameRate).first ?? 30
    }

    private static func parseFrameRate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        let rate: Double?
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
            rate = numerator / denominator
        } else {
            rate = Double(value)
        }
        guard let rate, rate.isFinite, (1...240).contains(rate) else { return nil }
        return rate
    }
}

/// Editors and conversion share both executable selection and typed media
/// facts. Only the deadline differs: a dismissed editor owns a short,
/// cancellable inspection, never a detached AVFoundation metadata wait.
enum EditorMediaProbe {
    static func inspect(
        source: URL,
        using probeOverride: URL? = nil,
        toolDirectories: [URL] = DependencyToolResolver.defaultDirectories
    ) async -> EditorMediaInfo? {
        guard let binary = probeOverride ?? DependencyToolResolver.resolve(in: toolDirectories).ffprobe else { return nil }
        let runner = FFmpegProcessRunner(
            executable: binary,
            arguments: MediaInspector.arguments(for: source),
            configuration: FFmpegProcessRunner.Configuration(inactivityTimeout: 5, terminationGrace: 0.5, maximumOutputBytes: 1_000_000)
        )
        let info = await MediaInspector.inspect(at: source, using: binary, runner: runner)
        guard !Task.isCancelled else { return nil }
        return EditorMediaInfo(info: info)
    }
}
