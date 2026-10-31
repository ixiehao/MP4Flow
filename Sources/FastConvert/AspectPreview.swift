import AVFoundation
import SwiftUI

/// Live geometry only: reuse the player and its timeline; no preview encodes,
/// image caches, or per-keystroke media probes.
struct AspectCorrectionPreview: View {
    let player: AVPlayer?
    let sourceWidth: Int
    let sourceHeight: Int
    let crop: CropRect
    let pixelRatio: Double
    let rotation: VideoRotation?
    let correction: DisplayAspectRatio?

    var body: some View {
        GeometryReader { proxy in
            let ratio = correction?.value ?? AspectGeometry.displayRatio(width: crop.width, height: crop.height, pixelRatio: pixelRatio, rotation: rotation)
            let fitted = AspectPreviewLayout.fitted(ratio: ratio, in: proxy.size)
            let turns = rotation?.swapsDimensions == true
            let before = turns ? CGSize(width: fitted.height, height: fitted.width) : fitted.size
            let sx = before.width / CGFloat(crop.width)
            let sy = before.height / CGFloat(crop.height)
            NativeVideoPreview(player: player, stretches: true)
                .frame(width: CGFloat(sourceWidth) * sx, height: CGFloat(sourceHeight) * sy)
                .offset(x: -CGFloat(crop.x) * sx, y: -CGFloat(crop.y) * sy)
                .frame(width: before.width, height: before.height, alignment: .topLeading)
                .clipped()
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
        }
        .clipped()
        .accessibilityLabel(L10n.text("比例预览"))
    }

    private var rotationDegrees: Double {
        switch rotation {
        case .clockwise: 90
        case .counterclockwise: -90
        case .upsideDown: 180
        case nil: 0
        }
    }
}
enum AspectPreviewLayout {
    static func fitted(ratio: Double, in size: CGSize) -> CGRect {
        guard ratio.isFinite, ratio > 0, size.width > 0, size.height > 0 else { return .zero }
        let width = min(size.width, size.height * ratio)
        let height = width / ratio
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}
