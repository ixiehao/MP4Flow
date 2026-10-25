import Foundation

/// Pixel bounds shared by the crop fields, presets and drag guide. Coordinates
/// may be zero; the two-pixel minimum applies only to width and height.
enum CropGeometry {
    static func normalized(_ rect: CropRect, sourceWidth: Int, sourceHeight: Int) -> CropRect? {
        guard sourceWidth >= 2, sourceHeight >= 2 else { return nil }
        let canvasWidth = evenDown(sourceWidth)
        let canvasHeight = evenDown(sourceHeight)
        let x = min(evenDown(rect.x), canvasWidth - 2)
        let y = min(evenDown(rect.y), canvasHeight - 2)
        return CropRect(
            x: x,
            y: y,
            width: min(max(2, evenDown(rect.width)), canvasWidth - x),
            height: min(max(2, evenDown(rect.height)), canvasHeight - y)
        )
    }

    static func centered(ratio: Double, sourceWidth: Int, sourceHeight: Int) -> CropRect? {
        guard sourceWidth >= 2, sourceHeight >= 2, ratio.isFinite, ratio > 0 else { return nil }
        let sourceRatio = Double(sourceWidth) / Double(sourceHeight)
        let width: Int
        let height: Int
        if sourceRatio > ratio {
            height = evenDown(sourceHeight)
            width = max(2, evenDown(Int((Double(height) * ratio).rounded(.down))))
        } else {
            width = evenDown(sourceWidth)
            height = max(2, evenDown(Int((Double(width) / ratio).rounded(.down))))
        }
        return normalized(
            CropRect(x: evenDown((sourceWidth - width) / 2), y: evenDown((sourceHeight - height) / 2), width: width, height: height),
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
    }

    private static func evenDown(_ value: Int) -> Int { max(0, value) / 2 * 2 }
}
