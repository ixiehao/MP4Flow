import Foundation

enum ConcatManifest {
    static func render(_ sources: [URL]) throws -> String {
        guard sources.allSatisfy({ $0.isFileURL && !$0.path.contains("\n") && !$0.path.contains("\r") }) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        // FFmpeg's single-quoted token parser does not interpret backslash
        // escapes inside quotes. Leave quotes, escape the apostrophe, reenter.
        return sources.map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: "\n") + "\n"
    }
}
