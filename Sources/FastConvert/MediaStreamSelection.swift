import AVFoundation

/// A video codec alone does not identify a movie: demuxers also expose cover
/// art and thumbnail images as video streams. Never infer this from the codec
/// (MJPEG, for example, can be a real camera recording).
struct MediaStreamDisposition: Decodable, Hashable, Sendable {
    let attachedPicture: Int?
    let timedThumbnails: Int?

    enum CodingKeys: String, CodingKey {
        case attachedPicture = "attached_pic"
        case timedThumbnails = "timed_thumbnails"
    }

    var isAuxiliaryImage: Bool {
        (attachedPicture ?? 0) != 0 || (timedThumbnails ?? 0) != 0
    }
}

/// Concat matches streams by position. Equal video geometry is insufficient
/// when a cover, audio track or second video shifts those positions.
struct MediaStreamLayout: Hashable, Sendable {
    let index: Int?
    let type: String?
    let codec: String?
    let isAuxiliaryImage: Bool
}

enum NativeVideoTrackSelection {
    static func select(from asset: AVAsset, trackID: CMPersistentTrackID?) async throws -> AVAssetTrack? {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        if let trackID {
            return tracks.first { $0.trackID == trackID }
        }
        // Without a container track ID, more than one native video track is
        // ambiguous. Refuse rather than export a different track by accident.
        return tracks.count == 1 ? tracks.first : nil
    }
}
