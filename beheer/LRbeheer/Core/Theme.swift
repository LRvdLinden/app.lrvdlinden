import SwiftUI
import UIKit

// Huisstijl van lrvdlinden.app (site/index.html: --bg, --surface, --ink, --muted, --line, --accent, ...).

extension Color {
    /// Kleur met een eigen waarde voor donker (zoals HomeyAppStore/Core/Theme.swift).
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }

    init(rgb v: UInt32) {
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum Theme {
    static let accent = Brand.accent
    static let bg = Color(light: 0xF3F5F9, dark: 0x0D1018)
    static let surface = Brand.surface
    static let ink = Brand.ink
    static let muted = Brand.muted
    static let line = Brand.line
    static let beta = Color(light: 0x0F766E, dark: 0x5EC8B8)
    static let betaSoft = Color(light: 0xE0F4F1, dark: 0x13302C)
    static let build = Color(light: 0xB4530D, dark: 0xF2A15E)
    static let buildSoft = Color(light: 0xFFF0E3, dark: 0x2E2016)
    static let star = Color(light: 0xE3A008, dark: 0xF5C04A)
    static let good = Color(light: 0x0F766E, dark: 0x5EC8B8)
    static let bad = Color(light: 0xC0262D, dark: 0xFF7A80)

    /// Titels in de stijl van de display-letter van lrvdlinden.app (Bricolage Grotesque → systeem, afgerond en vet).
    static func display(_ style: Font.TextStyle) -> Font { .system(style, design: .rounded).weight(.bold) }
}

/// Taal van de app (nl of en) voor MoreAppsText en AppInfoText.
enum Config {
    static var uiLanguage: String {
        String((Bundle.main.preferredLocalizations.first ?? "en").prefix(2))
    }
}

/// Weergave: Automatisch / Licht / Donker (Instellingen → Weergave).
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .system: "Automatisch"
        case .light: "Licht"
        case .dark: "Donker"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Kaart in de stijl van lrvdlinden.app: surface, dunne rand, radius 22.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

extension View {
    func lrCard() -> some View { modifier(CardBackground()) }
}

/// Kleine statuslabel (live / beta / dev) zoals .dot in beheer.html.
struct StatusPill: View {
    let text: LocalizedStringKey
    let fg: Color
    let bg: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
    }
}
