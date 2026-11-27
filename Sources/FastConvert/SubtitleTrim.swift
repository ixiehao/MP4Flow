import Foundation

/// A private workspace for a single kept text subtitle track.
struct SubtitleTrim: Sendable {
    private let directory: URL
    private var extractedURL: URL { directory.appendingPathComponent("extracted.srt") }
    var clippedURL: URL { directory.appendingPathComponent("clipped.srt") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MP4Flow-subtitles-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    func extractionArguments(source: URL, track: MediaTrack, trim: ClipRange) -> [String] {
        // The default timestamp origin matches input seeking in the main conversion.
        ["-hide_banner", "-nostdin", "-loglevel", "warning", "-n", "-i", source.path,
         "-map", "0:\(track.index)", "-t", FFmpegNumber.time(trim.end), "-c:s", "srt", "-f", "srt",
         "-progress", "pipe:1", "-nostats", extractedURL.path]
    }

    func writeClippedSubtitles(in trim: ClipRange) throws {
        let input = try FileHandle(forReadingFrom: extractedURL)
        defer {
            try? input.close()
            try? FileManager.default.removeItem(at: extractedURL)
        }
        let source = try input.read(upToCount: Self.maximumSubtitleBytes + 1) ?? Data()
        guard source.count <= Self.maximumSubtitleBytes else { throw ClipError.invalidSubtitles }
        let clipped = try Self.clip(source, to: trim)
        try clipped.write(to: clippedURL, options: .atomic)
    }

    // Normalized cue headers written by FFmpeg's SRT muxer. Match headers
    // separately from payloads so a multiline cue does not have to be split.
    private static let cueHeader = try! NSRegularExpression(
        pattern: #"(?m)(?:\A|\n\n)[0-9]+\n(-?[0-9]{2,}:[0-5][0-9]:[0-5][0-9],[0-9]{3})[ \t]+-->[ \t]+(-?[0-9]{2,}:[0-5][0-9]:[0-5][0-9],[0-9]{3})[^\n]*\n"#
    )
    private static let maximumSubtitleBytes = 32 * 1024 * 1024

    static func clip(_ source: Data, to trim: ClipRange) throws -> Data {
        guard trim.isValid,
              let start = Int64(exactly: (trim.start * 1000).rounded(.up)),
              let end = Int64(exactly: (trim.end * 1000).rounded(.down)),
              let text = String(data: source, encoding: .utf8) else { throw ClipError.invalidSubtitles }
        guard !text.isEmpty, start < end else { return Data() }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n") as NSString
        let headers = cueHeader.matches(in: normalized as String, range: NSRange(location: 0, length: normalized.length))
        guard headers.first?.range.location == 0 else { throw ClipError.invalidSubtitles }
        var result = ""
        var outputIndex = 1
        for (index, header) in headers.enumerated() {
            guard let cueStart = milliseconds(normalized.substring(with: header.range(at: 1))),
                  let cueEnd = milliseconds(normalized.substring(with: header.range(at: 2))) else { throw ClipError.invalidSubtitles }
            let clippedStart = max(start, cueStart)
            let clippedEnd = min(end, cueEnd)
            guard clippedStart < clippedEnd else { continue }

            let bodyStart = NSMaxRange(header.range)
            let bodyEnd = index + 1 < headers.count ? headers[index + 1].range.location : normalized.length
            var body = normalized.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
            while body.last == "\n" { body.removeLast() }
            guard !body.isEmpty else { continue }
            result += "\(outputIndex)\n\(timestamp(clippedStart - start)) --> \(timestamp(clippedEnd - start))\n\(body)\n\n"
            outputIndex += 1
        }
        return Data(result.utf8)
    }

    private static func milliseconds(_ value: String) -> Int64? {
        let negative = value.hasPrefix("-")
        let absolute = negative ? value.dropFirst() : value[...]
        let fields = absolute.split { $0 == ":" || $0 == "," }
        guard fields.count == 4,
              let hours = Int64(fields[0]), hours < Int64.max / 3_600_000,
              let minutes = Int64(fields[1]), let seconds = Int64(fields[2]),
              let fraction = Int64(fields[3]) else { return nil }
        let time = ((hours * 60 + minutes) * 60 + seconds) * 1000 + fraction
        return negative ? -time : time
    }

    private static func timestamp(_ time: Int64) -> String {
        String(format: "%02lld:%02lld:%02lld,%03lld", time / 3_600_000, time / 60_000 % 60, time / 1000 % 60, time % 1000)
    }

    private enum ClipError: Error {
        case invalidSubtitles
    }
}
