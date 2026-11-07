import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(Session.self) private var session
    @State private var pushOn = PushRegistrar.shared.enabled
    @State private var bronnenOn = PushRegistrar.shared.bronnen
    @State private var testResult: String?
    @State private var confirmLogout = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Ingelogd als", value: session.user ?? "–")
                    if let e = session.expires {
                        LabeledContent("Sessie geldig tot", value: e.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Uitloggen", role: .destructive) { confirmLogout = true }
                }
                Section {
                    Toggle("Vergrendel met \(Session.biometryName)", isOn: $session.faceIDEnabled)
                        .disabled(!Session.biometricsAvailable)
                } footer: {
                    Text("Bij het openen van A-Alerts-beheer vraagt de app om \(Session.biometryName).")
                }
                Section {
                    Toggle("Meldingen bij storingen", isOn: $pushOn)
                        .onChange(of: pushOn) { _, on in PushRegistrar.shared.enabled = on }
                    Toggle("Storingen en afwijkingen", isOn: $bronnenOn)
                        .onChange(of: bronnenOn) { _, on in PushRegistrar.shared.bronnen = on }
                        .disabled(!pushOn)
                    Button("Stuur een testmelding") { Task { await test() } }
                    if let testResult { Text(testResult).font(.callout).foregroundStyle(.secondary) }
                } header: {
                    Text("Pushmeldingen")
                } footer: {
                    Text("Je krijgt een melding zodra een onderdeel van de statuspagina 3 minuten afwijkt van normaal (P2000, NL-Alert, Burgernet, KNMI, pushmeldingen, helikopters, weer, server of website), bij een push-wachtrij die achterloopt of een ongewoon lange stilte zonder meldingen, en weer als alles normaal is.")
                }
                Section("Over") {
                    LabeledContent("Versie", value: version)
                    LabeledContent("API", value: BeheerAPI.base.host ?? "–")
                    Link(destination: URL(string: "https://a-alerts.nl")!) { Label("a-alerts.nl", systemImage: "safari") }
                    Link(destination: BeheerAPI.base.appendingPathComponent("health")) { Label("API-status (health)", systemImage: "waveform.path.ecg") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Instellingen")
            .confirmationDialog("Uitloggen?", isPresented: $confirmLogout) {
                Button("Uitloggen", role: .destructive) { session.logout() }
            }
        }
    }

    private func test() async {
        PushRegistrar.shared.syncIfPossible()
        try? await Task.sleep(for: .seconds(1))
        do {
            try await session.call { try await BeheerAPI.shared.testPush(token: $0) }
            testResult = "Testmelding verstuurd."
        } catch {
            testResult = error.localizedDescription
        }
    }
}
