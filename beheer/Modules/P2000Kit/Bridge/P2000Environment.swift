import SwiftUI

/// Brug tussen LRbeheer en de volledige P2000Beheer-app (alles in Sources/ is de originele code).
/// Doet wat `P2000BeheerApp` en zijn `AppDelegate` deden: Session.shared, root-view en het APNs-token.
@MainActor
public enum P2000Environment {
    /// In de losse app vroeg `PushRegistrar.start()` bij elke start om toestemming en registreerde bij APNs.
    /// In LRbeheer vraagt de app zelf (één keer) om toestemming en geeft het token door; start() registreert
    /// daarna opnieuw als de schakelaar in P2000-Instellingen aan staat.
    public static func start() {
        if Session.shared.isLoggedIn { PushRegistrar.shared.start() }
    }

    public static func rootView() -> AnyView {
        AnyView(
            RootView()
                .environment(Session.shared)
                .tint(Theme.red)
        )
    }

    /// P2000Beheer volgde de systeemweergave.
    public static let colorScheme: ColorScheme? = nil

    public static var isSignedIn: Bool { Session.shared.isLoggedIn }

    /// Inloggen met de gedeelde beheer-inlog van LRbeheer (zelfde route als het inlogscherm van P2000Beheer).
    public static func login(user: String, password: String) async throws {
        try await Session.shared.login(user: user, password: password)
        PushRegistrar.shared.start()
    }

    public static func didRegister(deviceToken: Data) {
        PushRegistrar.shared.didRegister(deviceToken)
    }

    public static func owns(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "p2000beheer"
    }

    /// P2000Beheer kende geen deeplinks; een link opent de app op het dashboard.
    public static func open(_ url: URL) {}

    public static func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background { Session.shared.lockIfNeeded() }
    }
}
