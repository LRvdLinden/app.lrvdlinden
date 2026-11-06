import SwiftUI
import UIKit

/// Brug tussen LRbeheer en de volledige BingrBeheer-app (alles in Sources/ is de originele code).
///
/// Doet precies wat `BingrBeheerApp` (Sources/App/BingrBeheerApp.swift) en zijn `AppDelegate` in de losse app deden:
/// één Session, de root-view met dezelfde modifiers, PushService koppelen en het APNs-token doorgeven.
@MainActor
public enum BingrEnvironment {
    /// Eén sessie voor de hele levensduur van LRbeheer: wisselen van omgeving logt niet uit.
    static let session = Session()

    /// Bij het starten van LRbeheer (ook als Bingr niet de actieve omgeving is), zodat pushregistratie en
    /// vergrendeling werken zoals in de losse app.
    public static func start() {
        PushService.shared.attach(session)
    }

    /// De complete BingrBeheer-interface (tabbalk op iPhone, zijbalk op iPad).
    public static func rootView() -> AnyView {
        AnyView(
            RootView()
                .environment(session)
                .tint(.bingrRed)
        )
    }

    /// BingrBeheer was altijd donker.
    public static let colorScheme: ColorScheme? = .dark

    public static var isSignedIn: Bool { session.isSignedIn }

    // MARK: pushmeldingen

    public static func didRegister(deviceToken: Data) {
        PushService.shared.didRegister(deviceToken: deviceToken)
    }

    public static func didFailToRegister() {
        PushService.shared.didFailToRegister()
    }

    /// Hoort deze link (widget, pushmelding) bij Bingr? `bingrbeheer://…` of `https://beheer.bingr.online/#…`.
    public static func owns(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "bingrbeheer" || url.host?.lowercased() == "beheer.bingr.online"
    }

    /// Deeplink openen (Session.open, zoals .onOpenURL in de losse app).
    public static func open(_ url: URL) {
        session.open(url)
    }

    /// Tik op een pushmelding met `url` (PushService.handleTap, zoals PushNotificationDelegate in de losse app).
    public static func handleNotification(url raw: String?) {
        PushService.shared.handleTap(raw)
    }

    /// Scènefase van LRbeheer, ook als Bingr niet zichtbaar is: vergrendelen bij naar de achtergrond gaan.
    public static func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background { session.didEnterBackground() }
        if phase == .active, session.isSignedIn { Task { await PushService.shared.refresh() } }
    }
}
