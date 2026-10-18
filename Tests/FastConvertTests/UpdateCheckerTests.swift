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

    private static func response(for request: URLRequest, statusCode: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: statusCode, httpVersion: nil, headerFields: nil))
    }
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
