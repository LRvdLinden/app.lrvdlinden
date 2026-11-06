import SwiftUI

/// Brug tussen LRbeheer en de volledige BeheerTunr-app (alles in Sources/ is de originele code).
/// Doet wat `BeheerTunrApp` (Sources/App/BeheerTunrApp.swift) deed: één Session en de root-view met dezelfde modifiers.
@MainActor
public enum TunrEnvironment {
    static let session = Session()

    public static func start() {}

    public static func rootView() -> AnyView {
        AnyView(
            RootView()
                .environmentObject(session)
                .tint(BeheerTheme.accent)
        )
    }

    /// BeheerTunr was altijd donker.
    public static let colorScheme: ColorScheme? = .dark

    public static var isSignedIn: Bool { session.isSignedIn }

    /// Beheer-token van Tunr (12 uur, functie `admin`). LRbeheer gebruikt het om zich aan te melden bij de centrale
    /// pushfunctie `lrbeheer`, die in hetzelfde Supabase-project draait en het token met dezelfde sleutel controleert.
    public static var adminToken: String? { session.token }

    /// Publieke Supabase-URL en publishable key van Tunr (dezelfde als in Config.swift; geen geheimen).
    public static var supabaseURL: String { Config.supabaseURL }
    public static var publishableKey: String { Config.publishableKey }

    public static func owns(_ url: URL) -> Bool {
        url.host?.lowercased() == "beheer.tunr.online"
    }

    public static func open(_ url: URL) {
        switch url.pathComponents.dropFirst().first?.lowercased() {
        case "downloads": session.section = .downloads
        case "settings", "instellingen": session.section = .settings
        default: session.section = .overview
        }
    }

    /// Zelfde vergrendelregels als in de losse app (na 5 minuten weg), ook als Tunr niet zichtbaar is.
    public static func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active { session.didEnterForeground() } else { session.didLeaveForeground() }
    }
}
