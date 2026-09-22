import SwiftUI

enum BrandColor {
    static let canvas = Color(red: 0.965, green: 0.972, blue: 0.984)
    static let surface = Color.white
    static let blue = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let bluePressed = Color(red: 0.118, green: 0.251, blue: 0.686)
    static let blueDisabled = Color(red: 0.663, green: 0.765, blue: 0.980)
    static let selectSurface = Color(red: 0.969, green: 0.976, blue: 0.992)
    static let selectHover = Color(red: 0.949, green: 0.965, blue: 1.000)
    static let selectStroke = Color(red: 0.843, green: 0.871, blue: 0.918)
    static let selectHoverStroke = Color(red: 0.569, green: 0.706, blue: 0.961)
    static let textPrimary = Color(red: 0.102, green: 0.114, blue: 0.149)
    static let textSecondary = Color(red: 0.400, green: 0.439, blue: 0.522)
    static let icon = Color(red: 0.294, green: 0.349, blue: 0.463)
    static let stroke = Color(red: 0.898, green: 0.914, blue: 0.941)
    static let tag = Color(red: 0.929, green: 0.945, blue: 0.976)
    static let success = Color(red: 0.090, green: 0.696, blue: 0.416)
    static let warning = Color(red: 0.902, green: 0.553, blue: 0.075)
    static let warningBackground = Color(red: 1.000, green: 0.968, blue: 0.894)
}

enum AppFont {
    static let body = Font.custom("NotoSansSC-Regular", size: 13)
    static let medium = Font.custom("NotoSansSC-Medium", size: 13)
    static let caption = Font.custom("NotoSansSC-Regular", size: 11)
    static let captionMedium = Font.custom("NotoSansSC-Medium", size: 11)
    static let section = Font.custom("NotoSansSC-Medium", size: 14)
    static let brand = Font.custom("NotoSansSC-Medium", size: 26)
    static let subtitle = Font.custom("NotoSansSC-Medium", size: 14)
    static let privacy = Font.custom("NotoSansSC-Medium", size: 13)
    static let headline = Font.custom("NotoSansSC-Medium", size: 16)
    static let rowTitle = Font.custom("NotoSansSC-Medium", size: 13)
    static let tag = Font.custom("NotoSansSC-Medium", size: 11)
}

enum MarkKind { case film, hardDrive, resolution, plus, bolt, shield, folder, trash, scissors, crop, rotate, chevron, ellipsis, info }

/// Original geometric marks drawn in SwiftUI; no third-party icon assets are used.
struct Mark: View {
    let kind: MarkKind
    var color: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = StrokeStyle(lineWidth: max(1.6, side * 0.085), lineCap: .round, lineJoin: .round)
            ZStack {
                switch kind {
                case .film:
                    RoundedRectangle(cornerRadius: side * 0.13, style: .continuous).stroke(color, style: line).padding(side * 0.08)
                    RoundedRectangle(cornerRadius: side * 0.03, style: .continuous).stroke(color, style: line).padding(.horizontal, side * 0.27).padding(.vertical, side * 0.34)
                    ForEach([-0.31, 0.31], id: \.self) { offset in
                        VStack(spacing: side * 0.07) {
                            ForEach(0..<3, id: \.self) { _ in Capsule().fill(color).frame(width: side * 0.085, height: side * 0.115) }
                        }.offset(x: side * offset)
                    }
                case .hardDrive:
                    RoundedRectangle(cornerRadius: side * 0.16, style: .continuous).stroke(color, style: line).padding(side * 0.10)
                    RoundedRectangle(cornerRadius: side * 0.035, style: .continuous).stroke(color, style: line).frame(width: side * 0.52, height: side * 0.20).offset(y: -side * 0.15)
                    HStack(spacing: side * 0.12) {
                        Circle().fill(color).frame(width: side * 0.10, height: side * 0.10)
                        Capsule().fill(color).frame(width: side * 0.26, height: side * 0.08)
                    }.offset(y: side * 0.25)
                case .resolution:
                    RoundedRectangle(cornerRadius: side * 0.12, style: .continuous).stroke(color, style: line).padding(side * 0.12)
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.30, y: side * 0.38)); path.addLine(to: CGPoint(x: side * 0.46, y: side * 0.38))
                        path.move(to: CGPoint(x: side * 0.30, y: side * 0.38)); path.addLine(to: CGPoint(x: side * 0.30, y: side * 0.54))
                        path.move(to: CGPoint(x: side * 0.70, y: side * 0.62)); path.addLine(to: CGPoint(x: side * 0.54, y: side * 0.62))
                        path.move(to: CGPoint(x: side * 0.70, y: side * 0.62)); path.addLine(to: CGPoint(x: side * 0.70, y: side * 0.46))
                    }.stroke(color, style: line)
                case .plus:
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.5, y: side * 0.18)); path.addLine(to: CGPoint(x: side * 0.5, y: side * 0.82))
                        path.move(to: CGPoint(x: side * 0.18, y: side * 0.5)); path.addLine(to: CGPoint(x: side * 0.82, y: side * 0.5))
                    }.stroke(color, style: line)
                case .bolt:
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.57, y: side * 0.06)); path.addLine(to: CGPoint(x: side * 0.20, y: side * 0.54))
                        path.addLine(to: CGPoint(x: side * 0.47, y: side * 0.54)); path.addLine(to: CGPoint(x: side * 0.40, y: side * 0.94))
                        path.addLine(to: CGPoint(x: side * 0.80, y: side * 0.40)); path.addLine(to: CGPoint(x: side * 0.53, y: side * 0.40)); path.closeSubpath()
                    }.fill(color)
                case .shield:
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.50, y: side * 0.08)); path.addLine(to: CGPoint(x: side * 0.82, y: side * 0.21)); path.addLine(to: CGPoint(x: side * 0.77, y: side * 0.62)); path.addLine(to: CGPoint(x: side * 0.50, y: side * 0.88)); path.addLine(to: CGPoint(x: side * 0.23, y: side * 0.62)); path.addLine(to: CGPoint(x: side * 0.18, y: side * 0.21)); path.closeSubpath()
                    }.stroke(color, style: line)
                    Circle().fill(color).frame(width: side * 0.12, height: side * 0.12)
                case .folder:
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.10, y: side * 0.30)); path.addLine(to: CGPoint(x: side * 0.42, y: side * 0.30)); path.addLine(to: CGPoint(x: side * 0.50, y: side * 0.20)); path.addLine(to: CGPoint(x: side * 0.72, y: side * 0.20)); path.addLine(to: CGPoint(x: side * 0.86, y: side * 0.34)); path.addLine(to: CGPoint(x: side * 0.86, y: side * 0.78)); path.addLine(to: CGPoint(x: side * 0.10, y: side * 0.78)); path.closeSubpath()
                    }.stroke(color, style: line)
                case .trash:
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.26, y: side * 0.27)); path.addLine(to: CGPoint(x: side * 0.31, y: side * 0.84)); path.addLine(to: CGPoint(x: side * 0.69, y: side * 0.84)); path.addLine(to: CGPoint(x: side * 0.74, y: side * 0.27))
                        path.move(to: CGPoint(x: side * 0.17, y: side * 0.27)); path.addLine(to: CGPoint(x: side * 0.83, y: side * 0.27))
                        path.move(to: CGPoint(x: side * 0.39, y: side * 0.17)); path.addLine(to: CGPoint(x: side * 0.61, y: side * 0.17))
                        path.move(to: CGPoint(x: side * 0.43, y: side * 0.42)); path.addLine(to: CGPoint(x: side * 0.43, y: side * 0.70))
                        path.move(to: CGPoint(x: side * 0.57, y: side * 0.42)); path.addLine(to: CGPoint(x: side * 0.57, y: side * 0.70))
                    }.stroke(color, style: line)
                case .scissors:
                    Circle().stroke(color, style: line).frame(width: side * 0.24, height: side * 0.24).offset(x: -side * 0.20, y: side * 0.22)
                    Circle().stroke(color, style: line).frame(width: side * 0.24, height: side * 0.24).offset(x: side * 0.20, y: side * 0.22)
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.38, y: side * 0.57)); path.addLine(to: CGPoint(x: side * 0.78, y: side * 0.17))
                        path.move(to: CGPoint(x: side * 0.62, y: side * 0.57)); path.addLine(to: CGPoint(x: side * 0.22, y: side * 0.17))
                    }.stroke(color, style: line)
                case .crop:
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.16, y: side * 0.36)); path.addLine(to: CGPoint(x: side * 0.16, y: side * 0.16)); path.addLine(to: CGPoint(x: side * 0.36, y: side * 0.16))
                        path.move(to: CGPoint(x: side * 0.64, y: side * 0.16)); path.addLine(to: CGPoint(x: side * 0.84, y: side * 0.16)); path.addLine(to: CGPoint(x: side * 0.84, y: side * 0.36))
                        path.move(to: CGPoint(x: side * 0.84, y: side * 0.64)); path.addLine(to: CGPoint(x: side * 0.84, y: side * 0.84)); path.addLine(to: CGPoint(x: side * 0.64, y: side * 0.84))
                        path.move(to: CGPoint(x: side * 0.36, y: side * 0.84)); path.addLine(to: CGPoint(x: side * 0.16, y: side * 0.84)); path.addLine(to: CGPoint(x: side * 0.16, y: side * 0.64))
                    }.stroke(color, style: line)
                case .rotate:
                    Path { path in
                        path.addArc(center: CGPoint(x: side * 0.5, y: side * 0.5), radius: side * 0.30, startAngle: .degrees(-55), endAngle: .degrees(235), clockwise: false)
                        path.move(to: CGPoint(x: side * 0.71, y: side * 0.16))
                        path.addLine(to: CGPoint(x: side * 0.81, y: side * 0.34))
                        path.addLine(to: CGPoint(x: side * 0.61, y: side * 0.31))
                    }.stroke(color, style: line)
                case .chevron:
                    Path { path in path.move(to: CGPoint(x: side * 0.20, y: side * 0.35)); path.addLine(to: CGPoint(x: side * 0.50, y: side * 0.65)); path.addLine(to: CGPoint(x: side * 0.80, y: side * 0.35)) }.stroke(color, style: line)
                case .ellipsis:
                    HStack(spacing: side * 0.12) { ForEach(0..<3, id: \.self) { _ in Circle().fill(color).frame(width: side * 0.14, height: side * 0.14) } }
                case .info:
                    Circle().fill(color)
                    Text("!").font(.system(size: side * 0.62, weight: .bold)).foregroundStyle(.white).offset(y: -side * 0.01)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct StatusMark: View {
    let state: ConversionState
    var body: some View {
        let color = state.color
        ZStack {
            Circle().stroke(color, lineWidth: 2)
            switch state {
            case .waiting:
                Path { path in path.move(to: CGPoint(x: 11, y: 5)); path.addLine(to: CGPoint(x: 11, y: 11)); path.addLine(to: CGPoint(x: 15, y: 14)) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case .running, .merging:
                Circle().trim(from: 0.12, to: 0.70).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            case .complete:
                Path { path in path.move(to: CGPoint(x: 5, y: 12)); path.addLine(to: CGPoint(x: 9, y: 16)); path.addLine(to: CGPoint(x: 18, y: 7)) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case .failed:
                Text("!").font(.system(size: 14, weight: .bold)).foregroundStyle(color)
            case .cancelled:
                Path { path in path.move(to: CGPoint(x: 7, y: 7)); path.addLine(to: CGPoint(x: 17, y: 17)); path.move(to: CGPoint(x: 17, y: 7)); path.addLine(to: CGPoint(x: 7, y: 17)) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
