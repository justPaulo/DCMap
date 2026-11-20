import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Colour tokens, mirroring the HTML version's dark and light themes.
struct Palette: Equatable {
    let dark: Bool

    var bg: Color { dark ? Color(hex: 0x0C1117) : Color(hex: 0xEEF2F6) }
    var panel: Color { dark ? Color(hex: 0x131A23) : .white }
    var panel2: Color { dark ? Color(hex: 0x18212C) : Color(hex: 0xF4F7FA) }
    var line: Color { dark ? Color(hex: 0x243041) : Color(hex: 0xD8E0E9) }
    var text: Color { dark ? Color(hex: 0xE6EDF5) : Color(hex: 0x15202C) }
    var muted: Color { dark ? Color(hex: 0x8A9AAE) : Color(hex: 0x5D6E82) }
    var ocean: Color { dark ? Color(hex: 0x0C1117) : Color(hex: 0xE4ECF4) }
    var land: Color { dark ? Color(hex: 0x1A2431) : Color(hex: 0xF8FAFC) }
    var landStroke: Color { dark ? Color(hex: 0x2A3748) : Color(hex: 0xC3CFDC) }
    var hasSite: Color { dark ? Color(hex: 0x23415A) : Color(hex: 0xBCD6EE) }
    var graticule: Color { dark ? Color(hex: 0x141D28) : Color(hex: 0xD7E2ED) }
    var dc: Color { dark ? Color(hex: 0x2FD4B5) : Color(hex: 0x0F9E86) }
    var dr: Color { dark ? Color(hex: 0xFFB347) : Color(hex: 0xD9820B) }
    var both: Color { dark ? Color(hex: 0x7AA7FF) : Color(hex: 0x3A6FE0) }
    var link: Color { dark ? Color(hex: 0x7AA7FF) : Color(hex: 0x3A6FE0) }
    var warn: Color { dark ? Color(hex: 0xFF7A7A) : Color(hex: 0xC93A3A) }
    var unlinked: Color { muted }

    func color(for role: SiteRole) -> Color {
        switch role {
        case .dc: return dc
        case .dr: return dr
        case .both: return both
        case .none: return unlinked
        }
    }
}

enum SiteRole {
    case dc, dr, both, none
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(dark: true)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Rounded "card" container used across the app.
struct Card<Content: View>: View {
    @Environment(\.palette) private var p
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.7)
                    .foregroundColor(p.muted)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(p.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.line, lineWidth: 1))
    }
}
