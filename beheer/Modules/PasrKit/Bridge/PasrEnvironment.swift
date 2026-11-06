import SwiftUI

/// Brug tussen LRbeheer en de volledige PasrBeheer-app (alles in Sources/ is de originele code).
/// Doet wat `PasrBeheerApp` en zijn `AppDelegate` deden: één Session, root-view, PushService en het APNs-token.
@MainActor
public enum PasrEnvironment {
    static let session = Session()

    public static func start() {
        PushService.shared.attach(session)
    }

    public static func rootView() -> AnyView {
        AnyView(
            RootView()
                .environmentObject(session)
                .tint(Theme.iris)
        )
    }

    /// PasrBeheer was altijd donker.
    public static let colorScheme: ColorScheme? = .dark

    public static var isSignedIn: Bool { session.isSignedIn }

    public static func didRegister(deviceToken: Data) {
        PushService.shared.didRegister(deviceToken: deviceToken)
    }

    public static func didFailToRegister() {
        PushService.shared.didFailToRegister()
    }

    public static func owns(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "pasrbeheer" || url.host?.lowercased() == "beheer.pasr.nl"
    }

    public static func open(_ url: URL) {
        session.open(url)
    }

    public static func handleNotification(url raw: String?) {
        PushService.shared.handleTap(raw)
    }

    public static func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            session.didEnterForeground()
            if session.isSignedIn { Task { await PushService.shared.refresh() } }
        case .background: session.didLeaveForeground()
        default: break
        }
    }
}
