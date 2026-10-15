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

    func testAutomaticScheduleSkipsFirstLaunchAndPersistsDailyBackoff() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(UpdateCheckSchedule.registerLaunchAndShouldCheck(in: defaults, now: now))
        XCTAssertTrue(UpdateCheckSchedule.registerLaunchAndShouldCheck(in: defaults, now: now.addingTimeInterval(30)))

        UpdateCheckSchedule.recordSuccessfulCheck(in: defaults, now: now)
        XCTAssertFalse(UpdateCheckSchedule.registerLaunchAndShouldCheck(in: defaults, now: now.addingTimeInterval(23 * 60 * 60)))
        XCTAssertTrue(UpdateCheckSchedule.registerLaunchAndShouldCheck(in: defaults, now: now.addingTimeInterval(24 * 60 * 60)))

        defaults.set(false, forKey: UpdateCheckSchedule.automaticChecksEnabledKey)
        XCTAssertFalse(UpdateCheckSchedule.registerLaunchAndShouldCheck(in: defaults, now: now.addingTimeInterval(48 * 60 * 60)))
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
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let result = await checker.checkForUpdate(force: true)

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
        let httpFailureResult = await checker.checkForUpdate(force: true)
        XCTAssertEqual(httpFailureResult, .failed)
        XCTAssertTrue(checker.lastCheckFailed)

        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        checker = UpdateChecker(currentVersion: installed, session: makeStubSession(), defaults: defaults)
        let timeoutFailureResult = await checker.checkForUpdate(force: true)
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
