import AppKit
import Foundation

/// Version comparison for stable GitHub release tags such as `v1.1.0`.
struct ReleaseVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(tag: String) {
        let raw = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let downloadURL: URL
}

enum UpdateCheckResult: Sendable {
    case available(AvailableUpdate)
    case upToDate
    case failed
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
    }
}

/// Reads only MP4Flow's public GitHub release metadata. It never sends media,
/// file paths, preferences, or usage data.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var lastCheckFailed = false

    private let session: URLSession
    private let currentVersion: ReleaseVersion
    private var isChecking = false
    private var lastCheckedAt: Date?

    private static let releaseURL = URL(string: "https://api.github.com/repos/ixiehao/MP4Flow/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/ixiehao/MP4Flow/releases/latest")!
    private static let checkInterval: TimeInterval = 12 * 60 * 60

    init(currentVersion: ReleaseVersion? = nil, session: URLSession = .shared) {
        self.currentVersion = currentVersion ?? Self.installedVersion
        self.session = session
    }

    var hasUpdate: Bool { availableUpdate != nil }

    func checkForUpdate(force: Bool = false) async -> UpdateCheckResult {
        if isChecking { return availableUpdate.map(UpdateCheckResult.available) ?? .upToDate }
        if !force, let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.checkInterval {
            return availableUpdate.map(UpdateCheckResult.available) ?? (lastCheckFailed ? .failed : .upToDate)
        }

        isChecking = true
        defer {
            lastCheckedAt = Date()
            isChecking = false
        }

        var request = URLRequest(url: Self.releaseURL)
        request.timeoutInterval = 10
        request.setValue("MP4Flow update checker", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                lastCheckFailed = true
                return .failed
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !release.draft, !release.prerelease,
                  let version = ReleaseVersion(tag: release.tagName),
                  release.htmlURL.scheme == "https", release.htmlURL.host == "github.com",
                  release.htmlURL.path.hasPrefix("/ixiehao/MP4Flow/releases/") else {
                lastCheckFailed = true
                return .failed
            }

            if currentVersion < version {
                let update = AvailableUpdate(version: release.tagName, downloadURL: release.htmlURL)
                availableUpdate = update
                lastCheckFailed = false
                return .available(update)
            }

            availableUpdate = nil
            lastCheckFailed = false
            return .upToDate
        } catch {
            lastCheckFailed = true
            return .failed
        }
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(availableUpdate?.downloadURL ?? Self.releasesPage)
    }

    private static var installedVersion: ReleaseVersion {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return ReleaseVersion(tag: version ?? "0.0.0") ?? ReleaseVersion(tag: "0.0.0")!
    }
}
