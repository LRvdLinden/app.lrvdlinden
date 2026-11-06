import SwiftUI

/// Vergrendelscherm (Face ID / Touch ID / toegangscode; op de Mac Touch ID of het wachtwoord).
/// Zonder knop: alleen afschermen in de app-wisselaar (iOS).
struct LockView: View {
    let showButton: Bool
    @EnvironmentObject private var session: Session

    var body: some View {
        ZStack {
            BeheerTheme.bg.ignoresSafeArea()
            RadialGradient(colors: [BeheerTheme.accent.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                BeheerLogo(size: 34)
                if showButton {
                    Button {
                        Task { await session.unlock() }
                    } label: {
                        Label(L("Ontgrendelen"), systemImage: session.biometryIcon)
                    }
                    .buttonStyle(.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .task(id: showButton) {
            if showButton && !session.autoUnlockTried {
                session.autoUnlockTried = true
                await session.unlock()
            }
        }
    }
}
