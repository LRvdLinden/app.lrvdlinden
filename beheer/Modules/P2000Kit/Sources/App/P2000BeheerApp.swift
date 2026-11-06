import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct P2000BeheerApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #else
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    #endif
    @State private var session = Session.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.red)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif
    }
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { PushRegistrar.shared.start() }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushRegistrar.shared.didRegister(deviceToken) }
    }
}
#else
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { PushRegistrar.shared.start() }
    }
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushRegistrar.shared.didRegister(deviceToken) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

enum Theme {
    static let red = Color(red: 0.863, green: 0.149, blue: 0.149)
    static let dark = Color(red: 0.051, green: 0.055, blue: 0.071)
    static let green = Color(red: 0.13, green: 0.77, blue: 0.37)
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    static var pageBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}
