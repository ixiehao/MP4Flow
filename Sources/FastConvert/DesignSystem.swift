import AppKit
import SwiftUI

enum BrandColor {
    static let canvas = Color(red: 0.963, green: 0.971, blue: 0.986)
    static let surface = Color.white
    static let blue = Color(red: 0.137, green: 0.376, blue: 0.900)
    static let bluePressed = Color(red: 0.102, green: 0.259, blue: 0.686)
    static let blueDisabled = Color(red: 0.663, green: 0.765, blue: 0.980)
    static let selectSurface = Color(red: 0.969, green: 0.976, blue: 0.992)
    static let selectHover = Color(red: 0.949, green: 0.965, blue: 1.000)
    static let selectStroke = Color(red: 0.843, green: 0.871, blue: 0.918)
    static let selectHoverStroke = Color(red: 0.569, green: 0.706, blue: 0.961)
    static let textPrimary = Color(red: 0.102, green: 0.114, blue: 0.149)
    static let textSecondary = Color(red: 0.400, green: 0.439, blue: 0.522)
    static let icon = Color(red: 0.294, green: 0.349, blue: 0.463)
    static let stroke = Color(red: 0.878, green: 0.902, blue: 0.937)
    static let tag = Color(red: 0.929, green: 0.945, blue: 0.976)
    static let success = Color(red: 0.090, green: 0.696, blue: 0.416)
    static let warning = Color(red: 0.902, green: 0.553, blue: 0.075)
    static let warningBackground = Color(red: 1.000, green: 0.968, blue: 0.894)
}

enum AppFont {
    static let body = Font.system(size: 13, weight: .regular)
    static let medium = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let section = Font.system(size: 14, weight: .medium)
    static let brand = Font.system(size: 26, weight: .medium)
    static let subtitle = Font.system(size: 14, weight: .medium)
    static let privacy = Font.system(size: 13, weight: .medium)
    static let headline = Font.system(size: 16, weight: .medium)
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let tag = Font.system(size: 11, weight: .medium)
}

enum TablerIconName: String {
    case video, database, aspectRatio = "aspect-ratio", plus, bolt
    case shieldCheck = "shield-check", healthCheck = "activity-heartbeat", refresh
    case folder, trash, scissors, crop, rotate
    case chevronDown = "chevron-down", infoCircle = "info-circle"
    case clock, loader2 = "loader-2", circleCheck = "circle-check"
    case alertCircle = "alert-circle", circleX = "circle-x", language, check
    case playerPlay = "player-play", playerPause = "player-pause"
    case playerSkipBack = "player-skip-back", playerSkipForward = "player-skip-forward"
    case volume, download, externalLink = "external-link"
}

/// Curated Tabler Icons Outline assets (24 px grid, 2 px stroke) are retained
/// as SVG resources, so they stay sharp at every macOS display scale.
struct TablerIcon: View {
    let name: TablerIconName
    var color: Color = .primary

    var body: some View {
        if let image = TablerIconLibrary.image(named: name) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }
}

private enum TablerIconLibrary {
    private static var cache: [TablerIconName: NSImage] = [:]

    static func image(named name: TablerIconName) -> NSImage? {
        if let image = cache[name] { return image }
        guard let url = Bundle.module.url(forResource: name.rawValue, withExtension: "svg", subdirectory: "TablerOutline"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }
}

enum MarkKind { case film, hardDrive, resolution, plus, bolt, shield, healthCheck, refresh, folder, trash, scissors, crop, rotate, chevron }

/// Compatibility wrapper for the existing UI. Every mark now resolves to the
/// same Tabler Outline family rather than a mixture of hand-drawn marks.
struct Mark: View {
    let kind: MarkKind
    var color: Color = .primary

    private var icon: TablerIconName {
        switch kind {
        case .film: .video
        case .hardDrive: .database
        case .resolution: .aspectRatio
        case .plus: .plus
        case .bolt: .bolt
        case .shield: .shieldCheck
        case .healthCheck: .healthCheck
        case .refresh: .refresh
        case .folder: .folder
        case .trash: .trash
        case .scissors: .scissors
        case .crop: .crop
        case .rotate: .rotate
        case .chevron: .chevronDown
        }
    }

    var body: some View { TablerIcon(name: icon, color: color) }
}

struct StatusMark: View {
    let state: ConversionState

    private var icon: TablerIconName {
        switch state {
        case .waiting: .clock
        case .running, .merging: .loader2
        case .complete: .circleCheck
        case .failed: .alertCircle
        case .cancelled: .circleX
        }
    }

    var body: some View {
        TablerIcon(name: icon, color: state.color)
            .rotationEffect(isLoading ? .degrees(-70) : .zero)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }

    private var isLoading: Bool {
        if case .running = state { return true }
        if case .merging = state { return true }
        return false
    }
}
