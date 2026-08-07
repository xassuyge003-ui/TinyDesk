import AppKit
import SwiftUI
import TinyDeskCore

/// 以 #RRGGBB 字符串构造 SwiftUI 颜色（标签色等）。
extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.removeFirst(cleaned.hasPrefix("#") ? 1 : 0)
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

private struct LibraryPaperThemeKey: EnvironmentKey {
    static let defaultValue: PaperTheme = .suJian
}

extension EnvironmentValues {
    var libraryPaperTheme: PaperTheme {
        get { self[LibraryPaperThemeKey.self] }
        set { self[LibraryPaperThemeKey.self] = newValue }
    }
}

enum LibraryTypography {
    static func title(_ size: CGFloat) -> Font {
        NSFont(name: "STFangsong", size: size) != nil
            ? .custom("STFangsong", size: size)
            : .system(size: size, weight: .semibold)
    }

    static func label(_ size: CGFloat = 13) -> Font {
        NSFont(name: "STSongti-SC", size: size) != nil
            ? .custom("STSongti-SC", size: size)
            : .system(size: size)
    }
}

extension PaperTheme {
    var symbolName: String {
        switch self {
        case .suJian: return "doc.plaintext"
        case .xuanZhi: return "mountain.2"
        case .zhuJian: return "leaf"
        case .moQing: return "drop.halffull"
        case .zhuSha: return "seal"
        case .yeMo: return "moon.stars"
        case .meiYing: return "sparkles"
        case .qingHua: return "leaf.circle"
        case .lanTing: return "building.columns"
        case .dunHuang: return "wind"
        case .songYan: return "tree"
        case .yunJin: return "cloud"
        }
    }
}

/// 古风纸张主题的视觉定义与 SwiftUI 渲染。
struct PaperThemeStyle {
    let backgroundColor: NSColor
    let textColor: NSColor
    let accentColor: NSColor

    static func style(for theme: PaperTheme) -> PaperThemeStyle {
        switch theme {
        case .suJian:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1),
                textColor: NSColor(red: 0.23, green: 0.20, blue: 0.16, alpha: 1),
                accentColor: NSColor(red: 0.55, green: 0.45, blue: 0.30, alpha: 1)
            )
        case .xuanZhi:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.95, green: 0.91, blue: 0.83, alpha: 1),
                textColor: NSColor(red: 0.18, green: 0.14, blue: 0.09, alpha: 1),
                accentColor: NSColor(red: 0.47, green: 0.36, blue: 0.22, alpha: 1)
            )
        case .zhuJian:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.83, green: 0.77, blue: 0.63, alpha: 1),
                textColor: NSColor(red: 0.24, green: 0.19, blue: 0.13, alpha: 1),
                accentColor: NSColor(red: 0.42, green: 0.32, blue: 0.18, alpha: 1)
            )
        case .moQing:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.17, green: 0.24, blue: 0.31, alpha: 1),
                textColor: NSColor(red: 0.84, green: 0.87, blue: 0.89, alpha: 1),
                accentColor: NSColor(red: 0.68, green: 0.75, blue: 0.80, alpha: 1)
            )
        case .zhuSha:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.94, green: 0.88, blue: 0.82, alpha: 1),
                textColor: NSColor(red: 0.36, green: 0.12, blue: 0.12, alpha: 1),
                accentColor: NSColor(red: 0.55, green: 0.20, blue: 0.18, alpha: 1)
            )
        case .yeMo:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1),
                textColor: NSColor(red: 0.86, green: 0.80, blue: 0.62, alpha: 1),
                accentColor: NSColor(red: 0.75, green: 0.66, blue: 0.42, alpha: 1)
            )
        case .meiYing:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.97, green: 0.93, blue: 0.89, alpha: 1),
                textColor: NSColor(red: 0.28, green: 0.18, blue: 0.17, alpha: 1),
                accentColor: NSColor(red: 0.57, green: 0.19, blue: 0.22, alpha: 1)
            )
        case .qingHua:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.94, green: 0.95, blue: 0.92, alpha: 1),
                textColor: NSColor(red: 0.12, green: 0.20, blue: 0.27, alpha: 1),
                accentColor: NSColor(red: 0.11, green: 0.32, blue: 0.48, alpha: 1)
            )
        case .lanTing:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.91, green: 0.90, blue: 0.84, alpha: 1),
                textColor: NSColor(red: 0.16, green: 0.18, blue: 0.16, alpha: 1),
                accentColor: NSColor(red: 0.26, green: 0.36, blue: 0.33, alpha: 1)
            )
        case .dunHuang:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.87, green: 0.76, blue: 0.58, alpha: 1),
                textColor: NSColor(red: 0.25, green: 0.15, blue: 0.10, alpha: 1),
                accentColor: NSColor(red: 0.56, green: 0.20, blue: 0.16, alpha: 1)
            )
        case .songYan:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.12, green: 0.19, blue: 0.17, alpha: 1),
                textColor: NSColor(red: 0.84, green: 0.84, blue: 0.72, alpha: 1),
                accentColor: NSColor(red: 0.60, green: 0.67, blue: 0.50, alpha: 1)
            )
        case .yunJin:
            return PaperThemeStyle(
                backgroundColor: NSColor(red: 0.31, green: 0.08, blue: 0.09, alpha: 1),
                textColor: NSColor(red: 0.93, green: 0.82, blue: 0.57, alpha: 1),
                accentColor: NSColor(red: 0.86, green: 0.64, blue: 0.31, alpha: 1)
            )
        }
    }

    var textColorSwiftUI: Color { Color(nsColor: textColor) }
    var backgroundColorSwiftUI: Color { Color(nsColor: backgroundColor) }
    var accentColorSwiftUI: Color { Color(nsColor: accentColor) }

    var isDark: Bool {
        guard let color = backgroundColor.usingColorSpace(.sRGB) else { return false }
        return 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent < 0.46
    }
}

/// 纸张背景：基色、纸张肌理和国风纹样。正文区域不再绘制横向行线。
struct PaperBackground: View {
    let theme: PaperTheme
    var showsOrnament = true

    private var style: PaperThemeStyle { .style(for: theme) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(style.backgroundColorSwiftUI)
                .overlay(texture)
            if showsOrnament {
                PaperOrnament(theme: theme)
            }
        }
    }

    @ViewBuilder
    private var texture: some View {
        switch theme {
        case .suJian, .meiYing:
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.brown.opacity(0.035), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .xuanZhi, .lanTing:
            RadialGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.brown.opacity(0.055),
                    .clear,
                ],
                center: UnitPoint(x: 0.3, y: 0.2),
                startRadius: 0,
                endRadius: 600
            )
        case .zhuJian:
            LinearGradient(
                colors: [
                    Color.brown.opacity(0.16),
                    Color.brown.opacity(0.06),
                    Color.brown.opacity(0.16),
                    Color.brown.opacity(0.06),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .moQing, .yeMo, .songYan, .yunJin:
            RadialGradient(
                colors: [
                    style.accentColorSwiftUI.opacity(0.10),
                    .clear,
                ],
                center: UnitPoint(x: 0.78, y: 0.14),
                startRadius: 0,
                endRadius: 500
            )
        case .zhuSha:
            LinearGradient(
                colors: [Color.red.opacity(0.04), .clear, Color.brown.opacity(0.035)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        case .qingHua:
            RadialGradient(
                colors: [Color.blue.opacity(0.035), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
        case .dunHuang:
            LinearGradient(
                colors: [Color.orange.opacity(0.07), Color.yellow.opacity(0.04), Color.red.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// 纯 SwiftUI 矢量纹样，不携带第三方图片资源，可随窗口尺寸无损缩放。
private struct PaperOrnament: View {
    let theme: PaperTheme

    private var style: PaperThemeStyle { .style(for: theme) }

    var body: some View {
        Canvas { context, size in
            let accent = Color(nsColor: style.accentColor)
            switch theme {
            case .suJian:
                Self.drawNamedSeal("笺", in: &context, size: size, color: accent.opacity(0.12))
            case .xuanZhi:
                Self.drawMountains(in: &context, size: size, color: accent.opacity(0.09))
                Self.drawPavilion(in: &context, size: size, color: accent.opacity(0.12))
            case .zhuJian:
                Self.drawBamboo(in: &context, size: size, color: accent.opacity(0.13))
            case .moQing:
                Self.drawOrchid(in: &context, size: size, color: accent.opacity(0.18))
            case .zhuSha:
                Self.drawNamedSeal("朱", in: &context, size: size, color: accent.opacity(0.20))
            case .yeMo:
                Self.drawMoon(in: &context, size: size, color: accent.opacity(0.22))
                Self.drawMountains(in: &context, size: size, color: accent.opacity(0.09))
            case .meiYing:
                Self.drawPlum(in: &context, size: size, color: accent.opacity(0.20))
            case .qingHua:
                Self.drawLotus(in: &context, size: size, color: accent.opacity(0.19))
            case .lanTing:
                Self.drawMountains(in: &context, size: size, color: accent.opacity(0.15))
                Self.drawPavilion(in: &context, size: size, color: accent.opacity(0.17))
                Self.drawNamedSeal("兰", in: &context, size: size, color: Color.red.opacity(0.13))
            case .dunHuang:
                Self.drawLotus(in: &context, size: size, color: accent.opacity(0.18))
                Self.drawRibbon(in: &context, size: size, color: accent.opacity(0.14))
            case .songYan:
                Self.drawPine(in: &context, size: size, color: accent.opacity(0.19))
            case .yunJin:
                Self.drawCloud(in: &context, size: size, color: accent.opacity(0.20))
                Self.drawNamedSeal("锦", in: &context, size: size, color: accent.opacity(0.12))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func stroke(
        _ path: Path,
        in context: inout GraphicsContext,
        color: Color,
        width: CGFloat = 1
    ) {
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    private static func drawNamedSeal(
        _ character: String,
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let side = min(72, max(38, min(size.width, size.height) * 0.12))
        let rect = CGRect(x: size.width - side - 28, y: size.height - side - 24, width: side, height: side)
        stroke(Path(rect), in: &context, color: color, width: 2)
        let sealText = context.resolve(
            Text(character)
                .font(.custom("STFangsong", size: side * 0.56))
                .foregroundColor(color)
        )
        context.draw(sealText, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    private static func drawMountains(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let baseline = size.height - 22
        var far = Path()
        far.move(to: CGPoint(x: 0, y: baseline))
        far.addCurve(
            to: CGPoint(x: size.width * 0.42, y: baseline - 34),
            control1: CGPoint(x: size.width * 0.16, y: baseline - 3),
            control2: CGPoint(x: size.width * 0.27, y: baseline - 54)
        )
        far.addCurve(
            to: CGPoint(x: size.width, y: baseline - 12),
            control1: CGPoint(x: size.width * 0.62, y: baseline - 66),
            control2: CGPoint(x: size.width * 0.78, y: baseline + 6)
        )
        far.addLine(to: CGPoint(x: size.width, y: size.height))
        far.addLine(to: CGPoint(x: 0, y: size.height))
        far.closeSubpath()
        context.fill(far, with: .color(color))

        var ridge = Path()
        ridge.move(to: CGPoint(x: size.width * 0.05, y: baseline))
        ridge.addCurve(
            to: CGPoint(x: size.width * 0.58, y: baseline - 18),
            control1: CGPoint(x: size.width * 0.24, y: baseline - 50),
            control2: CGPoint(x: size.width * 0.38, y: baseline + 4)
        )
        ridge.addCurve(
            to: CGPoint(x: size.width * 0.94, y: baseline - 8),
            control1: CGPoint(x: size.width * 0.72, y: baseline - 42),
            control2: CGPoint(x: size.width * 0.82, y: baseline + 2)
        )
        stroke(ridge, in: &context, color: color, width: 1.2)
    }

    private static func drawBamboo(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let x = size.width - 54
        var stem = Path()
        stem.move(to: CGPoint(x: x, y: size.height + 6))
        stem.addCurve(
            to: CGPoint(x: x - 10, y: max(36, size.height * 0.20)),
            control1: CGPoint(x: x + 8, y: size.height * 0.70),
            control2: CGPoint(x: x - 18, y: size.height * 0.43)
        )
        stroke(stem, in: &context, color: color, width: 3)
        for offset in stride(from: CGFloat(0.28), through: 0.78, by: 0.16) {
            let y = size.height * offset
            var leaf = Path()
            leaf.move(to: CGPoint(x: x - 7, y: y))
            leaf.addCurve(
                to: CGPoint(x: x - 42, y: y - 19),
                control1: CGPoint(x: x - 20, y: y - 2),
                control2: CGPoint(x: x - 30, y: y - 17)
            )
            leaf.addCurve(
                to: CGPoint(x: x - 7, y: y),
                control1: CGPoint(x: x - 27, y: y - 8),
                control2: CGPoint(x: x - 17, y: y + 1)
            )
            context.fill(leaf, with: .color(color))
        }
    }

    private static func drawMoon(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let diameter = min(130, max(68, min(size.width, size.height) * 0.20))
        let rect = CGRect(x: size.width - diameter - 34, y: 26, width: diameter, height: diameter)
        context.fill(Path(ellipseIn: rect), with: .color(color))
        let cutout = rect.offsetBy(dx: diameter * 0.18, dy: -diameter * 0.08)
        context.blendMode = .destinationOut
        context.fill(Path(ellipseIn: cutout), with: .color(.black))
        context.blendMode = .normal
    }

    private static func drawPlum(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        var branch = Path()
        branch.move(to: CGPoint(x: size.width + 8, y: 42))
        branch.addCurve(
            to: CGPoint(x: max(28, size.width - 190), y: 132),
            control1: CGPoint(x: size.width - 62, y: 47),
            control2: CGPoint(x: size.width - 118, y: 108)
        )
        stroke(branch, in: &context, color: color, width: 3)
        let centers = [
            CGPoint(x: size.width - 44, y: 54),
            CGPoint(x: size.width - 88, y: 79),
            CGPoint(x: size.width - 132, y: 110),
        ]
        for center in centers {
            for index in 0..<5 {
                let angle = Double(index) * .pi * 2 / 5
                let petal = CGRect(
                    x: center.x + cos(angle) * 10 - 4,
                    y: center.y + sin(angle) * 10 - 4,
                    width: 9,
                    height: 9
                )
                context.fill(Path(ellipseIn: petal), with: .color(color))
            }
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)),
                with: .color(color)
            )
        }
    }

    private static func drawOrchid(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let root = CGPoint(x: size.width - 66, y: size.height - 28)
        for index in 0..<5 {
            let offset = CGFloat(index - 2) * 8
            var leaf = Path()
            leaf.move(to: root)
            leaf.addCurve(
                to: CGPoint(x: root.x + offset * 4, y: max(54, size.height * 0.38)),
                control1: CGPoint(x: root.x + offset, y: size.height * 0.78),
                control2: CGPoint(x: root.x + offset * 5, y: size.height * 0.56)
            )
            stroke(leaf, in: &context, color: color, width: index == 2 ? 2 : 1.4)
        }

        let flowers = [
            CGPoint(x: size.width - 118, y: max(72, size.height * 0.36)),
            CGPoint(x: size.width - 70, y: max(46, size.height * 0.29)),
        ]
        for center in flowers {
            for index in 0..<3 {
                let angle = Double(index) * .pi * 2 / 3 - .pi / 2
                let petal = CGRect(
                    x: center.x + cos(angle) * 8 - 4,
                    y: center.y + sin(angle) * 8 - 6,
                    width: 8,
                    height: 13
                )
                context.fill(Path(ellipseIn: petal), with: .color(color))
            }
        }
    }

    private static func drawPavilion(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let centerX = size.width * 0.72
        let baseY = size.height - 34
        var roof = Path()
        roof.move(to: CGPoint(x: centerX - 42, y: baseY - 36))
        roof.addCurve(
            to: CGPoint(x: centerX, y: baseY - 56),
            control1: CGPoint(x: centerX - 24, y: baseY - 36),
            control2: CGPoint(x: centerX - 13, y: baseY - 54)
        )
        roof.addCurve(
            to: CGPoint(x: centerX + 42, y: baseY - 36),
            control1: CGPoint(x: centerX + 13, y: baseY - 54),
            control2: CGPoint(x: centerX + 24, y: baseY - 36)
        )
        stroke(roof, in: &context, color: color, width: 2)

        var frame = Path()
        frame.move(to: CGPoint(x: centerX - 28, y: baseY - 34))
        frame.addLine(to: CGPoint(x: centerX - 24, y: baseY))
        frame.move(to: CGPoint(x: centerX + 28, y: baseY - 34))
        frame.addLine(to: CGPoint(x: centerX + 24, y: baseY))
        frame.move(to: CGPoint(x: centerX - 34, y: baseY))
        frame.addLine(to: CGPoint(x: centerX + 34, y: baseY))
        stroke(frame, in: &context, color: color, width: 1.5)
    }

    private static func drawLotus(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let center = CGPoint(x: size.width - 82, y: 88)
        for index in 0..<7 {
            let angle = Double(index - 3) * 0.28 - .pi / 2
            let tip = CGPoint(
                x: center.x + cos(angle) * 42,
                y: center.y + sin(angle) * 42
            )
            var petal = Path()
            petal.move(to: center)
            petal.addCurve(
                to: tip,
                control1: CGPoint(x: center.x - 15 + CGFloat(index) * 4, y: center.y - 18),
                control2: CGPoint(x: tip.x - 9, y: tip.y + 13)
            )
            petal.addCurve(
                to: center,
                control1: CGPoint(x: tip.x + 9, y: tip.y + 13),
                control2: CGPoint(x: center.x + 15 - CGFloat(index) * 4, y: center.y - 18)
            )
            context.fill(petal, with: .color(color))
        }

        var stem = Path()
        stem.move(to: CGPoint(x: center.x, y: center.y + 2))
        stem.addCurve(
            to: CGPoint(x: center.x - 18, y: size.height * 0.58),
            control1: CGPoint(x: center.x + 8, y: center.y + 48),
            control2: CGPoint(x: center.x - 20, y: size.height * 0.42)
        )
        stroke(stem, in: &context, color: color, width: 1.5)

        let leafRect = CGRect(x: center.x - 82, y: size.height * 0.48, width: 74, height: 30)
        context.fill(Path(ellipseIn: leafRect), with: .color(color.opacity(0.72)))
    }

    private static func drawRibbon(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: size.width - 22, y: 34))
        ribbon.addCurve(
            to: CGPoint(x: size.width - 182, y: 172),
            control1: CGPoint(x: size.width - 126, y: 22),
            control2: CGPoint(x: size.width - 62, y: 152)
        )
        ribbon.addCurve(
            to: CGPoint(x: size.width - 44, y: 244),
            control1: CGPoint(x: size.width - 260, y: 194),
            control2: CGPoint(x: size.width - 144, y: 270)
        )
        stroke(ribbon, in: &context, color: color, width: 2)
    }

    private static func drawPine(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        var branch = Path()
        branch.move(to: CGPoint(x: size.width + 8, y: 34))
        branch.addCurve(
            to: CGPoint(x: max(20, size.width - 220), y: 138),
            control1: CGPoint(x: size.width - 72, y: 48),
            control2: CGPoint(x: size.width - 126, y: 116)
        )
        stroke(branch, in: &context, color: color, width: 4)
        for cluster in 0..<5 {
            let origin = CGPoint(x: size.width - 45 - CGFloat(cluster) * 35, y: 54 + CGFloat(cluster) * 19)
            for needle in -4...4 {
                let angle = CGFloat(needle) * 0.15 - 0.8
                var path = Path()
                path.move(to: origin)
                path.addLine(to: CGPoint(x: origin.x + cos(angle) * 38, y: origin.y + sin(angle) * 38))
                stroke(path, in: &context, color: color, width: 1)
            }
        }
    }

    private static func drawCloud(
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let center = CGPoint(x: size.width - 112, y: size.height - 92)
        var cloud = Path()
        cloud.move(to: CGPoint(x: center.x - 88, y: center.y + 16))
        cloud.addCurve(
            to: CGPoint(x: center.x - 34, y: center.y + 4),
            control1: CGPoint(x: center.x - 78, y: center.y - 10),
            control2: CGPoint(x: center.x - 48, y: center.y - 12)
        )
        cloud.addCurve(
            to: CGPoint(x: center.x + 8, y: center.y - 12),
            control1: CGPoint(x: center.x - 30, y: center.y - 28),
            control2: CGPoint(x: center.x - 2, y: center.y - 34)
        )
        cloud.addCurve(
            to: CGPoint(x: center.x + 58, y: center.y + 2),
            control1: CGPoint(x: center.x + 18, y: center.y - 34),
            control2: CGPoint(x: center.x + 52, y: center.y - 25)
        )
        cloud.addCurve(
            to: CGPoint(x: center.x + 88, y: center.y + 17),
            control1: CGPoint(x: center.x + 66, y: center.y - 2),
            control2: CGPoint(x: center.x + 82, y: center.y + 5)
        )
        cloud.addLine(to: CGPoint(x: center.x - 4, y: center.y + 17))
        cloud.addCurve(
            to: CGPoint(x: center.x + 24, y: center.y + 6),
            control1: CGPoint(x: center.x + 8, y: center.y + 17),
            control2: CGPoint(x: center.x + 26, y: center.y + 18)
        )
        cloud.addCurve(
            to: CGPoint(x: center.x + 4, y: center.y + 2),
            control1: CGPoint(x: center.x + 23, y: center.y - 3),
            control2: CGPoint(x: center.x + 10, y: center.y - 5)
        )
        stroke(cloud, in: &context, color: color, width: 2)
    }
}

/// 纸张主题的缩略色块，用于工具栏与文档列表。
struct PaperThemeSwatch: View {
    let theme: PaperTheme

    var body: some View {
        let style = PaperThemeStyle.style(for: theme)
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(style.backgroundColorSwiftUI)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(style.accentColorSwiftUI.opacity(0.6), lineWidth: 1)
            }
            .frame(width: 24, height: 20)
            .overlay {
                Image(systemName: theme.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.accentColorSwiftUI)
            }
            .accessibilityLabel(theme.displayName)
    }
}
