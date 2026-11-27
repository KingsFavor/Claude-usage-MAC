import SwiftUI
import AppKit

// MARK: - Theme
// Warm-neutral palette shared with TaskOcean: off-white header/footer panels,
// white cards with hairline borders and soft shadows, ink-colored progress,
// low-saturation accents, quiet status dots. Resolved per color scheme.
struct Theme {
    let scheme: ColorScheme
    var isDark: Bool { scheme == .dark }

    // Surfaces
    var window: Color { isDark ? Color(hex: 0x1D1D1F) : Color(hex: 0xFFFFFF) }
    var chrome: Color { isDark ? Color(hex: 0x232325) : Color(hex: 0xF4F3F0) }   // header / footer band
    var card: Color { isDark ? Color(hex: 0x28282B) : Color(hex: 0xFFFFFF) }
    var panel: Color { isDark ? Color(hex: 0x2C2C2F) : Color(hex: 0xEDECE8) }    // controls on chrome
    var panelStrong: Color { isDark ? Color(hex: 0x3A3A3D) : Color(hex: 0xE6E5E1) }
    var track: Color { isDark ? Color(hex: 0x3A3A3D) : Color(hex: 0xEAE9E5) }
    var segmentOn: Color { isDark ? Color(hex: 0x3A3A3D) : Color(hex: 0xFFFFFF) }
    var infoSurface: Color { isDark ? Color(hex: 0x212123) : Color(hex: 0xFBFAF8) }

    // Lines
    var cardBorder: Color { isDark ? .white.opacity(0.05) : Color(hex: 0xF1F0ED) }
    var divider: Color { isDark ? .white.opacity(0.06) : Color(hex: 0xE7E6E2) }

    // Text
    var textPrimary: Color { isDark ? Color(hex: 0xF4F4F2) : Color(hex: 0x1B1B1A) }
    var textSecondary: Color { isDark ? Color(hex: 0x9A9A94) : Color(hex: 0x67665F) }
    var textMuted: Color { isDark ? Color(hex: 0x7D7D78) : Color(hex: 0xA6A5A1) }
    var textFaint: Color { isDark ? Color(hex: 0x565658) : Color(hex: 0xC9C8C4) }
    var icon: Color { isDark ? Color(hex: 0x8A8A85) : Color(hex: 0x8F8E8A) }

    // Ink (primary fill: progress, primary button)
    var ink: Color { isDark ? Color(hex: 0xF4F4F2) : Color(hex: 0x141413) }
    var onInk: Color { isDark ? Color(hex: 0x1D1D1F) : Color(hex: 0xFFFFFF) }

    // Semantic
    var ok: Color { Color(hex: 0x7BA86B) }
    var warn: Color { Color(hex: 0xC9A15B) }
    var danger: Color { Color(hex: 0xC1694F) }
    var accentBlue: Color { Color(hex: 0x5B7CA8) }
    var accentTan: Color { Color(hex: 0xB08363) }

    // Shape
    let cardRadius: CGFloat = 15
    let controlRadius: CGFloat = 9
    let chipRadius: CGFloat = 7

    /// Usage-level fill: ink while comfortable, warm amber/terracotta near the cap.
    func levelColor(_ pct: Double) -> Color {
        switch pct {
        case ..<70: return ink
        case ..<90: return warn
        default:    return danger
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(scheme: .light)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Resolves the theme from the live color scheme and injects it.
struct Themed<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View { content.environment(\.theme, Theme(scheme: scheme)) }
}

// MARK: - Card
struct CardModifier: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                .stroke(theme.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(theme.isDark ? 0 : 0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(theme.isDark ? 0 : 0.10), radius: 8, y: 5)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

// MARK: - Wordmark
/// App glyph + "Claude Usage" in serif italic (TaskOcean-style wordmark).
struct Wordmark: View {
    var size: CGFloat = 15
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size + 5, height: size + 5)
            Text("Claude Usage")
                .font(.system(size: size, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(theme.textPrimary)
                .fixedSize()
        }
    }
}

// MARK: - Section label ("주간 한도  2")
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(theme.textMuted)
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

// MARK: - Segmented pills (TaskOcean's 미니/컴팩트/확장 switch)
struct Segmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var fontSize: CGFloat = 10
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                let on = opt.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = opt.value }
                } label: {
                    Text(opt.label)
                        .font(.system(size: fontSize, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? theme.textPrimary : theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(theme.segmentOn)
                                    .shadow(color: .black.opacity(theme.isDark ? 0.25 : 0.08), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
    }
}

// MARK: - Chip
struct Chip: View {
    let text: String
    var color: Color? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(color ?? theme.textPrimary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(theme.panelStrong, in: RoundedRectangle(cornerRadius: theme.chipRadius, style: .continuous))
            .fixedSize()
    }
}

// MARK: - Progress bar (ink fill on a warm track)
struct InkBar: View {
    let fraction: Double
    var color: Color
    var height: CGFloat = 6
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: fraction <= 0 ? 0 : max(height, geo.size.width * min(fraction, 1)))
                    .animation(.snappy(duration: 0.4), value: fraction)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Icon button on the chrome bands
struct ChromeIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hover ? theme.textPrimary : theme.icon)
                .frame(width: 26, height: 26)
                .background(hover ? theme.panel : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Account avatar (initial on an accent circle)
struct Avatar: View {
    let text: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        Text(String(text.prefix(1)).uppercased())
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}

// MARK: - Status dot
struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}
