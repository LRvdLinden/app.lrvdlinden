import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if session.isLoggedIn {
                MainTabs()
                    .blur(radius: session.isLocked ? 18 : 0)
                    .disabled(session.isLocked)
                if session.isLocked {
                    LockView().transition(.opacity)
                }
            } else {
                LoginView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isLoggedIn)
        .animation(.easeInOut(duration: 0.25), value: session.isLocked)
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            if phase == .background { session.lockIfNeeded() }
            #endif
            if phase == .active && session.isLocked { Task { await session.unlock() } }
        }
        .task { if session.isLocked { await session.unlock() } }
    }
}

struct MainTabs: View {
    @State private var tab = "dashboard"

    var body: some View {
        TabView(selection: $tab) {
            Tab("Dashboard", systemImage: "chart.xyaxis.line", value: "dashboard") { DashboardView() }
            Tab("Status", systemImage: "waveform.path.ecg", value: "status") { StatusBeheerView() }
            Tab("Meldingen", systemImage: "list.bullet.rectangle", value: "meldingen") { MeldingenView() }
            Tab("Waarschuwingen", systemImage: "exclamationmark.triangle", value: "waarschuwingen") { WaarschuwingenView() }
            Tab("Gemelde fouten", systemImage: "exclamationmark.bubble", value: "fouten") { FoutenView() }
            Tab("Toestel zoeken", systemImage: "magnifyingglass", value: "toestel") { ToestelView() }
            Tab("Push", systemImage: "paperplane.fill", value: "push") { PushView() }
            Tab("Teksten", systemImage: "doc.text", value: "teksten") { TekstenView() }
            Tab("Instellingen", systemImage: "gearshape", value: "instellingen") { SettingsView() }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

struct LockView: View {
    @Environment(Session.self) private var session
    var body: some View {
        VStack(spacing: 18) {
            Image("BrandMark").resizable().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("A-Alerts-beheer is vergrendeld").font(.title3.bold())
            Button {
                Task { await session.unlock() }
            } label: {
                Label("Ontgrendel met \(Session.biometryName)", systemImage: "faceid")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
