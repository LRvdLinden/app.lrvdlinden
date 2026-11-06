import SwiftUI

/// Een beheeromgeving met daarboven de omgevingskiezer van LRbeheer. De omgeving zelf is de volledige, originele
/// interface (eigen tabbalk/zijbalk, eigen inlog en instellingen); de balk bovenin laat altijd zien welke omgeving
/// actief is en wisselt direct naar een andere, zonder terug te gaan naar het overzicht (zoals profielen in Bingr).
struct EnvironmentHost: View {
    let env: BeheerEnvironment
    @Environment(AppModel.self) private var model

    var body: some View {
        env.rootView
            .safeAreaInset(edge: .top, spacing: 0) { EnvironmentBar(env: env) }
    }
}

struct EnvironmentBar: View {
    let env: BeheerEnvironment
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Section("Wissel van omgeving") {
                    ForEach(BeheerEnvironment.allCases) { e in
                        Button { model.switchTo(e) } label: {
                            Label {
                                Text(verbatim: e.name)
                            } icon: {
                                Image(systemName: e == env ? "checkmark.circle.fill" : (e.isSignedIn ? "circle.fill" : "circle"))
                            }
                        }
                    }
                }
                Button { model.switchTo(nil) } label: { Label("Overzicht", systemImage: "square.grid.2x2") }
            } label: {
                HStack(spacing: 8) {
                    EnvironmentIcon(env: env, size: 26)
                    Text(verbatim: env.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(env.color.opacity(0.55), lineWidth: 1))
                .contentShape(Capsule())
            }
            .accessibilityLabel(Text("Actieve omgeving: \(env.name). Tik om te wisselen."))
            .sensoryFeedback(.selection, trigger: env)

            Spacer(minLength: 0)

            // snelle wissel: de andere omgevingen als kleine icoontjes (iPad en brede schermen)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(BeheerEnvironment.allCases.filter { $0 != env }) { e in
                        Button { model.switchTo(e) } label: { EnvironmentIcon(env: e, size: 26) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: e.name))
                    }
                }
                EmptyView()
            }

            Button { model.showSettings = true } label: {
                Image(systemName: "gearshape").font(.body.weight(.medium)).frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Instellingen van LRbeheer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(env.color.opacity(0.7)).frame(height: 1.5) }
    }
}
