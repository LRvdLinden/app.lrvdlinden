import BingrKit
import P2000Kit
import PasrKit
import UIKit
import UserNotifications

/// Eén app-delegate en één meldingencentrum-delegate voor alle omgevingen.
///
/// - Het APNs-token gaat naar elke omgeving met een eigen pushsysteem (Bingr, Pasr, P2000; elk registreert alleen als
///   je daar ingelogd bent, net als in de losse app) en naar het centrale systeem (LRvdLinden, PixelForges, Tunr).
/// - Meldingen worden ook getoond als LRbeheer open is, ongeacht welke omgeving actief is.
/// - Een tik op een melding opent de juiste omgeving en het juiste onderdeel (AppModel.handleNotification).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated {
            BingrEnvironment.didRegister(deviceToken: deviceToken)
            PasrEnvironment.didRegister(deviceToken: deviceToken)
            P2000Environment.didRegister(deviceToken: deviceToken)
            CentralPush.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MainActor.assumeIsolated {
            BingrEnvironment.didFailToRegister()
            PasrEnvironment.didFailToRegister()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run { AppModel.shared.handleNotification(info) }
    }
}
