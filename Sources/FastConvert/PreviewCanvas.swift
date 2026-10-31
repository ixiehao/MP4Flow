import AppKit
import AVFoundation
import QuartzCore
import SwiftUI

/// A transparent video surface: unused canvas space belongs to the editor,
/// while black pixels that are part of the video remain untouched.
struct NativeVideoPreview: NSViewRepresentable {
    let player: AVPlayer?
    var stretches = false

    func makeNSView(context: Context) -> VideoPreviewLayerView {
        let view = VideoPreviewLayerView(frame: .zero)
        view.update(player: player, stretches: stretches)
        return view
    }

    func updateNSView(_ view: VideoPreviewLayerView, context: Context) {
        view.update(player: player, stretches: stretches)
    }

    static func dismantleNSView(_ view: VideoPreviewLayerView, coordinator: ()) {
        // The editor owns playback. Release only this surface's reference;
        // do not pause another surface sharing the same player.
        view.playerLayer.player = nil
    }
}

final class VideoPreviewLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false
        layer?.addSublayer(playerLayer)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }

    func update(player: AVPlayer?, stretches: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if playerLayer.player !== player { playerLayer.player = player }
        let gravity: AVLayerVideoGravity = stretches ? .resize : .resizeAspect
        if playerLayer.videoGravity != gravity { playerLayer.videoGravity = gravity }
        if playerLayer.frame != bounds { playerLayer.frame = bounds }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct PreviewCanvasStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        content
            .background {
                shape.fill(LinearGradient(
                    colors: [BrandColor.tag, BrandColor.canvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(BrandColor.selectStroke.opacity(0.8), lineWidth: 1) }
    }
}

extension View {
    /// Shared by every editor; no padding changes the crop or preview geometry.
    func previewCanvas() -> some View { modifier(PreviewCanvasStyle()) }
}
