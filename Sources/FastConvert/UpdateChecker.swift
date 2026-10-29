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

/// GitHub owns the latest-release selection. Only accept an exact, stable tag
/// on this repository; never parse HTML or follow a download/third-party URL.
enum ReleaseEndpoint {
    static let api = URL(string: "https://api.github.com/repos/ixiehao/MP4Flow/releases/latest")!
    static let latest = URL(string: "https://github.com/ixiehao/MP4Flow/releases/latest")!

    static func version(at url: URL) -> ReleaseVersion? {
        guard url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let prefix = "/ixiehao/MP4Flow/releases/tag/"
        guard url.path.hasPrefix(prefix) else { return nil }
        let tag = String(url.path.dropFirst(prefix.count))
        guard !tag.contains("/"), !tag.contains("%"),
              let version = ReleaseVersion(tag: tag),
              tag == version.displayString || tag == "v" + version.displayString else { return nil }
        return version
    }
}

/// Inspect Location without fetching a release HTML page or following an
/// unexpected host. A HEAD request returns no release body.
private final class ReleaseRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
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

    var stableVersion: ReleaseVersion? {
        guard !draft, !prerelease,
              let version = ReleaseVersion(tag: tagName),
              tagName == version.displayString || tagName == "v" + version.displayString,
              ReleaseEndpoint.version(at: htmlURL) == version else { return nil }
        return version
    }

    func update(newerThan installedVersion: ReleaseVersion) -> AvailableUpdate? {
        guard let version = stableVersion, installedVersion < version else { return nil }
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

/// Reads only MP4Flow's public GitHub release link/metadata. It never sends media,
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
    private let now: @Sendable () -> Date
    private var hasScheduledStartupCheck = false

    private let redirectBlocker = ReleaseRedirectBlocker()
    private static let apiRetryTimeKey = "com.ixiehao.MP4Flow.updates.apiRetryNotBefore"
    private static let dismissedUpdateVersionKey = "com.ixiehao.MP4Flow.updates.dismissedVersion"

    init(
        currentVersion: ReleaseVersion? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        pause: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.currentVersion = currentVersion ?? Self.installedVersion
        self.session = session
        self.defaults = defaults
        self.pause = pause
        self.now = now
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

        // Normal checks do not consume the shared, per-IP REST API quota.
        do {
            let (_, response) = try await session.data(
                for: request(to: ReleaseEndpoint.latest, method: "HEAD"), delegate: redirectBlocker
            )
            if let response = response as? HTTPURLResponse {
                let destination: URL?
                if [301, 302, 303, 307, 308].contains(response.statusCode),
                   let location = response.value(forHTTPHeaderField: "Location") {
                    destination = URL(string: location, relativeTo: ReleaseEndpoint.latest)?.absoluteURL
                } else if response.statusCode == 200 {
                    destination = response.url
                } else {
                    destination = nil
                }
                if let destination, let version = ReleaseEndpoint.version(at: destination) {
                    return accept(version: version, page: destination)
                }
            }
        } catch {
            if Task.isCancelled { return failedCheck() }
        }

        if let retryTime = defaults.object(forKey: Self.apiRetryTimeKey) as? Date, now() < retryTime {
            return failedCheck()
        }
        do {
            var request = request(to: ReleaseEndpoint.api)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request, delegate: redirectBlocker)
            guard let response = response as? HTTPURLResponse else { return failedCheck() }
            if response.statusCode == 403 || response.statusCode == 429 {
                deferAPI(after: response)
                return failedCheck()
            }
            guard response.statusCode == 200 else { return failedCheck() }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let version = release.stableVersion else { return failedCheck() }
            defaults.removeObject(forKey: Self.apiRetryTimeKey)
            return accept(version: version, page: release.htmlURL)
        } catch {
            return failedCheck()
        }
    }

    private func request(to url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("MP4Flow update checker", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func accept(version: ReleaseVersion, page: URL) -> UpdateCheckResult {
        lastCheckFailed = false
        guard currentVersion < version else {
            availableUpdate = nil
            return .upToDate
        }
        let update = AvailableUpdate(version: version.displayString, downloadURL: page)
        availableUpdate = update
        return .available(update)
    }

    private func failedCheck() -> UpdateCheckResult {
        // A failed request must not hide an update already found this session.
        lastCheckFailed = true
        return .failed
    }

    private func deferAPI(after response: HTTPURLResponse) {
        let current = now()
        var retryTime = current.addingTimeInterval(60)
        if let raw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let timestamp = TimeInterval(raw), timestamp.isFinite {
            retryTime = max(retryTime, Date(timeIntervalSince1970: timestamp))
        }
        if let raw = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(raw), seconds.isFinite, seconds >= 0 {
                retryTime = max(retryTime, current.addingTimeInterval(seconds))
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                if let date = formatter.date(from: raw) { retryTime = max(retryTime, date) }
            }
        }
        defaults.set(retryTime, forKey: Self.apiRetryTimeKey)
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(availableUpdate?.downloadURL ?? ReleaseEndpoint.latest)
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
