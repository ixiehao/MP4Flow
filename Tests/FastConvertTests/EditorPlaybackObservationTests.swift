import AVFoundation
import XCTest
@testable import FastConvert

final class EditorPlaybackObservationTests: XCTestCase {
    @MainActor
    func testDetachedAndPreviousPlayerTicksCannotChangeCurrentTransport() {
        let observation = EditorPlaybackObservation()
        let first = AVPlayer(), second = AVPlayer()
        observation.attach(to: first)
        let firstSession = observation.sessionIdentity
        observation.receive(seconds: 3, from: first, session: firstSession)
        XCTAssertEqual(observation.currentTime, 3)
        observation.attach(to: second)
        let secondSession = observation.sessionIdentity
        XCTAssertNotEqual(secondSession, firstSession)
        XCTAssertEqual(observation.currentTime, 0)
        observation.receive(seconds: 99, from: first, session: firstSession)
        observation.receive(seconds: 99, from: first, session: secondSession)
        XCTAssertEqual(observation.currentTime, 0)
        observation.receive(seconds: 7, from: second, session: secondSession)
        XCTAssertEqual(observation.currentTime, 7)
        observation.detach()
        observation.receive(seconds: 99, from: second, session: secondSession)
        XCTAssertEqual(observation.currentTime, 7)
        XCTAssertFalse(observation.isObserving)
    }

    @MainActor
    func testReattachingSamePlayerDoesNotAcceptTicksFromItsPreviousSubscription() {
        let observation = EditorPlaybackObservation()
        let player = AVPlayer()
        observation.attach(to: player)
        let first = observation.sessionIdentity
        observation.detach()
        observation.attach(to: player)
        defer { observation.detach() }
        let second = observation.sessionIdentity
        XCTAssertNotEqual(first, second)
        observation.receive(seconds: 15, from: player, session: first)
        XCTAssertEqual(observation.currentTime, 0)
        observation.receive(seconds: 5, from: player, session: second)
        XCTAssertEqual(observation.currentTime, 5)
        observation.attach(to: player)
        XCTAssertEqual(observation.sessionIdentity, second, "Repeated appearance must not create duplicate observers")
        observation.receive(seconds: .nan, from: player, session: second)
        XCTAssertEqual(observation.currentTime, 5)
    }

    @MainActor
    func testDetachingReleasesPlayerInsteadOfRetainingTheOldView() {
        let observation = EditorPlaybackObservation()
        weak var released: AVPlayer?
        autoreleasepool {
            let player = AVPlayer()
            released = player
            observation.attach(to: player)
            XCTAssertTrue(observation.isObserving)
            observation.detach()
        }
        XCTAssertNil(released)
        XCTAssertFalse(observation.isObserving)
    }
}
