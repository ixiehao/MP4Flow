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

    var displayString: String { "\(major).\(minor).\(patch)" }
}

struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let downloadURL: URL
}

enum UpdateCheckResult: Equatable, Sendable {
    case available(AvailableUpdate)
    case upToDate
    case failed
    case checking
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
    }

    func update(newerThan installedVersion: ReleaseVersion) -> AvailableUpdate? {
        guard !draft, !prerelease,
              let version = ReleaseVersion(tag: tagName), installedVersion < version,
              htmlURL.scheme == "https", htmlURL.host == "github.com",
              htmlURL.path.hasPrefix("/ixiehao/MP4Flow/releases/") else {
            return nil
        }
        return AvailableUpdate(version: version.displayString, downloadURL: htmlURL)
    }
}

enum UpdateCheckSchedule {
    static let automaticChecksEnabledKey = "com.ixiehao.MP4Flow.updates.automaticChecksEnabled"
    static let startupDelay: TimeInterval = 60

    static func automaticChecksEnabled(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: automaticChecksEnabledKey) != nil else { return true }
        return defaults.bool(forKey: automaticChecksEnabledKey)
    }
}

/// Reads only MP4Flow's public GitHub release metadata. It never sends media,
/// file paths, preferences, or usage data.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var lastCheckFailed = false
    @Published private(set) var isChecking = false

    private let session: URLSession
    private let currentVersion: ReleaseVersion
    private let defaults: UserDefaults
    private let pause: @Sendable (TimeInterval) async throws -> Void
    private var hasScheduledStartupCheck = false

    private static let releaseURL = URL(string: "https://api.github.com/repos/ixiehao/MP4Flow/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/ixiehao/MP4Flow/releases/latest")!
    private static let dismissedUpdateVersionKey = "com.ixiehao.MP4Flow.updates.dismissedVersion"

    init(
        currentVersion: ReleaseVersion? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        pause: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        self.currentVersion = currentVersion ?? Self.installedVersion
        self.session = session
        self.defaults = defaults
        self.pause = pause
    }

    var hasUpdate: Bool { availableUpdate != nil }
    var shouldShowUpdateBanner: Bool {
        guard let version = availableUpdate?.version else { return false }
        return defaults.string(forKey: Self.dismissedUpdateVersionKey) != version
    }

    /// The shared checker is also used by reopened windows; schedule only once per app process.
    func checkAfterStartupDelay() async -> UpdateCheckResult? {
        guard !hasScheduledStartupCheck else { return nil }
        hasScheduledStartupCheck = true
        do {
            try await pause(UpdateCheckSchedule.startupDelay)
        } catch {
            return nil
        }
        guard UpdateCheckSchedule.automaticChecksEnabled(in: defaults) else { return nil }
        return await checkForUpdate()
    }

    func checkForUpdate() async -> UpdateCheckResult {
        guard !isChecking else { return .checking }

        isChecking = true
        defer {
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
            guard ReleaseVersion(tag: release.tagName) != nil else {
                lastCheckFailed = true
                return .failed
            }

            if let update = release.update(newerThan: currentVersion) {
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

    func dismissAvailableUpdateBanner() {
        guard let version = availableUpdate?.version else { return }
        defaults.set(version, forKey: Self.dismissedUpdateVersionKey)
        objectWillChange.send()
    }

    private static var installedVersion: ReleaseVersion {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return ReleaseVersion(tag: version ?? "0.0.0") ?? ReleaseVersion(tag: "0.0.0")!
    }
}
