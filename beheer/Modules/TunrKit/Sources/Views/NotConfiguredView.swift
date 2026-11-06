import SwiftUI

/// Zolang `Config.supabaseURL` of `Config.publishableKey` leeg is.
struct NotConfiguredView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)
                BeheerLogo(size: 34)
                VStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(BeheerTheme.gradient)
                    Text(L("Nog niet ingericht"))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(L("Vul de Supabase-URL en de publishable key van het project tunr in apple/Shared/Config.swift in en bouw de app opnieuw."))
                        .font(.subheadline)
                        .foregroundStyle(BeheerTheme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .card(padding: 24)
                .frame(maxWidth: 480)
                Link(destination: Config.beheerSite) {
                    Label(L("Beheer op het web"), systemImage: "safari")
                }
                .buttonStyle(.secondary)
            }
            .padding(BeheerTheme.edge)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
    }
}
