import SwiftUI

/// "Nog niet ingericht", inloggen, of de app zelf (tabbalk op de iPhone, zijbalk op iPad en Mac);
/// met het vergrendelscherm eroverheen.
struct RootView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        ZStack {
            BeheerTheme.bg.ignoresSafeArea()
            if !Config.isConfigured {
                NotConfiguredView()
            } else if session.isSignedIn {
                main
            } else {
                LoginView()
            }
            if shielded {
                LockView(showButton: showUnlockButton)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shielded)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: session.didEnterForeground()
            default: session.didLeaveForeground()
            }
        }
    }

    @ViewBuilder private var main: some View {
        #if os(iOS)
        if sizeClass == .regular {
            SplitLayout()
        } else {
            TabLayout()
        }
        #else
        SplitLayout()
        #endif
    }

    /// iOS: knop pas als de app weer actief is; Mac: altijd als hij vergrendeld is (ook als het venster niet voorop staat).
    private var showUnlockButton: Bool {
        #if os(iOS)
        return session.isLocked && scenePhase == .active
        #else
        return session.isLocked
        #endif
    }

    /// Vergrendeld; op iPhone/iPad ook afgeschermd zolang de app niet actief is (app-wisselaar).
    private var shielded: Bool {
        guard Config.isConfigured, session.isSignedIn, session.lockEnabled else { return false }
        #if os(iOS)
        return session.isLocked || scenePhase != .active
        #else
        return session.isLocked
        #endif
    }
}

/// iPhone: tabbalk met Overzicht, Downloads en Instellingen.
struct TabLayout: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        TabView(selection: $session.section) {
            ForEach(AppSection.allCases) { s in
                NavigationStack {
                    SectionContent(section: s)
                }
                .tabItem { Label(s.title, systemImage: s.icon) }
                .tag(s)
            }
        }
    }
}

/// iPad en Mac: zijbalk met de onderdelen, rechts het gekozen onderdeel.
struct SplitLayout: View {
    @EnvironmentObject private var session: Session
    @State private var visibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(selection: Binding<AppSection?>(
                get: { session.section },
                set: { if let s = $0 { session.section = s } }
            )) {
                Section {
                    ForEach(AppSection.allCases) { s in
                        Label(s.title, systemImage: s.icon).tag(s)
                    }
                } header: {
                    BeheerLogo(size: 18)
                        .padding(.vertical, 8)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            NavigationStack {
                SectionContent(section: session.section)
            }
            .id(session.section)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SectionContent: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .overview: OverviewView()
        case .downloads: DownloadsView()
        case .settings: SettingsView()
        }
    }
}
