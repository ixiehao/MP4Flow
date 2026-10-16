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
    private static let hasLaunchedKey = "com.ixiehao.MP4Flow.updates.hasLaunched"
    private static let lastSuccessfulCheckKey = "com.ixiehao.MP4Flow.updates.lastSuccessfulCheck"
    private static let lastFailedCheckKey = "com.ixiehao.MP4Flow.updates.lastFailedCheck"

    static let successfulCheckInterval: TimeInterval = 24 * 60 * 60
    static let failedCheckInterval: TimeInterval = 60 * 60

    static func automaticChecksEnabled(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: automaticChecksEnabledKey) != nil else { return true }
        return defaults.bool(forKey: automaticChecksEnabledKey)
    }

    /// Keeps the very first launch network-free. A later launch may check only
    /// when the user has enabled automatic checks and the relevant backoff has elapsed.
    static func registerLaunchAndShouldCheck(in defaults: UserDefaults, now: Date) -> Bool {
        let hasLaunchedBefore = defaults.bool(forKey: hasLaunchedKey)
        defaults.set(true, forKey: hasLaunchedKey)

        guard hasLaunchedBefore, automaticChecksEnabled(in: defaults) else { return false }
        if let lastSuccess = defaults.object(forKey: lastSuccessfulCheckKey) as? Date,
           now.timeIntervalSince(lastSuccess) < successfulCheckInterval {
            return false
        }
        if let lastFailure = defaults.object(forKey: lastFailedCheckKey) as? Date,
           now.timeIntervalSince(lastFailure) < failedCheckInterval {
            return false
        }
        return true
    }

    static func recordSuccessfulCheck(in defaults: UserDefaults, now: Date) {
        defaults.set(now, forKey: lastSuccessfulCheckKey)
        defaults.removeObject(forKey: lastFailedCheckKey)
    }

    static func recordFailedCheck(in defaults: UserDefaults, now: Date) {
        defaults.set(now, forKey: lastFailedCheckKey)
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
    private let now: () -> Date

    private static let releaseURL = URL(string: "https://api.github.com/repos/ixiehao/MP4Flow/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/ixiehao/MP4Flow/releases/latest")!
    private static let dismissedUpdateVersionKey = "com.ixiehao.MP4Flow.updates.dismissedVersion"

    init(
        currentVersion: ReleaseVersion? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion ?? Self.installedVersion
        self.session = session
        self.defaults = defaults
        self.now = now
    }

    var hasUpdate: Bool { availableUpdate != nil }
    var shouldShowUpdateBanner: Bool {
        guard let version = availableUpdate?.version else { return false }
        return defaults.string(forKey: Self.dismissedUpdateVersionKey) != version
    }

    /// Automatic checks begin from the second launch so first-run setup stays local.
    func checkAtLaunchIfEligible() async -> UpdateCheckResult? {
        guard UpdateCheckSchedule.registerLaunchAndShouldCheck(in: defaults, now: now()) else { return nil }
        return await checkForUpdate(force: true)
    }

    func checkForUpdate(force: Bool = false) async -> UpdateCheckResult {
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
                UpdateCheckSchedule.recordFailedCheck(in: defaults, now: now())
                return .failed
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard ReleaseVersion(tag: release.tagName) != nil else {
                lastCheckFailed = true
                UpdateCheckSchedule.recordFailedCheck(in: defaults, now: now())
                return .failed
            }

            if let update = release.update(newerThan: currentVersion) {
                availableUpdate = update
                lastCheckFailed = false
                UpdateCheckSchedule.recordSuccessfulCheck(in: defaults, now: now())
                return .available(update)
            }

            availableUpdate = nil
            lastCheckFailed = false
            UpdateCheckSchedule.recordSuccessfulCheck(in: defaults, now: now())
            return .upToDate
        } catch {
            lastCheckFailed = true
            UpdateCheckSchedule.recordFailedCheck(in: defaults, now: now())
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
