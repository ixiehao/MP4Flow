import Foundation

/// A user-selected display ratio, applied after crop and rotation. Keep this
/// rational separate from localized labels and never pass text to FFmpeg.
struct DisplayAspectRatio: Equatable, Sendable {
    let width: Int
    let height: Int

    init?(width: Int, height: Int) {
        guard width > 0, height > 0, width <= 1_000_000_000_000, height <= 1_000_000_000_000,
              (0.1...10).contains(Double(width) / Double(height)) else { return nil }
        let divisor = Self.gcd(width, height)
        self.width = width / divisor
        self.height = height / divisor
    }

    /// Accept decimal ratios such as 2.39:1, including comma decimal input.
    /// Limits bound arithmetic and reject exponent/FFmpeg expressions.
    init?(widthText: String, heightText: String) {
        guard let w = Self.component(widthText), let h = Self.component(heightText),
              let ratio = DisplayAspectRatio(width: w.value * h.scale, height: h.value * w.scale) else { return nil }
        self = ratio
    }

    var value: Double { Double(width) / Double(height) }
    var summary: String { "\(width):\(height)" }

    func outputSize(height targetHeight: Int) -> (width: Int, height: Int)? {
        guard (2...16_384).contains(targetHeight) else { return nil }
        let height = targetHeight / 2 * 2
        let width = max(2, Int((Double(height) * value / 2).rounded()) * 2)
        guard width <= 16_384, width * height <= 67_108_864 else { return nil }
        return (width, height)
    }

    private static func component(_ text: String) -> (value: Int, scale: Int)? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, normalized.count <= 10,
              normalized.allSatisfy({ "0123456789.".contains($0) }) else { return nil }
        let fields = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count <= 2, let whole = Int(fields[0]), whole <= 100_000_000 else { return nil }
        let fraction = fields.count == 2 ? String(fields[1]) : ""
        guard fraction.count <= 4, fields.count == 1 || !fraction.isEmpty else { return nil }
        let scale = [1, 10, 100, 1000, 10_000][fraction.count]
        let value = whole * scale + (Int(fraction) ?? 0)
        guard value > 0, value <= 100_000_000 else { return nil }
        return (value, scale)
    }

    private static func gcd(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs, b = rhs
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}

enum AspectRatioPreset: String, CaseIterable, Identifiable {
    case original, landscape, standard, portrait, square, custom
    var id: Self { self }
    var ratio: DisplayAspectRatio? {
        switch self {
        case .landscape: DisplayAspectRatio(width: 16, height: 9)
        case .standard: DisplayAspectRatio(width: 4, height: 3)
        case .portrait: DisplayAspectRatio(width: 9, height: 16)
        case .square: DisplayAspectRatio(width: 1, height: 1)
        case .original, .custom: nil
        }
    }
    var title: String {
        switch self {
        case .original: L10n.text("原比例")
        case .custom: L10n.text("自定义")
        default: ratio?.summary ?? ""
        }
    }
}

/// Display geometry shared by preview and conversion. SAR is a pixel shape,
/// not a request to crop; a quarter turn inverts it along with frame geometry.
enum AspectGeometry {
    static func pixelRatio(_ text: String?) -> Double {
        guard let text else { return 1 }
        let fields = text.split(whereSeparator: { $0 == ":" || $0 == "/" })
        guard fields.count == 2, let w = Double(fields[0]), let h = Double(fields[1]),
              w > 0, h > 0, (w / h).isFinite else { return 1 }
        return w / h
    }

    static func displayRatio(width: Int, height: Int, pixelRatio: Double, rotation: VideoRotation?) -> Double {
        let ratio = Double(width) / Double(height) * pixelRatio
        return rotation?.swapsDimensions == true ? 1 / ratio : ratio
    }
}
