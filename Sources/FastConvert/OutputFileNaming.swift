import Foundation

/// Shared by conversion and both merge modes. A valid source filename can be
/// near NAME_MAX already; appending an edit suffix must not make saving fail.
/// Reserve the complete suffix, extension and collision number before fitting
/// the source stem. Whole characters preserve Unicode filenames at the limit.
enum OutputFileNaming {
    private static let maximumComponentBytes = 255

    static func uniqueURL(in directory: URL, stem: String, suffix: String) -> URL {
        // File URLs can expose the filesystem's decomposed spelling after a
        // lookup (é becomes e + accent; a Hangul syllable becomes Jamo). Budget
        // that spelling up front rather than only measuring the input string.
        let filesystemStem = stem.decomposedStringWithCanonicalMapping
        var number = 1
        while true {
            let ending = suffix + (number == 1 ? "" : "-\(number)") + ".mp4"
            let budget = maximumComponentBytes - ending.utf8.count
            var bytes = 0
            var fittedStem = String(filesystemStem.prefix { character in
                bytes += String(character).utf8.count
                return bytes <= budget
            })
            while true {
                let name = (fittedStem.isEmpty ? "Video" : fittedStem) + ending
                let candidate = directory.appendingPathComponent(name)
                let exists = FileManager.default.fileExists(atPath: candidate.path)
                // Verify the actual URL component after its filesystem lookup,
                // not just our normalization estimate. Retain whole characters.
                if candidate.lastPathComponent.utf8.count > maximumComponentBytes, !fittedStem.isEmpty {
                    fittedStem.removeLast()
                    continue
                }
                if !exists { return candidate }
                break
            }
            number += 1
        }
    }
}
