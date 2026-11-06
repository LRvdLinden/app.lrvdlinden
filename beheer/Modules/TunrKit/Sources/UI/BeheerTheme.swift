import SwiftUI

/// Tunr-huisstijl (overgenomen uit de Tunr-app, Shared/UI/Theme.swift): altijd donker, "On Air"-oranje als accent.
enum BeheerTheme {
    static let bg = Color(hex: 0x0A0A0C)
    static let surface = Color(hex: 0x16161A)
    static let elevated = Color(hex: 0x202026)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color.white
    static let secondary = Color(hex: 0xA8A8B3)
    static let dim = Color(hex: 0x6E6E78)
    static let accent = Color(hex: 0xFF5A1F)
    static let accent2 = Color(hex: 0xFFB020)
    static let bad = Color(hex: 0xFF453A)
    static let good = Color(hex: 0x30D158)

    /// Accentverloop (135°)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Horizontaal verloop voor staafjes
    static let barGradient = LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing)

    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 12

    #if os(macOS)
    static let edge: CGFloat = 24
    #else
    static let edge: CGFloat = 16
    #endif
}

extension Color {
    /// `Color(hex: 0xFF5A1F)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Knopstijlen

/// Primaire knop: accentverloop, witte tekst.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(BeheerTheme.gradient,
                            in: RoundedRectangle(cornerRadius: BeheerTheme.buttonRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BeheerTheme.buttonRadius, style: .continuous)
                        .fill(Color.black.opacity(configuration.isPressed ? 0.18 : 0))
                }
                .opacity(enabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .shadow(color: BeheerTheme.accent.opacity(0.25), radius: 10, y: 5)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Secundaire knop: donker vlak met rand.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(BeheerTheme.elevated,
                            in: RoundedRectangle(cornerRadius: BeheerTheme.buttonRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BeheerTheme.buttonRadius, style: .continuous)
                        .strokeBorder(BeheerTheme.stroke, lineWidth: 1)
                }
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension View {
    /// Standaard schermachtergrond
    func screenBackground() -> some View {
        background(BeheerTheme.bg.ignoresSafeArea())
    }

    /// Kaart: donker vlak met dunne rand
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BeheerTheme.surface, in: RoundedRectangle(cornerRadius: BeheerTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BeheerTheme.cardRadius, style: .continuous)
                    .strokeBorder(BeheerTheme.stroke, lineWidth: 1)
            }
    }

    /// Titel in de navigatiebalk alleen inline op iPhone/iPad
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func largeTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
}
