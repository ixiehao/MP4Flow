import AVFoundation
import Combine
import Foundation

/// The transport UI owns exactly one observation. A tick never captures a
/// SwiftUI value (and its player); callbacks keep both references weak until
/// they reach the main actor and validate the current subscription.
@MainActor
final class EditorPlaybackObservation: ObservableObject {
    @Published var currentTime = 0.0
    @Published var isPlaying = false
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private(set) var sessionIdentity = UUID()
    var isObserving: Bool { timeObserver != nil }

    func attach(to newPlayer: AVPlayer?) {
        if player === newPlayer, timeObserver != nil { return }
        detach()
        currentTime = 0
        isPlaying = false
        guard let newPlayer else { return }
        player = newPlayer
        let identity = sessionIdentity
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.15, preferredTimescale: 600), queue: .main
        ) { [weak self, weak newPlayer] time in
            let seconds = time.seconds
            Task { @MainActor [weak self, weak newPlayer] in
                guard let self, let newPlayer else { return }
                self.receive(seconds: seconds, from: newPlayer, session: identity)
            }
        }
    }

    func detach() {
        // A queued tick can arrive after removal, including after the same
        // player is attached again. Invalidate its identity before removing it.
        sessionIdentity = UUID()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        isPlaying = false
    }

    func receive(seconds: Double, from source: AVPlayer, session: UUID) {
        guard session == sessionIdentity, player === source, timeObserver != nil else { return }
        // Inspection can still be loading when the observer attaches. Read the
        // player's time without clamping to an earlier zero-duration snapshot.
        if seconds.isFinite { currentTime = max(0, seconds) }
        isPlaying = source.timeControlStatus == .playing
    }
}
