import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BeheerTunrApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            root
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .commands { BeheerCommands(session: session) }

        Settings {
            NavigationStack {
                SettingsView(inSettingsWindow: true)
            }
            .environmentObject(session)
            .preferredColorScheme(.dark)
            .tint(BeheerTheme.accent)
            .frame(width: 520, height: 560)
        }
        #else
        WindowGroup {
            root
        }
        #endif
    }

    private var root: some View {
        RootView()
            .environmentObject(session)
            .preferredColorScheme(.dark)
            .tint(BeheerTheme.accent)
    }
}

#if os(macOS)
/// Menubalk op de Mac: menu Beheer met Vernieuwen (⌘R) en de onderdelen (⌘1 … ⌘3); geen Nieuw venster.
struct BeheerCommands: Commands {
    let session: Session

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu(L("Beheer")) {
            Button(L("Vernieuwen")) { onMain { $0.requestRefresh() } }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            Button(AppSection.overview.title) { onMain { $0.section = .overview } }
                .keyboardShortcut("1", modifiers: .command)
            Button(AppSection.downloads.title) { onMain { $0.section = .downloads } }
                .keyboardShortcut("2", modifiers: .command)
            Button(AppSection.settings.title) { onMain { $0.section = .settings } }
                .keyboardShortcut("3", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button(L("Beheer op het web")) { open(Config.beheerSite) }
            Button("tunr.online") { open(Config.website) }
            Button(L("Webspeler")) { open(Config.webPlayer) }
        }
    }

    private func onMain(_ action: @escaping @MainActor (Session) -> Void) {
        let session = session
        Task { @MainActor in action(session) }
    }

    private func open(_ url: URL) {
        Task { @MainActor in _ = NSWorkspace.shared.open(url) }
    }
}
#endif
