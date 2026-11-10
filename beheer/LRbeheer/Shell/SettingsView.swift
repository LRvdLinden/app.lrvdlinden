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
                Section("A-Alerts: Widgets") {
                    Label("Nieuw onderdeel Widgets: kopieer de scriptcode van de live kaart en Verkeer nu voor andere websites, zie op welke sites ze staan met het aantal weergaven, en blokkeer een site", systemImage: "puzzlepiece.extension")
                    Label("Alleen nog de scriptcode: die past zich vanzelf aan en websites kunnen de widget niet aanpassen", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Section("A-Alerts: Verkeer") {
                    Label("Bij A-Alerts-bronnen staat nu ook Verkeer (NDW, Koyeb): je ziet of de verkeersservice werkt en krijgt een pushmelding als hij langer dan 30 minuten geen gegevens geeft", systemImage: "car.side")
                }
                Section("A-Alerts: Nieuws") {
                    Label("Zet per weerartikel, Burgernet, AMBER Alert, NL-Alert en Vermist Kind zelf aan of het een liveblog is: dan staat er \"Liveblog\" bij en LIVEBLOG op de afbeelding (standaard uit). NL-Alert krijgt nu ook een artikel", systemImage: "dot.radiowaves.left.and.right")
                    Label("Nieuw tabblad Nieuws: politieberichten over Apeldoorn en omgeving, weerartikelen en liveblogs bij Burgernet, AMBER Alert en Vermist Kind Alert", systemImage: "newspaper")
                    Label("Vul een liveblog aan met tekst, foto en link, met een pushmelding naar wie die bron volgt; wijzig of verwijder eigen berichten", systemImage: "plus.bubble")
                    Label("Verberg een bericht, kies een eigen afbeelding, en stel per onderwerp de standaardafbeelding voor politieberichten in", systemImage: "photo.on.rectangle")
                    Label("Ook artikelen van 112 Nieuws per plaats (titel en intro met link), met eigen filter", systemImage: "light.beacon.max")
                }
                Section("A-Alerts: AMBER Alert en Vermist Kind Alert") {
                    Label("Twee nieuwe soorten waarschuwingen (vermiste kinderen, van de politie via Burgernet) in de lijst, het filter en de cijfers per bron", systemImage: "figure.child")
                    Label("Status van de nieuwe bron en hoeveel toestellen ze willen ontvangen; verbergen of beëindigen werkt zoals bij de andere waarschuwingen", systemImage: "antenna.radiowaves.left.and.right")
                }
                Section("A-Alerts: toestel zoeken") {
                    Label("Zoek een gebruiker op met het toestel-ID uit de app (Instellingen, onder Disclaimer): toestel, appversie en pushinstellingen", systemImage: "magnifyingglass")
                    Label("Stuur dat toestel meteen een testmelding", systemImage: "bell.badge")
                }
                Section("A-Alerts: gemelde fouten") {
                    Label("Gemelde fouten: meldingen die gebruikers als onjuist aangeven, met reden, toelichting en de juiste plek", systemImage: "exclamationmark.bubble")
                    Label("Afhandelen, heropenen of de melding meteen bewerken; een pushmelding bij elke nieuwe melding", systemImage: "checkmark.circle")
                }
                Section("A-Alerts: hulp in de app") {
                    Label("Teksten › Hulp en veelgestelde vragen: de hulppagina van de app en a-alerts.nl/hulp aanpassen", systemImage: "questionmark.circle")
                }
                Section("Pasr: pushmeldingen") {
                    Label("Meldingen van Pasr (nieuwe accounts, winkelaanvragen) komen nu ook in LRbeheer aan", systemImage: "bell.badge.fill")
                }
                Section("Pasr: saldo-pagina's") {
                    Label("Winkels › Saldo: per winkel de pagina waar je het tegoed van een cadeaukaart nakijkt", systemImage: "eurosign.circle")
                    Label("Alle cadeaukaarten uit de app staan klaar: alleen het adres invullen, met een zoekknop", systemImage: "list.bullet.rectangle")
                    Label("Werkt ook voor winkels die al in de app zitten, zonder app-update", systemImage: "arrow.down.app")
                }
                Section("Pasr: review-account") {
                    Label("Accounts › Review-account maken: bevestigd account voor Apple App Review met voorbeeldkaarten en een gedeelde Pasr", systemImage: "person.badge.key")
                    Label("Zelf een wachtwoord kiezen of een sterk wachtwoord laten maken; de server bewaart het niet", systemImage: "key.fill")
                }
                Section("Pasr: winkels zonder update") {
                    Label("Tabblad Winkels: aanvragen uit de app, gebundeld per winkel, ook cadeaukaarten en vouchers", systemImage: "storefront")
                    Label("Website opzoeken: logo en merkkleuren automatisch, of zelf een logo kiezen", systemImage: "wand.and.stars")
                    Label("Publiceren zonder app-update; aanvragen worden gesloten en de aanvragers krijgen een pushmelding", systemImage: "paperplane")
                    Label("Pushmelding bij een nieuwe winkelaanvraag (schakelaar Winkel aangevraagd)", systemImage: "bell.badge")
                }
                Section("Pasr: delen") {
                    Label("Kerncijfers Gedeelde Pasrs (met personen en kaarten) en Tijdelijk gedeeld (nu geldig)", systemImage: "person.2.fill")
                    Label("Kaart Delen: uitnodigingen, gedeelde kaarten, keren geopend en eerder gestopt", systemImage: "clock.badge.checkmark")
                    Label("Insights: reeksen Gedeelde Pasrs en Tijdelijk gedeeld; per account het aantal gedeelde Pasrs", systemImage: "chart.bar.xaxis")
                }
                Section("Bingr: omzet van Apple") {
                    Label("Omzet: website (Stripe) en Apple (App Store) apart, met bruto, inhouding, netto opbrengst, aantal en terugbetaald", systemImage: "chart.bar.doc.horizontal")
                    Label("Apple-cijfers uit App Store Connect, met Apple bijgewerkt t/m en gekoppelde aankopen", systemImage: "apple.logo")
                    Label("Reeksen Website en Apple in de grafiek en de knop Apple-omzet bijwerken", systemImage: "arrow.clockwise")
                    Label("Apple-commissie en vaste koersen instellen", systemImage: "eurosign.circle")
                }
                Section("Bingr: nieuwe accounts eerst kopen") {
                    Label("Lifetime-only: Nieuwe accounts eerst kopen, apart voor web en Android en voor de Apple-apps, met bevestiging", systemImage: "cart.badge.plus")
                    Label("Waarschuwing als de datum voor de Apple-apps staat terwijl de Apple-koopknop uit staat", systemImage: "exclamationmark.triangle")
                }
                Section("Bekendr") {
                    Label("Nieuwe omgeving Bekendr, met dezelfde beheer-inlog", systemImage: "app.badge")
                    Label("Downloads per apparaat: iPhone, iPad en Mac uit App Store Connect", systemImage: "iphone")
                    Label("Android: downloads van de APK, totaal en per versie", systemImage: "arrow.down.circle")
                    Label("Grafiek met downloads per dag over 30 dagen", systemImage: "chart.bar.xaxis")
                    Label("Ook op het web: bekendr.lrvdlinden.app/beheer", systemImage: "safari")
                    Label("Feedback uit de app: wat er niet klopt aan een bekendmaking, met reden en toelichting", systemImage: "exclamationmark.bubble")
                    Label("Feedback afhandelen of verwijderen; ook op bekendr.lrvdlinden.app/beheer", systemImage: "checkmark.circle")
                }
                Section("Bingr: Lifetime-only") {
                    Label("Instellingen → Lifetime-only: aankondiging, overgangsdatum, korting, proefperiode, Apple-koopknop en EU-link, met bevestiging", systemImage: "star.circle")
                    Label("Kortingscodes genereren (droog en echt) met de totalen", systemImage: "ticket")
                    Label("Mail Bingr wordt Lifetime testen en versturen, en de herinnering", systemImage: "envelope")
                    Label("Niet geclaimde aankopen, en een aankoop handmatig aan een account koppelen", systemImage: "link")
                    Label("Gebruikers: kortingscode en status bij het account", systemImage: "person.text.rectangle")
                    Label("Omzet: per aanbieder (website via Stripe en Apple)", systemImage: "eurosign.circle")
                }
                Section("A-Alerts: status") {
                    Label("Nieuw tabblad Status: alle onderdelen van a-alerts.nl/status met uptime en foutmelding", systemImage: "waveform.path.ecg")
                    Label("Storing of gepland onderhoud melden, bijwerken en afronden; staat direct op de statuspagina en in de apps", systemImage: "exclamationmark.bubble")
                    Label("Pushmelding zodra iets afwijkt van normaal en weer als het hersteld is (schakelaar Storingen en afwijkingen)", systemImage: "bell.badge")
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
                    Label("Echte Mac-app met menubalk (⌘1…⌘7 wisselt van omgeving)", systemImage: "macbook")
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
