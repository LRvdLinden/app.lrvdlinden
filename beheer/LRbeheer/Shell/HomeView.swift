import SwiftUI

/// Overzicht na het opstarten: de zes beheeromgevingen in vaste volgorde, met logo, status (ingelogd of niet) en
/// de laatstgebruikte omgeving gemarkeerd.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tick = 0

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: sizeClass == .regular ? 3 : 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(BeheerEnvironment.allCases) { env in
                            Button { model.switchTo(env) } label: { EnvironmentCard(env: env, last: model.lastUsed == env, tick: tick) }
                                .buttonStyle(CardPressStyle())
                                .accessibilityHint("Opent de beheeromgeving")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("LRbeheer")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Instellingen")
                }
            }
            .onAppear { tick += 1 }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BeheerMark(size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kies een omgeving").font(Theme.display(.title3))
                Text("Wissel daarna bovenin, zonder terug te gaan.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

struct EnvironmentCard: View {
    let env: BeheerEnvironment
    let last: Bool
    let tick: Int

    var body: some View {
        HStack(spacing: 14) {
            EnvironmentIcon(env: env, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: env.name).font(.headline).foregroundStyle(Theme.ink)
                    if last {
                        Text("Laatst gebruikt")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Brand.accentSoft, in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(env.subtitle).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Circle().fill(env.isSignedIn ? Theme.good : Theme.muted.opacity(0.5)).frame(width: 7, height: 7)
                    Text(env.isSignedIn ? "Ingelogd" : "Niet ingelogd").font(.caption).foregroundStyle(Theme.muted)
                    Text(verbatim: "· \(env.site)").font(.caption).foregroundStyle(Theme.muted.opacity(0.8)).lineLimit(1)
                }
                .id(tick)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(env.color).frame(width: 4).padding(.vertical, 18)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
