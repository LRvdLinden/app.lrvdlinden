import SwiftUI

@main
struct LRbeheerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        #if targetEnvironment(macCatalyst)
        // Mac: standaard venstergrootte (daarna onthoudt macOS hem) en een eigen menubalk
        window
            .defaultSize(width: 1320, height: 860)
            .commands { LRbeheerCommands(model: model) }
        #else
        window
        #endif
    }

    private var window: some Scene {
        WindowGroup {
            RootContainer()
                .environment(model)
                // Bingr, Tunr en Pasr waren altijd donker; daar blijft dat zo. Elders de keuze in Instellingen → Weergave.
                .preferredColorScheme(model.active?.forcedScheme ?? appearance.colorScheme)
                .onOpenURL { model.open($0) }
                .task { model.start() }
                #if targetEnvironment(macCatalyst)
                .background { MacWindowSetup() }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
    }
}

/// Splash → (vergrendeld) → overzicht of de actieve omgeving.
struct RootContainer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var splash = true

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let env = model.active {
                EnvironmentHost(env: env)
                    .id(env)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
            } else {
                HomeView()
                    .transition(.opacity)
            }
            if shielded {
                AppLockView()
                    .transition(.opacity)
                    .zIndex(5)
            }
            if splash {
                SplashView { withAnimation(.easeOut(duration: 0.35)) { splash = false } }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shielded)
        .reviewPrompt(isCalm: !splash && !shielded && !model.showSettings && !model.showSwitcher)
        .sheet(isPresented: Binding(get: { model.showSettings }, set: { model.showSettings = $0 })) {
            NavigationStack { SettingsView() }
        }
    }

    /// Alleen het overzicht, LRvdLinden en PixelForges vallen onder de vergrendeling van LRbeheer. Bingr, Tunr, Pasr en
    /// P2000 hebben hun eigen vergrendeling uit de oorspronkelijke app (met hun eigen schakelaar in hun Instellingen).
    private var shielded: Bool {
        guard model.lockEnabled else { return false }
        let own = model.active == nil || model.active == .lrvdlinden || model.active == .pixelforges
        return own && (model.isLocked || scenePhase != .active) && !splash
    }
}
