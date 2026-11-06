import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Push notifications for P2000Beheer (feed outages, tests). Registers the APNs token with the API once logged in.
@MainActor
final class PushRegistrar: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushRegistrar()
    private(set) var deviceToken: String?
    /// Pushmeldingen bij een storing van NL-Alert, Burgernet of KNMI (A-Alerts), standaard aan.
    var bronnen: Bool {
        get { UserDefaults.module.object(forKey: "beheer.push.bronnen") as? Bool ?? true }
        set { UserDefaults.module.set(newValue, forKey: "beheer.push.bronnen"); syncIfPossible() }
    }
    var enabled: Bool {
        get { UserDefaults.module.object(forKey: "beheer.push") as? Bool ?? true }
        set { UserDefaults.module.set(newValue, forKey: "beheer.push"); if newValue { start() } }
    }

    func start() {
        guard enabled else { return }
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #else
            NSApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }

    func didRegister(_ data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        syncIfPossible()
    }

    func syncIfPossible() {
        guard let deviceToken, enabled, Session.shared.isLoggedIn else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        #if os(macOS)
        let platform = "macos"
        #else
        let platform = "ios"
        #endif
        let bronnen = self.bronnen
        Task {
            try? await Session.shared.call { token in
                try await BeheerAPI.shared.registerDevice(.init(token: deviceToken, environment: environment, platform: platform, bronnen: bronnen), token: token)
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
