import SwiftUI

/// Instellingen van LRbeheer zelf. De instellingen van elke omgeving (inloggen, pushsoorten, vergrendeling, Overal
/// uitloggen, ...) staan ongewijzigd in die omgeving, onder hun eigen Instellingen.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system
    @State private var showWhatsNew = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Laatstgebruikte omgeving openen", isOn: $model.reopenLast)
                if AppLock.canLock {
                    Toggle(isOn: $model.lockEnabled) {
                        Label(String(format: String(localized: "Vergrendelen met %@"), AppLock.biometryName), systemImage: AppLock.biometryIcon)
                    }
                }
                NavigationLink { NotificationSettingsView() } label: {
                    Label("Meldingen", systemImage: "bell.badge")
                }
                NavigationLink { SharedLoginForm() } label: {
                    Label("Eén inlog voor alle omgevingen", systemImage: "person.badge.key")
                }
            } header: { Text("LRbeheer") } footer: {
                Text("De vergrendeling geldt voor het overzicht, LRvdLinden en PixelForges. Bingr, Tunr, Pasr en P2000 houden hun eigen vergrendeling, in hun eigen Instellingen.")
            }

            Section("Omgevingen") {
                ForEach(BeheerEnvironment.allCases) { env in
                    Button {
                        dismiss()
                        model.switchTo(env)
                    } label: {
                        HStack(spacing: 12) {
                            EnvironmentIcon(env: env, size: 30)
                            Text(verbatim: env.name).foregroundStyle(.primary)
                            Spacer()
                            Text(env.isSignedIn ? "Ingelogd" : "Niet ingelogd").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Weergave") {
                Picker("Weergave", selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Bingr, Tunr en Pasr blijven donker, zoals in de oorspronkelijke apps.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://lrvdlinden.app/privacy.html")!) {
                    Label("Privacyverklaring", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://lrvdlinden.app")!) {
                    Label("Support / contact", systemImage: "questionmark.circle")
                }
                Button { showWhatsNew = true } label: { Label("Wat is nieuw", systemImage: "sparkles") }
                Link(destination: URL(string: "https://lrvdlinden.app/donate")!) {
                    Label("Doneer", systemImage: "heart")
                }
            }

            Section {
                MoreAppsCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: { Text(MoreAppsText.current.section) }

            Section {
                AppInfoFooter()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Instellingen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
        }
        .sheet(isPresented: $showWhatsNew) { WhatsNewView() }
    }
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Bingr: Lifetime-only") {
                    Label("Instellingen → Lifetime-only: aankondiging, overgangsdatum, korting, proefperiode, Apple-koopknop en EU-link, met bevestiging", systemImage: "star.circle")
                    Label("Kortingscodes genereren (droog en echt) met de totalen", systemImage: "ticket")
                    Label("Mail Bingr wordt Lifetime testen en versturen, en de herinnering", systemImage: "envelope")
                    Label("Niet geclaimde aankopen, en een aankoop handmatig aan een account koppelen", systemImage: "link")
                    Label("Gebruikers: kortingscode en status bij het account", systemImage: "person.text.rectangle")
                    Label("Omzet: per aanbieder (website via Stripe en Apple)", systemImage: "eurosign.circle")
                }
                Section("A-Alerts") {
                    Label("P2000 Apeldoorn heet nu A-Alerts, met het nieuwe icoon", systemImage: "app.badge")
                    Label("Waarschuwingen: NL-Alert, Burgernet en KNMI bekijken, verbergen of handmatig beëindigen", systemImage: "exclamationmark.triangle")
                    Label("Dashboard: status van de bronnen en helikopters in de lucht", systemImage: "antenna.radiowaves.left.and.right")
                    Label("Dashboard: gebruik van de notificatieprofielen", systemImage: "person.2.badge.gearshape")
                    Label("Pushmelding bij een storing van NL-Alert, Burgernet of KNMI (met schakelaar)", systemImage: "bell.badge")
                    Label("A-Alerts gebruikt dezelfde iconen als de app", systemImage: "app.badge.checkmark")
                    Label("A-Alerts: nieuwe tekst Cookies bewerken, links naar a-alerts.nl", systemImage: "checkmark.shield")
                    Label("A-Alerts: nieuwe iconen voor NL-Alert en KNMI, net als in de app", systemImage: "photo")
                    Label("A-Alerts: downloads van de Android-app (totaal, 30 dagen, per dag en per versie)", systemImage: "arrow.down.circle")
                    Label("A-Alerts: Android-installaties, push-toestellen en status van Firebase", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
                Section(String(format: String(localized: "Versie %@"), Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")) {
                    Label("Eén app voor LRvdLinden, PixelForges, Bingr, Tunr, Pasr en P2000 Apeldoorn", systemImage: "square.grid.2x2")
                    Label("Direct wisselen tussen omgevingen bovenin het scherm", systemImage: "arrow.left.arrow.right")
                    Label("Alle functies van BingrBeheer, BeheerTunr, PasrBeheer en P2000Beheer", systemImage: "checkmark.seal")
                    Label("Native beheer van lrvdlinden.app en pixelforges.nl", systemImage: "globe")
                    Label("Echte Mac-app met menubalk (⌘1…⌘6 wisselt van omgeving)", systemImage: "macbook")
                    Label("Pushmeldingen van alle omgevingen; een tik opent de juiste omgeving", systemImage: "bell.badge")
                }
            }
            .navigationTitle("Wat is nieuw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Meldingen per omgeving: één systeemtoestemming, daarna per omgeving waar de schakelaars staan.
struct NotificationSettingsView: View {
    @State private var central = CentralPush.shared
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                switch central.permission {
                case .allowed:
                    Label("Meldingen staan aan", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                case .denied:
                    Label("Meldingen staan uit in de systeeminstellingen", systemImage: "bell.slash")
                    Button("Open Instellingen") { Task { await central.requestPermission() } }
                default:
                    Button { Task { await central.requestPermission() } } label: { Label("Meldingen aanzetten", systemImage: "bell") }
                }
            } footer: {
                Text("Meldingen komen van alle omgevingen binnen, welke omgeving er ook open is. Een tik opent de juiste omgeving en het juiste onderdeel.")
            }

            Section {
                envRow(.bingr, "Eigen pushsysteem van BingrBeheer: tickets, antwoorden, builds en status. Per soort in Bingr → Instellingen.")
                envRow(.pasr, "Eigen pushsysteem van PasrBeheer. Per soort in Pasr → Instellingen.")
                envRow(.p2000, "Eigen pushsysteem van P2000Beheer: storingen van de feed en tests. Aan/uit in P2000 → Instellingen.")
            } header: { Text("Bestaande meldingen") }

            Section {
                if !central.canRegister {
                    Label("Log in bij Tunr om deze meldingen aan te zetten (het centrale pushsysteem gebruikt de beheer-inlog van Tunr).",
                          systemImage: "info.circle")
                        .font(.footnote)
                } else {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(central.registered ? "Aangemeld" : "Niet aangemeld").foregroundStyle(.secondary)
                    }
                    if let e = central.lastError { Text(e).font(.footnote).foregroundStyle(Theme.bad) }
                }
                @Bindable var c = central
                Group {
                    Toggle(isOn: $c.prefs.lrvdlindenStore) { envLabel(.lrvdlinden, "Store-check: nieuwe apps en updates") }
                    Toggle(isOn: $c.prefs.lrvdlindenDeploy) { envLabel(.lrvdlinden, "Site gepubliceerd of deploy mislukt") }
                    Toggle(isOn: $c.prefs.pixelforgesDeploy) { envLabel(.pixelforges, "Site gepubliceerd of deploy mislukt") }
                    Toggle(isOn: $c.prefs.pixelforgesContent) { envLabel(.pixelforges, "Inhoud gewijzigd") }
                    Toggle(isOn: $c.prefs.pixelforgesContact) { envLabel(.pixelforges, "Nieuwe aanvraag via het contactformulier") }
                    Toggle(isOn: $c.prefs.tunrInstalls) { envLabel(.tunr, "Nieuwe installaties (dagelijks overzicht)") }
                    Toggle(isOn: $c.prefs.tunrPresskit) { envLabel(.tunr, "Perskit gedownload") }
                }
                .disabled(!central.canRegister || central.permission != .allowed)
                Button {
                    testing = true
                    Task {
                        defer { testing = false }
                        do { try await central.sendTest(); testResult = String(localized: "Testmelding verstuurd") }
                        catch { testResult = error.localizedDescription }
                    }
                } label: { Label(testing ? "Bezig…" : "Stuur een testmelding", systemImage: "paperplane") }
                .disabled(!central.canRegister || central.permission != .allowed || testing)
                if let t = testResult { Text(t).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Nieuwe meldingen (centraal)") } footer: {
                Text("LRvdLinden, PixelForges en Tunr via de centrale pushfunctie van LRbeheer. De schakelaars gelden voor dit apparaat.")
            }
        }
        .navigationTitle("Meldingen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await central.refresh()
            central.sync(force: false)
        }
    }

    private func envRow(_ env: BeheerEnvironment, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            EnvironmentIcon(env: env, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: env.name).font(.body.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
                if !env.isSignedIn { Text("Log in bij deze omgeving om meldingen te krijgen.").font(.caption).foregroundStyle(Theme.build) }
            }
        }
    }

    private func envLabel(_ env: BeheerEnvironment, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            EnvironmentIcon(env: env, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: env.name).font(.caption).foregroundStyle(.secondary)
                Text(text)
            }
        }
    }
}
