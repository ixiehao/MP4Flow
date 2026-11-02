import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

// GitHub Markdown strips custom CSS. Bake a transparent rounded mask into
// lossless WebP derivatives; keep the original capture and its dimensions.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift prepare-readme-screenshots.swift <website-directory> <output-directory>")
}
let website = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL
let sourceManifest = try Data(contentsOf: website.appendingPathComponent("screenshots.json"))
let sourceRecord = try JSONSerialization.jsonObject(with: sourceManifest) as! [String: Any]
let captures = sourceRecord["screenshots"] as! [String: [String: [String: Any]]]
let fileManager = FileManager.default
let sourcePath = website.resolvingSymlinksInPath().path
let outputPath = output.resolvingSymlinksInPath().path
guard outputPath != "/", outputPath != sourcePath,
      !outputPath.hasPrefix(sourcePath + "/"), !sourcePath.hasPrefix(outputPath + "/") else {
    FileHandle.standardError.write(Data("Output must be outside the website source tree\n".utf8))
    exit(1)
}
try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
let scratch = fileManager.temporaryDirectory.appendingPathComponent("mp4flow-readme-" + UUID().uuidString, isDirectory: true)
try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: scratch) }
var screenshots: [String: [String: [String: Any]]] = [:]
func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func encode(_ input: URL, to output: URL, method: Int) throws {
    let encoder = Process()
    encoder.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    encoder.arguments = ["cwebp", "-quiet", "-lossless", "-m", String(method), input.path, "-o", output.path]
    try encoder.run()
    encoder.waitUntilExit()
    guard encoder.terminationStatus == 0 else { fatalError("cwebp failed; install the development tool with brew install webp") }
}
for kind in captures.keys.sorted() {
    var localized: [String: [String: Any]] = [:]
    for language in captures[kind]!.keys.sorted() {
        let capture = captures[kind]![language]!
        let relativeSource = capture["src"] as! String
        guard relativeSource.hasPrefix("assets/"), !relativeSource.contains("..") else { fatalError("Invalid source path") }
        let input = website.appendingPathComponent(relativeSource)
        let sourceData = try Data(contentsOf: input)
        guard hash(sourceData) == capture["sha256"] as? String else {
            fatalError("Capture does not match its provenance: \(relativeSource)")
        }
        // Decode JPEG with libwebp's standard JPEG decoder first. ImageIO's
        // JPEG chroma upsampling differs and can otherwise shift colored edges.
        let decoded = scratch.appendingPathComponent("decoded.webp")
        try encode(input, to: decoded, method: 0)
        guard let source = CGImageSourceCreateWithURL(decoded as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            fatalError("Unable to decode capture: \(relativeSource)")
        }
        let width = image.width, height = image.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let radius = Double(width) * 0.03
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(image, in: bounds)
        let png = scratch.appendingPathComponent("masked.png")
        let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("PNG mask encoding failed") }
        let webp = scratch.appendingPathComponent("masked.webp")
        try encode(png, to: webp, method: 6)
        let name = "mp4flow-v150-\(kind)-\(language).webp"
        let data = try Data(contentsOf: webp)
        try data.write(to: output.appendingPathComponent(name), options: .atomic)
        localized[language] = ["src": name, "width": width, "height": height,
            "cornerRadius": radius, "sha256": hash(data), "source": "website/" + relativeSource,
            "sourceSHA256": hash(sourceData), "pngBytes": try Data(contentsOf: png).count, "bytes": data.count]
    }
    screenshots[kind] = localized
}
let record: [String: Any] = ["appVersion": sourceRecord["appVersion"]!, "format": "lossless WebP",
    "sourceManifest": "website/screenshots.json", "film": sourceRecord["film"]!, "screenshots": screenshots]
try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    .write(to: output.appendingPathComponent("screenshots.json"), options: .atomic)
print("Prepared transparent rounded README screenshots in \(output.path)")
