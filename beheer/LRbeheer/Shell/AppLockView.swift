import SwiftUI

/// Vergrendelscherm van LRbeheer (overzicht, LRvdLinden en PixelForges). Vraagt één keer vanzelf om Face ID.
struct AppLockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tried = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                BeheerMark(size: 88)
                Text("LRbeheer is vergrendeld").font(Theme.display(.title3))
                if model.isLocked && scenePhase == .active {
                    Button {
                        Task { await unlock() }
                    } label: {
                        Label(String(format: String(localized: "Ontgrendel met %@"), AppLock.biometryName), systemImage: AppLock.biometryIcon)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, model.isLocked, !tried else { return }
            tried = true
            await unlock()
        }
        .onChange(of: model.isLocked) { _, locked in if locked { tried = false } }
    }

    private func unlock() async {
        if await AppLock.unlock() { model.isLocked = false }
    }
}
