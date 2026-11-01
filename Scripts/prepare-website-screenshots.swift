import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

// Publish actual window captures. Only remove the empty main-window chrome
// (which can contain macOS's screen-sharing indicator), resize and JPEG-encode.
// Never replace UI, film frames, labels, values or progress indicators.
guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: swift prepare-website-screenshots.swift <raw-directory> <asset-directory> <manifest.json>")
}
let raw = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assets = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let manifest = URL(fileURLWithPath: CommandLine.arguments[3])
let languages = ["en", "zh", "fr", "ru", "es", "ja", "ko"]
let kinds = ["queue", "export", "trim", "crop", "aspect", "adjust"]
var shots: [String: [String: [String: Any]]] = [:]
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
for kind in kinds {
    var localized: [String: [String: Any]] = [:]
    for language in languages {
        let input = raw.appendingPathComponent("\(kind)-\(language).jpg")
        let source = CGImageSourceCreateWithURL(input as CFURL, nil)!
        let original = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let cropTop = kind == "queue" ? 60 : 0
        let captured = original.cropping(to: CGRect(x: 0, y: cropTop, width: original.width, height: original.height - cropTop))!
        let scale = min(1, 1600 / Double(captured.width))
        let width = Int((Double(captured.width) * scale).rounded())
        let height = Int((Double(captured.height) * scale).rounded())
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(captured, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { fatalError("JPEG encoding failed: \(input.lastPathComponent)") }
        let output = "mp4flow-v150-\(kind)-\(language).jpg"
        let data = bytes as Data
        try data.write(to: assets.appendingPathComponent(output), options: .atomic)
        localized[language] = ["src": "assets/" + output, "width": width, "height": height,
            "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
    }
    shots[kind] = localized
}
let record: [String: Any] = [
    "appVersion": "1.5.0", "appCommit": "3ba503f071fed188a19a17121c44618c9a5054a4",
    "captureDate": "2026-11-01", "screenshots": shots,
    "film": ["title": "Tears of Steel (2012)", "attribution": "(CC) Blender Foundation | mango.blender.org",
        "source": "https://mango.blender.org/", "license": "CC BY 3.0",
        "licenseURL": "https://creativecommons.org/licenses/by/3.0/"]
]
try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: manifest, options: .atomic)
print("Prepared \(kinds.count * languages.count) real, localized application screenshots")
