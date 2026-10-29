import Foundation
import XCTest
@testable import FastConvert

final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "MP4Flow.UpdateCheckerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        if let defaultsSuiteName {
            defaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testStableSemanticVersionsCompareButMalformedTagsDoNot() throws {
        let installed = try XCTUnwrap(ReleaseVersion(tag: "v1.1.1"))
        XCTAssertLessThan(installed, try XCTUnwrap(ReleaseVersion(tag: "1.1.2")))
        XCTAssertNil(ReleaseVersion(tag: "v1.2"))
        XCTAssertNil(ReleaseVersion(tag: "v1.2.3-beta"))
        XCTAssertNil(ReleaseVersion(tag: "version 1.2.3"))
    }

    func testOnlyNewStableReleasesFromMP4FlowAreAccepted() throws {
        let installed = try XCTUnwrap(ReleaseVersion(tag: "1.1.1"))
        func release(
            tag: String = "v1.1.2",
            url: String = "https://github.com/ixiehao/MP4Flow/releases/tag/v1.1.2",
            draft: Bool = false,
            prerelease: Bool = false
        ) -> GitHubRelease {
            GitHubRelease(tagName: tag, htmlURL: try! XCTUnwrap(URL(string: url)), draft: draft, prerelease: prerelease)
        }

        XCTAssertEqual(release().update(newerThan: installed)?.version, "1.1.2")
        XCTAssertNil(release(tag: "v1.1.1").update(newerThan: installed))
        XCTAssertNil(release(draft: true).update(newerThan: installed))
        XCTAssertNil(release(prerelease: true).update(newerThan: installed))
        XCTAssertNil(release(url: "http://github.com/ixiehao/MP4Flow/releases/tag/v1.1.2").update(newerThan: installed))
        XCTAssertNil(release(url: "https://example.com/MP4Flow/releases/tag/v1.1.2").update(newerThan: installed))
        XCTAssertNil(release(url: "https://github.com/ixiehao/other/releases/tag/v1.1.2").update(newerThan: installed))
        XCTAssertNil(release(url: "https://github.com/ixiehao/MP4Flow/releases/tag/v9.9.9").update(newerThan: installed))
    }

    func testReleaseRedirectOnlyAcceptsExactStableOfficialTagPages() throws {
        let good = "https://github.com/ixiehao/MP4Flow/releases/tag/v1.3.1"
        XCTAssertEqual(ReleaseEndpoint.version(at: try XCTUnwrap(URL(string: good)))?.displayString, "1.3.1")
        for url in [
            "http://github.com/ixiehao/MP4Flow/releases/tag/v1.3.1",
            "https://github.com.example.com/ixiehao/MP4Flow/releases/tag/v1.3.1",
            "https://github.com/another/MP4Flow/releases/tag/v1.3.1",
            "https://github.com/ixiehao/MP4Flow/releases/latest",
            good + "-beta", good + "/more", good + "?other=1", good + "#other",
            "https://user@github.com/ixiehao/MP4Flow/releases/tag/v1.3.1",
            "https://github.com:443/ixiehao/MP4Flow/releases/tag/v1.3.1",
            "https://github.com/ixiehao/MP4Flow/releases/tag/v01.3.1"
        ] {
            XCTAssertNil(ReleaseEndpoint.version(at: try XCTUnwrap(URL(string: url))), url)
        }
    }

    @MainActor
    func testLatestRedirectFindsUpdateWithoutUsingRateLimitedAPI() async throws {
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.append(request)
            guard request.url == ReleaseEndpoint.latest else {
                return (try Self.response(for: request, statusCode: 403), Data())
            }
            XCTAssertEqual(request.httpMethod, "HEAD")
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.timeoutInterval, 5)
            return (try Self.response(for: request, statusCode: 302, headers: [
                "Location": "https://github.com/ixiehao/MP4Flow/releases/tag/v1.3.1"
            ]), Data())
        }
        let checker = makeChecker(installed: "1.3.0")
        await expectResult(checker, .available(AvailableUpdate(
            version: "1.3.1", downloadURL: URL(string: "https://github.com/ixiehao/MP4Flow/releases/tag/v1.3.1")!
        )))
        XCTAssertEqual(requests.values.count, 1)
        XCTAssertTrue(checker.shouldShowUpdateBanner)
        XCTAssertFalse(checker.lastCheckFailed)
    }

    @MainActor
    func testAutomaticCheckUsesRedirectAfter60SecondsAndHonorsDismissedVersion() async throws {
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.append(request)
            return (try Self.response(for: request, statusCode: 302, headers: [
                "Location": "/ixiehao/MP4Flow/releases/tag/v1.3.1"
            ]), Data())
        }
        let checker = UpdateChecker(
            currentVersion: ReleaseVersion(tag: "1.3.0"), session: makeStubSession(), defaults: defaults,
            pause: { delay in XCTAssertEqual(delay, 60) }
        )
        guard case .available? = await checker.checkAfterStartupDelay() else {
            return XCTFail("Startup must find the stable update without the API")
        }
        XCTAssertTrue(checker.shouldShowUpdateBanner)
        checker.dismissAvailableUpdateBanner()
        XCTAssertFalse(checker.shouldShowUpdateBanner)
        guard case .available = await checker.checkForUpdate() else { return XCTFail("Manual result missing") }
        XCTAssertFalse(checker.shouldShowUpdateBanner)
        let repeated = await checker.checkAfterStartupDelay()
        XCTAssertNil(repeated)
        XCTAssertEqual(requests.values.count, 2)
    }

    @MainActor
    func testCurrentOrOlderRedirectIsUpToDateWithoutAPIFallback() async throws {
        for tag in ["v1.3.1", "v1.3.0"] {
            let requests = RequestLog()
            StubURLProtocol.handler = { request in
                requests.append(request)
                return (try Self.response(for: request, statusCode: 302, headers: [
                    "Location": "/ixiehao/MP4Flow/releases/tag/" + tag
                ]), Data())
            }
            let checker = makeChecker(installed: "1.3.1")
            await expectResult(checker, .upToDate)
            XCTAssertFalse(checker.hasUpdate)
            XCTAssertEqual(requests.values.count, 1)
        }
    }

    @MainActor
    func testBlockedUnsupportedOrTimedOutPageFallsBackToPublicAPI() async throws {
        for status in [403, 405, 429, 500, 200, -1] {
            let requests = RequestLog()
            StubURLProtocol.handler = { request in
                requests.append(request)
                if request.url == ReleaseEndpoint.latest {
                    if status == -1 { throw URLError(.timedOut) }
                    return (try Self.response(for: request, statusCode: status), Data("not a release".utf8))
                }
                XCTAssertEqual(request.url, ReleaseEndpoint.api)
                return (try Self.response(for: request, statusCode: 200), try Self.validRelease())
            }
            let checker = makeChecker(installed: "1.3.0")
            guard case .available(let update) = await checker.checkForUpdate() else {
                return XCTFail("API fallback failed for page status \(status)")
            }
            XCTAssertEqual(update.version, "1.3.1")
            XCTAssertEqual(requests.values.count, 2)
        }
    }

    @MainActor
    func testAPIBackoffPersistsAcrossLaunchesButDoesNotSuppressPageChecks() async throws {
        let requests = RequestLog()
        let current = Date(timeIntervalSince1970: 1_800_000_000)
        StubURLProtocol.handler = { request in
            requests.append(request)
            if request.url == ReleaseEndpoint.latest { return (try Self.response(for: request, statusCode: 405), Data()) }
            return (try Self.response(for: request, statusCode: 403, headers: [
                "X-RateLimit-Reset": String(Int(current.timeIntervalSince1970 + 300)), "Retry-After": "120"
            ]), Data())
        }
        let checker = makeChecker(installed: "1.3.0", now: { current })
        await expectResult(checker, .failed)
        let relaunched = makeChecker(installed: "1.3.0", now: { current.addingTimeInterval(200) })
        await expectResult(relaunched, .failed)
        XCTAssertEqual(requests.values.filter { $0.url == ReleaseEndpoint.api }.count, 1)

        StubURLProtocol.handler = { request in
            requests.append(request)
            return (try Self.response(for: request, statusCode: 302, headers: [
                "Location": "/ixiehao/MP4Flow/releases/tag/v1.3.1"
            ]), Data())
        }
        guard case .available = await relaunched.checkForUpdate() else {
            return XCTFail("API cooldown must not block a valid page redirect")
        }
        XCTAssertFalse(relaunched.lastCheckFailed)
    }

    @MainActor
    func testAPIBackoffExpiresAndRespectsRetryAfterDate() async throws {
        let current = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let after = formatter.string(from: current.addingTimeInterval(120))
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.append(request)
            if request.url == ReleaseEndpoint.latest { return (try Self.response(for: request, statusCode: 405), Data()) }
            return (try Self.response(for: request, statusCode: 429, headers: ["Retry-After": after]), Data())
        }
        let first = makeChecker(installed: "1.3.0", now: { current })
        await expectResult(first, .failed)
        let before = makeChecker(installed: "1.3.0", now: { current.addingTimeInterval(119) })
        await expectResult(before, .failed)
        XCTAssertEqual(requests.values.filter { $0.url == ReleaseEndpoint.api }.count, 1)
        StubURLProtocol.handler = { request in
            requests.append(request)
            if request.url == ReleaseEndpoint.latest { return (try Self.response(for: request, statusCode: 405), Data()) }
            return (try Self.response(for: request, statusCode: 200), try Self.validRelease())
        }
        let expired = makeChecker(installed: "1.3.0", now: { current.addingTimeInterval(121) })
        guard case .available = await expired.checkForUpdate() else { return XCTFail("API should recover after cooldown") }
        XCTAssertEqual(requests.values.filter { $0.url == ReleaseEndpoint.api }.count, 2)
    }

    @MainActor
    func testUntrustedRedirectAndInvalidAPIMetadataNeverReportUpToDate() async throws {
        for payload in [Data("invalid JSON".utf8), try Self.validRelease(url: "https://example.com/v1.3.1"),
                        try Self.validRelease(tag: "v1.3.2"), try Self.validRelease(prerelease: true)] {
            StubURLProtocol.handler = { request in
                if request.url == ReleaseEndpoint.latest {
                    return (try Self.response(for: request, statusCode: 302, headers: ["Location": "https://example.com/v1.3.1"]), Data())
                }
                return (try Self.response(for: request, statusCode: 200), payload)
            }
            let checker = makeChecker(installed: "1.3.0")
            await expectResult(checker, .failed)
            XCTAssertTrue(checker.lastCheckFailed)
            XCTAssertFalse(checker.hasUpdate)
        }
    }

    @MainActor
    func testFailedSourcesPreserveKnownUpdateAndCheckingStateRecovers() async throws {
        StubURLProtocol.handler = { request in
            (try Self.response(for: request, statusCode: 302, headers: ["Location": "/ixiehao/MP4Flow/releases/tag/v1.3.1"]), Data())
        }
        let checker = makeChecker(installed: "1.3.0")
        guard case .available = await checker.checkForUpdate() else { return XCTFail("Initial check failed") }
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await expectResult(checker, .failed)
        XCTAssertEqual(checker.availableUpdate?.version, "1.3.1")
        XCTAssertTrue(checker.shouldShowUpdateBanner)
        XCTAssertTrue(checker.lastCheckFailed)
        XCTAssertFalse(checker.isChecking)
    }

    @MainActor
    func testDismissalOnlyAppliesToThatVersionAndNewReleaseStillNotifies() async throws {
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.append(request)
            let tag = requests.values.count == 1 ? "v1.3.1" : "v1.3.2"
            return (try Self.response(for: request, statusCode: 302, headers: [
                "Location": "/ixiehao/MP4Flow/releases/tag/" + tag
            ]), Data())
        }
        let checker = makeChecker(installed: "1.3.0")
        _ = await checker.checkForUpdate()
        checker.dismissAvailableUpdateBanner()
        XCTAssertFalse(checker.shouldShowUpdateBanner)
        _ = await checker.checkForUpdate()
        XCTAssertEqual(checker.availableUpdate?.version, "1.3.2")
        XCTAssertTrue(checker.shouldShowUpdateBanner)
    }

    @MainActor
    func testConcurrentCheckDoesNotDuplicateNetworkRequests() async throws {
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.append(request)
            Thread.sleep(forTimeInterval: 0.05)
            return (try Self.response(for: request, statusCode: 302, headers: [
                "Location": "/ixiehao/MP4Flow/releases/tag/v1.3.1"
            ]), Data())
        }
        let checker = makeChecker(installed: "1.3.0")
        let first = Task { await checker.checkForUpdate() }
        while !checker.isChecking { await Task.yield() }
        await expectResult(checker, .checking)
        guard case .available = await first.value else { return XCTFail("Initial request failed") }
        XCTAssertEqual(requests.values.count, 1)
        XCTAssertFalse(checker.isChecking)
    }

    @MainActor
    func testAutomaticCheckWaits60SecondsAndRunsOncePerProcessIncludingFirstLaunch() async throws {
        let delayGate = StartupDelayGate()
        StubURLProtocol.handler = { request in
            let data = try JSONSerialization.data(withJSONObject: [
                "tag_name": "v1.1.2",
                "html_url": "https://github.com/ixiehao/MP4Flow/releases/tag/v1.1.2",
                "draft": false,
                "prerelease": false
            ])
            return (try Self.response(for: request, statusCode: 200), data)
        }
        let checker = UpdateChecker(
            currentVersion: try XCTUnwrap(ReleaseVersion(tag: "1.1.1")),
            session: makeStubSession(),
            defaults: defaults,
            pause: { delay in try await delayGate.pause(for: delay) }
        )

        let scheduledCheck = Task { await checker.checkAfterStartupDelay() }
        let requestedDelay = await delayGate.waitUntilStarted()
        XCTAssertEqual(requestedDelay, 60)
        XCTAssertFalse(checker.isChecking)
        XCTAssertFalse(checker.hasUpdate)
        await delayGate.release()

        guard case let .available(update)? = await scheduledCheck.value else {
            return XCTFail("Expected an update on the first launch")
        }
        XCTAssertEqual(update.version, "1.1.2")
        let repeatedCheck = await checker.checkAfterStartupDelay()
        XCTAssertNil(repeatedCheck)
    }

    @MainActor
    func testDisabledAutomaticCheckDoesNotRequestReleaseButManualCheckStillWorks() async throws {
        defaults.set(false, forKey: UpdateCheckSchedule.automaticChecksEnabledKey)
        let checker = UpdateChecker(
            currentVersion: try XCTUnwrap(ReleaseVersion(tag: "1.1.1")),
            session: makeStubSession(),
            defaults: defaults,
            pause: { delay in XCTAssertEqual(delay, 60) }
        )
        let automaticCheck = await checker.checkAfterStartupDelay()
        XCTAssertNil(automaticCheck)

        StubURLProtocol.handler = { request in
            let data = try JSONSerialization.data(withJSONObject: [
                "tag_name": "v1.1.1",
                "html_url": "https://github.com/ixiehao/MP4Flow/releases/tag/v1.1.1",
                "draft": false,
                "prerelease": false
            ])
            return (try Self.response(for: request, statusCode: 200), data)
        }
        let manualCheck = await checker.checkForUpdate()
        XCTAssertEqual(manualCheck, .upToDate)
    }

    @MainActor
    func testCheckerReportsAnAvailableStableRelease() async throws {
        StubURLProtocol.handler = { request in
            let data = try JSONSerialization.data(withJSONObject: [
                "tag_name": "v1.1.2",
                "html_url": "https://github.com/ixiehao/MP4Flow/releases/tag/v1.1.2",
                "draft": false,
                "prerelease": false
            ])
            return (try Self.response(for: request, statusCode: 200), data)
        }

        let checker = UpdateChecker(
            currentVersion: try XCTUnwrap(ReleaseVersion(tag: "1.1.1")),
            session: makeStubSession(),
            defaults: defaults,
            pause: { _ in }
        )
        let result = await checker.checkForUpdate()

        guard case let .available(update) = result else {
            return XCTFail("Expected an available update, got \(result)")
        }
        XCTAssertEqual(update.version, "1.1.2")
        XCTAssertTrue(checker.hasUpdate)
    }

    @MainActor
    func testCheckerTreatsHTTPFailuresAndTimeoutsAsNonFatalFailures() async throws {
        let installed = try XCTUnwrap(ReleaseVersion(tag: "1.1.1"))

        StubURLProtocol.handler = { request in
            (try Self.response(for: request, statusCode: 429), Data())
        }
        var checker = UpdateChecker(currentVersion: installed, session: makeStubSession(), defaults: defaults)
        let httpFailureResult = await checker.checkForUpdate()
        XCTAssertEqual(httpFailureResult, .failed)
        XCTAssertTrue(checker.lastCheckFailed)

        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        checker = UpdateChecker(currentVersion: installed, session: makeStubSession(), defaults: defaults)
        let timeoutFailureResult = await checker.checkForUpdate()
        XCTAssertEqual(timeoutFailureResult, .failed)
        XCTAssertTrue(checker.lastCheckFailed)
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @MainActor
    private func expectResult(
        _ checker: UpdateChecker, _ expected: UpdateCheckResult,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let result = await checker.checkForUpdate()
        XCTAssertEqual(result, expected, file: file, line: line)
    }

    @MainActor
    private func makeChecker(installed: String, now: @escaping @Sendable () -> Date = { Date() }) -> UpdateChecker {
        UpdateChecker(currentVersion: ReleaseVersion(tag: installed), session: makeStubSession(), defaults: defaults, now: now)
    }

    private static func validRelease(
        tag: String = "v1.3.1", url: String = "https://github.com/ixiehao/MP4Flow/releases/tag/v1.3.1", prerelease: Bool = false
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url, "draft": false, "prerelease": prerelease])
    }

    private static func response(for request: URLRequest, statusCode: Int, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: statusCode, httpVersion: nil, headerFields: headers))
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []
    func append(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; storage.append(request) }
    var values: [URLRequest] { lock.lock(); defer { lock.unlock() }; return storage }
}

private actor StartupDelayGate {
    private var requestedDelay: TimeInterval?
    private var started: CheckedContinuation<TimeInterval, Never>?
    private var pending: CheckedContinuation<Void, Error>?

    func pause(for delay: TimeInterval) async throws {
        requestedDelay = delay
        started?.resume(returning: delay)
        started = nil
        try await withCheckedThrowingContinuation { pending = $0 }
    }

    func waitUntilStarted() async -> TimeInterval {
        if let requestedDelay { return requestedDelay }
        return await withCheckedContinuation { started = $0 }
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
