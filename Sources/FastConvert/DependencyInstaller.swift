import Foundation

/// Installs only the Homebrew FFmpeg formula. Never invokes a shell or sudo.
enum DependencyInstaller {
    enum Outcome: Equatable {
        case homebrewMissing
        case installed
        case failed(String)
    }

    struct CommandResult: Sendable {
        let succeeded: Bool
        let detail: String
    }

    static var brewCandidates: [URL] {
#if arch(arm64)
        return [URL(fileURLWithPath: "/opt/homebrew/bin/brew"), URL(fileURLWithPath: "/usr/local/bin/brew")]
#else
        return [URL(fileURLWithPath: "/usr/local/bin/brew"), URL(fileURLWithPath: "/opt/homebrew/bin/brew")]
#endif
    }

    static func formula(for path: String?) -> String {
        path?.split(separator: "/").contains("ffmpeg-full") == true ? "ffmpeg-full" : "ffmpeg"
    }

    static func install(
        damagedFFmpeg: String? = nil,
        candidates: [URL] = brewCandidates,
        run: @Sendable (URL, [String]) async -> CommandResult = { await runBrew($0, $1) }
    ) async -> Outcome {
        let matchingBrew = damagedFFmpeg.flatMap { path in
            candidates.first { candidate in
                let prefix = candidate.deletingLastPathComponent().deletingLastPathComponent().path
                return path.hasPrefix(prefix + "/")
            }
        }
        let executable = { (url: URL) in FileManager.default.isExecutableFile(atPath: url.path) }
        guard let brew = matchingBrew.flatMap({ executable($0) ? $0 : nil }) ?? candidates.first(where: executable) else {
            return .homebrewMissing
        }
        let package = formula(for: damagedFFmpeg)
        // A damaged or partially unlinked formula needs reinstall, not install.
        let installed = await run(brew, ["list", "--versions", package])
        guard !Task.isCancelled else { return .failed("") }
        let result = await run(brew, [installed.succeeded ? "reinstall" : "install", package])
        return result.succeeded ? .installed : .failed(result.detail)
    }

    private static func runBrew(_ brew: URL, _ arguments: [String]) async -> CommandResult {
        let runner = FFmpegProcessRunner(
            executable: brew,
            arguments: arguments,
            configuration: .init(inactivityTimeout: 600, maximumOutputBytes: 16_384, maximumErrorBytes: 16_384)
        )
        let result = await runner.run()
        let error = result.launchError ?? result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(succeeded: result.succeeded, detail: String((error.isEmpty ? output : error).suffix(1_000)))
    }
}
