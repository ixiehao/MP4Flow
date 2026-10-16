import AppKit
import Foundation

enum SocialPreviewError: Error {
    case invalidArguments
    case unreadableImage(String)
    case unableToCreateBitmap
    case unableToWrite(String)
}

private let canvas = NSSize(width: 1280, height: 640)

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

private func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

private func fill(_ rect: NSRect, with fillColor: NSColor, radius: CGFloat = 0) {
    let path = radius > 0 ? roundedRect(rect, radius: radius) : NSBezierPath(rect: rect)
    fillColor.setFill()
    path.fill()
}

private func stroke(_ rect: NSRect, with strokeColor: NSColor, width: CGFloat = 1, radius: CGFloat = 0) {
    let path = radius > 0 ? roundedRect(rect, radius: radius) : NSBezierPath(rect: rect)
    strokeColor.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color textColor: NSColor,
    tracking: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    NSAttributedString(
        string: text,
        attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: textColor,
            .kern: tracking,
            .paragraphStyle: paragraph
        ]
    ).draw(in: rect)
}

private func drawImageAspectFit(_ image: NSImage, in rect: NSRect) {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return }
    let scale = min(rect.width / size.width, rect.height / size.height)
    let rendered = NSSize(width: size.width * scale, height: size.height * scale)
    image.draw(
        in: NSRect(
            x: rect.midX - rendered.width / 2,
            y: rect.midY - rendered.height / 2,
            width: rendered.width,
            height: rendered.height
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func drawImageAspectFill(_ image: NSImage, in rect: NSRect) {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return }
    let scale = max(rect.width / size.width, rect.height / size.height)
    let rendered = NSSize(width: size.width * scale, height: size.height * scale)
    image.draw(
        in: NSRect(
            x: rect.midX - rendered.width / 2,
            y: rect.midY - rendered.height / 2,
            width: rendered.width,
            height: rendered.height
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func render(icon: NSImage, workspace: NSImage) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw SocialPreviewError.unableToCreateBitmap
    }
    bitmap.size = canvas
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw SocialPreviewError.unableToCreateBitmap
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSGradient(
        colors: [color(0.025, 0.075, 0.18), color(0.045, 0.18, 0.46)]
    )!.draw(in: NSRect(origin: .zero, size: canvas), angle: -24)
    NSGradient(colors: [color(0.15, 0.45, 0.98, 0.30), .clear])!.draw(
        fromCenter: NSPoint(x: 985, y: 400),
        radius: 0,
        toCenter: NSPoint(x: 985, y: 400),
        radius: 580,
        options: [.drawsAfterEndingLocation]
    )

    fill(NSRect(x: 55, y: 54, width: 1170, height: 532), with: color(0.02, 0.06, 0.15, 0.46), radius: 30)
    stroke(NSRect(x: 55, y: 54, width: 1170, height: 532), with: color(0.53, 0.74, 1, 0.25), width: 1, radius: 30)

    let iconRect = NSRect(x: 91, y: 486, width: 58, height: 58)
    fill(iconRect, with: color(0.13, 0.32, 0.72, 0.35), radius: 15)
    drawImageAspectFit(icon, in: iconRect.insetBy(dx: 3, dy: 3))
    drawText("MP4", in: NSRect(x: 166, y: 507, width: 112, height: 34), size: 32, weight: .bold, color: color(0.96, 0.98, 1))
    drawText("Flow", in: NSRect(x: 236, y: 507, width: 108, height: 34), size: 32, weight: .bold, color: color(0.42, 0.67, 1))

    let badge = NSRect(x: 91, y: 442, width: 132, height: 25)
    fill(badge, with: color(0.18, 0.40, 0.82, 0.70), radius: 12.5)
    let badgeText = NSMutableParagraphStyle()
    badgeText.alignment = .center
    NSAttributedString(
        string: "NATIVE macOS",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: color(0.90, 0.95, 1),
            .kern: 0.8,
            .paragraphStyle: badgeText
        ]
    ).draw(in: NSRect(x: 91, y: 448, width: 132, height: 14))

    drawText("Video to MP4.", in: NSRect(x: 91, y: 356, width: 390, height: 54), size: 44, weight: .bold, color: .white)
    drawText("Seriously simple.", in: NSRect(x: 91, y: 305, width: 420, height: 54), size: 44, weight: .bold, color: color(0.62, 0.77, 1))
    drawText("Free · Open source · Processed locally", in: NSRect(x: 91, y: 263, width: 410, height: 25), size: 17, weight: .semibold, color: color(0.79, 0.87, 1))

    fill(NSRect(x: 91, y: 219, width: 7, height: 7), with: color(0.36, 0.85, 0.72), radius: 3.5)
    drawText("No uploads. No accounts.", in: NSRect(x: 112, y: 211, width: 340, height: 22), size: 15, weight: .medium, color: color(0.83, 0.90, 1))
    fill(NSRect(x: 91, y: 181, width: 7, height: 7), with: color(0.36, 0.85, 0.72), radius: 3.5)
    drawText("Convert · Trim · Crop · Rotate", in: NSRect(x: 112, y: 173, width: 340, height: 22), size: 15, weight: .medium, color: color(0.83, 0.90, 1))

    let previewRect = NSRect(x: 518, y: 99, width: 659, height: 439)
    context.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, 0.33)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    fill(previewRect, with: color(0.96, 0.98, 1), radius: 20)
    context.restoreGraphicsState()

    context.saveGraphicsState()
    roundedRect(previewRect.insetBy(dx: 5, dy: 5), radius: 16).addClip()
    drawImageAspectFill(workspace, in: previewRect.insetBy(dx: 5, dy: 5))
    context.restoreGraphicsState()
    stroke(previewRect, with: color(0.66, 0.80, 1, 0.56), width: 1.5, radius: 20)

    drawText("MP4Flow · ixiehao.github.io/MP4Flow", in: NSRect(x: 91, y: 93, width: 374, height: 18), size: 13, weight: .medium, color: color(0.53, 0.68, 0.91))

    NSGraphicsContext.restoreGraphicsState()
    guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
        throw SocialPreviewError.unableToWrite("social preview")
    }
    return jpeg
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: create-social-preview.swift <app-icon.png> <real-workspace.png> <social-preview.jpg>\\n", stderr)
    throw SocialPreviewError.invalidArguments
}

let iconURL = URL(fileURLWithPath: CommandLine.arguments[1])
let workspaceURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard let icon = NSImage(contentsOf: iconURL) else {
    throw SocialPreviewError.unreadableImage(iconURL.path)
}
guard let workspace = NSImage(contentsOf: workspaceURL) else {
    throw SocialPreviewError.unreadableImage(workspaceURL.path)
}

try render(icon: icon, workspace: workspace).write(to: outputURL, options: .atomic)
