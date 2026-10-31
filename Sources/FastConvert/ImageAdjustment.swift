import AVFoundation
import CoreImage
import Foundation

/// Small, bounded values shared by preview and export. Neutral settings leave
/// stream-copy and the zero-copy VideoToolbox path completely unchanged.
struct ImageAdjustment: Equatable, Sendable {
    let brightness: Int
    let shadows: Int
    let denoise: Bool

    init(brightness: Int = 0, shadows: Int = 0, denoise: Bool = false) {
        self.brightness = min(100, max(-100, brightness))
        self.shadows = min(100, max(0, shadows))
        self.denoise = denoise
    }

    var isIdentity: Bool { brightness == 0 && shadows == 0 && !denoise }
    private var shadowGain: Double { Double(shadows) * 0.012 }
    var offset: Double { Double(brightness) * 0.002 }

    func adjusted(_ component: Double) -> Double {
        guard component.isFinite else { return 0 }
        let x = min(1, max(0, component))
        // A smooth toe has unit slope at black, unlike x^gamma's unbounded
        // near-black gain. The shoulder also leaves white and its slope intact.
        let lift = shadowGain * x * x * (1 - x) * (1 - x) / (x + 0.08)
        return min(1, max(0, x + lift + offset))
    }

    var ffmpegFilter: String? {
        guard !isIdentity else { return nil }
        let number: (Double) -> String = { String(format: "%.10f", locale: Locale(identifier: "en_US_POSIX"), $0) }
        let x = "(val/maxval)"
        let expression = "clip(\(x)+\(number(shadowGain))*\(x)*\(x)*(1-\(x))*(1-\(x))/(\(x)+0.08)+\(number(offset)),0,1)*maxval"
        // A LUT is generated once, not a per-pixel pow for every frame. Work in
        // 16-bit encoded RGB before the selected encoder's pixel conversion.
        // The encoders currently output 8-bit SDR. Keep this optional small
        // spatial stage 8-bit, then apply the high-precision tone LUT.
        var filters = denoise ? "format=gbrp" : "format=gbrp16le"
        if denoise {
            // 65% original + 35% small Gaussian. Bake the mix into one 3x3
            // convolution rather than carrying two branches/frames. Explicit
            // replicated borders match Core Image's clamped sampling.
            let kernel = "7 14 7 14 236 14 7 14 7"
            let convolution = (0..<3).map { "\($0)m='\(kernel)':\($0)rdiv=0.003125" }.joined(separator: ":")
            filters += ",pad=iw+2:ih+2:1:1,fillborders=left=1:right=1:top=1:bottom=1:mode=smear,convolution=\(convolution),crop=iw-2:ih-2:1:1,format=gbrp16le"
        }
        if brightness != 0 || shadows != 0 {
            filters += ",lutrgb=r='\(expression)':g='\(expression)':b='\(expression)'"
        }
        return filters
    }

    func previewImage(_ source: CIImage) -> CIImage {
        previewImage(source, curveData: makeCurveData())
    }

    private func makeCurveData() -> Data? {
        guard brightness != 0 || shadows != 0 else { return nil }
        // A small shared 1D RGB table, built once per composition rather than
        // once per video frame. Interpolation is tested against the export LUT.
        let values = (0...1024).flatMap { i -> [Float] in
            let value = Float(adjusted(Double(i) / 1024))
            return [value, value, value]
        }
        return values.withUnsafeBytes { Data($0) }
    }

    private func previewImage(_ source: CIImage, curveData: Data?) -> CIImage {
        guard !isIdentity else { return source }
        var result = source
        if denoise {
            let weights: [CGFloat] = [7,14,7,14,236,14,7,14,7].map { $0 / 320 }
            result = source.clampedToExtent().applyingFilter("CIConvolution3X3", parameters: [
                "inputWeights": CIVector(values: weights, count: weights.count), "inputBias": 0
            ]).cropped(to: source.extent)
        }
        if let curveData {
            result = result.applyingFilter("CIColorCurves", parameters: [
                "inputCurvesData": curveData, "inputCurvesDomain": CIVector(x: 0, y: 1),
                "inputColorSpace": Self.encodedColorSpace
            ])
        }
        return result.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ]).cropped(to: source.extent)
    }

    // Disable an implicit linear-light conversion: the FFmpeg LUT and these
    // filters operate on the same encoded SDR RGB values. No frame cache or
    // additional media runtime is installed or bundled.
    private static let encodedColorSpace = CGColorSpace(name: CGColorSpace.itur_709)!
    static let previewContext = CIContext(options: [
        .workingColorSpace: encodedColorSpace,
        .outputColorSpace: encodedColorSpace, .cacheIntermediates: false
    ])

    func composition(for asset: AVAsset) -> AVVideoComposition? {
        guard !isIdentity else { return nil }
        let curveData = makeCurveData()
        return AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            request.finish(with: self.previewImage(request.sourceImage, curveData: curveData), context: Self.previewContext)
        })
    }
}

// AVFoundation supplies SDR filtering requests in CoreMedia709. Normalize the
// export into that same space before applying the identical encoded-RGB curve.
// Respect recognized source metadata; defaults cover untagged consumer video.
extension VideoInfo {
    var imageAdjustmentColorNormalization: String {
        let matrices = ["bt709", "fcc", "bt470bg", "smpte170m", "smpte240m", "ycgco", "gbr", "bt2020nc", "bt2020ncl"]
        let primaries = ["bt709", "bt470m", "bt470bg", "smpte170m", "smpte240m", "film", "bt2020", "smpte428", "smpte431", "smpte432", "jedec-p22"]
        let transfers = ["bt709", "bt470m", "gamma22", "bt470bg", "gamma28", "smpte170m", "smpte240m", "linear", "srgb", "iec61966-2-1", "iec61966-2-4", "bt2020-10", "bt2020-12"]
        let matrix = colorSpace.flatMap { matrices.contains($0) ? $0 : nil } ?? ((height ?? 1080) <= 576 ? "smpte170m" : "bt709")
        let primary = colorPrimaries.flatMap { primaries.contains($0) ? $0 : nil } ?? "bt709"
        let transfer = colorTransfer.flatMap { transfers.contains($0) ? $0 : nil } ?? "bt709"
        let range = ["pc", "jpeg"].contains(colorRange ?? "") || matrix == "gbr" ? "pc" : "tv"
        return "colorspace=all=bt709:format=yuv444p12:range=tv:ispace=\(matrix):iprimaries=\(primary):itrc=\(transfer):irange=\(range)"
    }
}
