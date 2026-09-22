import AppKit
import Foundation
import ImageIO

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/assets/mp4flow-demo.gif")
guard output.pathExtension.lowercased() == "gif", !output.hasDirectoryPath else {
    fatalError("Output must be a GIF file path.")
}
let width = 1200
let height = 700
let frameCount = 72
let frameDelay = 0.055

enum Palette {
    static let canvas = NSColor(calibratedRed: 0.95, green: 0.97, blue: 1, alpha: 1)
    static let white = NSColor.white
    static let ink = NSColor(calibratedWhite: 0.09, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.39, green: 0.45, blue: 0.57, alpha: 1)
    static let line = NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.95, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.12, green: 0.37, blue: 0.91, alpha: 1)
    static let blueSoft = NSColor(calibratedRed: 0.92, green: 0.95, blue: 1, alpha: 1)
    static let green = NSColor(calibratedRed: 0.07, green: 0.67, blue: 0.38, alpha: 1)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: y, width: w, height: h) }
func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = lineWidth; path.stroke() }
}
func text(_ value: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Palette.ink, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    NSAttributedString(string: value, attributes: attributes).draw(in: rect)
}
func circle(_ center: CGPoint, _ radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(ovalIn: rect(center.x - radius, center.y - radius, radius * 2, radius * 2))
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = 1.5; path.stroke() }
}
func iconFilm(at origin: CGPoint, color: NSColor) {
    let frame = NSBezierPath(roundedRect: rect(origin.x, origin.y, 25, 18), xRadius: 4, yRadius: 4)
    color.setStroke(); frame.lineWidth = 2; frame.stroke()
    NSBezierPath.strokeLine(from: CGPoint(x: origin.x + 7, y: origin.y + 4), to: CGPoint(x: origin.x + 7, y: origin.y + 14))
    NSBezierPath.strokeLine(from: CGPoint(x: origin.x + 18, y: origin.y + 4), to: CGPoint(x: origin.x + 18, y: origin.y + 14))
}
func progress(_ value: CGFloat, in box: NSRect) {
    rounded(box, radius: box.height / 2, fill: Palette.line)
    rounded(rect(box.minX, box.minY, box.width * min(max(value, 0), 1), box.height), radius: box.height / 2, fill: Palette.blue)
}
func stage(for frame: Int) -> Int { min(2, frame / 24) }
func pulse(_ frame: Int) -> CGFloat { 0.55 + 0.45 * sin(CGFloat(frame % 24) / 24 * .pi) }

func drawFrame(_ index: Int) -> CGImage? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    Palette.canvas.setFill(); NSBezierPath.fill(rect(0, 0, CGFloat(width), CGFloat(height)))
    let window = rect(84, 54, 1032, 592)
    rounded(window, radius: 20, fill: Palette.white, stroke: Palette.line)
    Palette.blueSoft.setFill(); NSBezierPath.fill(rect(window.minX, window.maxY - 68, window.width, 68))

    [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated().forEach { offset, color in
        circle(CGPoint(x: window.minX + 26 + CGFloat(offset) * 20, y: window.maxY - 26), 6, fill: color)
    }
    iconFilm(at: CGPoint(x: 174, y: 597), color: Palette.blue)
    text("MP4Flow", in: rect(208, 590, 160, 28), size: 23, weight: .bold)
    text("Video to MP4 · Local · Private", in: rect(208, 570, 230, 20), size: 12, color: Palette.muted)

    let stageIndex = stage(for: index)
    let titles = ["1  Add videos", "2  Trim · Crop · Rotate", "3  Convert locally"]
    let subtitles = [
        "Drop a video. MP4Flow reads it on your Mac.",
        "Choose a range, crop the frame, or rotate the picture.",
        "Fast hardware conversion. Safe batch processing."
    ]
    text(titles[stageIndex], in: rect(486, 593, 410, 26), size: 18, weight: .semibold, color: Palette.blue, alignment: .center)
    text(subtitles[stageIndex], in: rect(390, 570, 600, 18), size: 12, color: Palette.muted, alignment: .center)

    let configuration = rect(112, 462, 976, 80)
    rounded(configuration, radius: 12, fill: Palette.white, stroke: Palette.line)
    let controls: [(String, String)] = [("Mode", "Smart Convert"), ("Size", "Balanced"), ("Resolution", "720p"), ("Output", "Source Folder")]
    for (position, control) in controls.enumerated() {
        let x = configuration.minX + 20 + CGFloat(position) * 238
        text(control.0, in: rect(x, 511, 180, 15), size: 11, weight: .medium, color: Palette.muted)
        rounded(rect(x, 480, 210, 27), radius: 7, fill: Palette.canvas, stroke: Palette.line)
        text(control.1, in: rect(x + 10, 486, 170, 16), size: 12, weight: .medium)
    }

    let queue = rect(112, 154, 976, 286)
    rounded(queue, radius: 12, fill: Palette.white, stroke: Palette.line)
    text("Conversion Queue", in: rect(132, 405, 250, 22), size: 16, weight: .semibold)
    let row = rect(132, 318, 936, 72)
    let rowFill = stageIndex == 2 ? Palette.blueSoft : Palette.white
    rounded(row, radius: 10, fill: rowFill, stroke: Palette.line)
    rounded(rect(148, 333, 42, 42), radius: 9, fill: Palette.blueSoft)
    iconFilm(at: CGPoint(x: 157, y: 345), color: Palette.blue)
    text("travel-video.mkv", in: rect(206, 354, 280, 20), size: 15, weight: .semibold)
    text("1920 × 1080  ·  02:09  ·  1.14 GB", in: rect(206, 334, 300, 16), size: 11, color: Palette.muted)

    if stageIndex == 0 {
        rounded(rect(890, 339, 156, 30), radius: 7, fill: Palette.blue)
        text("+  Add Videos", in: rect(890, 347, 156, 16), size: 12, weight: .semibold, color: .white, alignment: .center)
        let alpha = pulse(index)
        rounded(rect(126, 312, 948, 84), radius: 12, fill: .clear, stroke: Palette.blue.withAlphaComponent(alpha), lineWidth: 2)
        text("Drop videos here", in: rect(132, 252, 936, 22), size: 14, weight: .medium, color: Palette.muted, alignment: .center)
    } else if stageIndex == 1 {
        let actions = [("Trim", 770), ("Crop", 834), ("Rotate", 898)]
        for (label, x) in actions {
            rounded(rect(CGFloat(x), 339, 56, 30), radius: 7, fill: label == "Trim" ? Palette.blue : Palette.canvas, stroke: Palette.line)
            text(label, in: rect(CGFloat(x), 347, 56, 16), size: 11, weight: .medium, color: label == "Trim" ? .white : Palette.ink, alignment: .center)
        }
        let editor = rect(160, 188, 880, 104)
        rounded(editor, radius: 10, fill: Palette.blueSoft, stroke: Palette.line)
        text("Keep range", in: rect(182, 259, 160, 19), size: 13, weight: .semibold)
        progress(0.64, in: rect(182, 236, 670, 7))
        circle(CGPoint(x: 397, y: 239.5), 8, fill: .white, stroke: Palette.blue)
        circle(CGPoint(x: 852, y: 239.5), 8, fill: .white, stroke: Palette.blue)
        text("00:00:15.464", in: rect(870, 231, 145, 17), size: 12, weight: .medium, color: Palette.blue, alignment: .right)
        text("Trim a time range without re-encoding when possible", in: rect(182, 204, 610, 16), size: 11, color: Palette.muted)
    } else {
        let progressValue = min(1, CGFloat(index - 48) / 20)
        text(progressValue >= 1 ? "Completed" : "Converting", in: rect(774, 355, 112, 18), size: 13, weight: .semibold, color: progressValue >= 1 ? Palette.green : Palette.blue)
        progress(progressValue, in: rect(774, 334, 250, 8))
        if progressValue >= 1 {
            circle(CGPoint(x: 1040, y: 358), 11, fill: Palette.green)
            text("✓", in: rect(1033, 352, 14, 16), size: 12, weight: .bold, color: .white, alignment: .center)
        }
        text(progressValue >= 1 ? "Done. Your MP4 is ready beside the original." : "Hardware acceleration keeps compatible conversions fast.", in: rect(132, 232, 936, 20), size: 13, color: Palette.muted, alignment: .center)
    }
    text("Free and open source for macOS", in: rect(112, 88, 976, 20), size: 12, weight: .medium, color: Palette.muted, alignment: .center)

    return representation.cgImage
}

try? FileManager.default.removeItem(at: output)
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "com.compuserve.gif" as CFString, frameCount, nil) else {
    fputs("Could not create GIF destination.\n", stderr)
    exit(1)
}
for frame in 0..<frameCount {
    guard let image = drawFrame(frame) else { continue }
    let properties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
}
let properties: [CFString: Any] = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
]
CGImageDestinationSetProperties(destination, properties as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not write GIF.\n", stderr)
    exit(1)
}
print("Created \(output.path)")
