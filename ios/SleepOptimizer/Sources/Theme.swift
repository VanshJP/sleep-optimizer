import SwiftUI
import SleepEngine

// MARK: - Palette
//
// Colours ported from the web app's globals.css so the iOS app reads as the
// same product. Below the raw tokens we layer a small design system —
// spacing/radius tokens, gradients, a card surface, and reusable section
// chrome — so screens stay visually consistent without repeating modifiers.
enum Palette {
    static let bg = Color(hex: 0x0b0e1a)
    static let bg2 = Color(hex: 0x111733)
    static let card = Color(hex: 0x141a2e)
    static let cardHi = Color(hex: 0x1b2342)
    static let text = Color(hex: 0xeaedf9)
    static let faint = Color(hex: 0x5f6890)
    static let ice = Color(hex: 0x93d8f5)
    static let iceDeep = Color(hex: 0x4f9fd8)
    static let ember = Color(hex: 0xd97f4e)
    static let amber = Color(hex: 0xf0a868)
    static let mint = Color(hex: 0x5fd3b2)

    static let deep = Color(hex: 0x4d74e0)
    static let rem = Color(hex: 0xa87be8)
    static let light = Color(hex: 0x4fb8ac)
    static let awake = Color(hex: 0xd97f4e)

    /// Hairline used for card borders and dividers on the dark surface.
    static let hairline = Color.white.opacity(0.06)

    // Gradients --------------------------------------------------------------

    /// Full-screen background: a deep night sky with a faint glow up top.
    static let screen = LinearGradient(
        colors: [Color(hex: 0x0c1024), Color(hex: 0x080a16)],
        startPoint: .top, endPoint: .bottom)

    static let iceGradient = LinearGradient(
        colors: [ice, iceDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let emberGradient = LinearGradient(
        colors: [amber, ember], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Spacing / radius tokens

enum Metric {
    static let gap: CGFloat = 16
    static let smallGap: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 18
    static let pillRadius: CGFloat = 12
}

// MARK: - Card surface

private struct CardSurface: ViewModifier {
    var padding: CGFloat
    var highlighted: Bool
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Palette.cardHi : Palette.card,
                        in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

extension View {
    /// Standard raised card surface used across the app.
    func card(padding: CGFloat = Metric.cardPadding, highlighted: Bool = false) -> some View {
        modifier(CardSurface(padding: padding, highlighted: highlighted))
    }
}

// MARK: - Section header

/// Consistent card section title: small accent icon + heading.
struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = Palette.ice
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Palette.text)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

/// Small rounded stat chip ("2h 14m restorative").
struct MetricChip: View {
    let value: String
    let label: String
    var accent: Color = Palette.ice
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(accent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Palette.faint)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Metric.pillRadius, style: .continuous))
    }
}

// MARK: - Sleep stage presentation

extension SleepStage {
    var color: Color {
        switch self {
        case .deep: return Palette.deep
        case .rem: return Palette.rem
        case .light: return Palette.light
        case .awake: return Palette.awake
        }
    }
    var label: String {
        switch self {
        case .deep: return "Deep"
        case .rem: return "REM"
        case .light: return "Light"
        case .awake: return "Awake"
        }
    }
    /// Vertical lane in the hypnogram, 0 = most awake (top), 3 = deep (bottom).
    var depthLane: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .light: return 2
        case .deep: return 3
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}
