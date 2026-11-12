import Charts
import SwiftUI

/// Beheeromgeving Noodpakket: downloads, Android-builds en berichten aan de gebruikers.
/// Zelfde gegevens en inlog als het web-beheer op noodpakket.lrvdlinden.app/beheer/.
struct NoodpakketRoot: View {
    @State private var store = NoodpakketStore.shared

    var body: some View {
        Group {
            if store.isSignedIn {
                NoodpakketMain(store: store)
            } else {
                NoodpakketLoginView(store: store)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

enum NoodpakketPalette {
    /// Huisstijl van Noodpakket: diep paars en warm geel.
    static let purple = Color(rgb: 0x3C175B)
    static let brand = Color(light: 0x5A2E85, dark: 0xC9A6F0)
    static let yellow = Color(rgb: 0xF4B943)
    static let iPhone = Color(light: 0x5A2E85, dark: 0xC9A6F0)
    static let iPad = Color(rgb: 0xE08A1E)
    static let android = Color(rgb: 0x2E8B57)
    static let other = Color(rgb: 0x8A91A3)
}

// MARK: overzicht

struct NoodpakketMain: View {
    @Bindable var store: NoodpakketStore
    @State private var confirmSignOut = false
    @State private var section = Part.overview
    @Environment(\.openURL) private var openURL

    enum Part: Hashable { case overview, messages }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Onderdeel", selection: $section) {
                    Text("Overzicht").tag(Part.overview)
                    Text("Berichten").tag(Part.messages)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: 520)
                if section == .overview { overview } else { NoodpakketMessagesView(store: store) }
            }
            .background(Theme.bg)
            .navigationTitle("Noodpakket")
            .toolbar { toolbar }
            .task { if store.stats == nil { await store.load() } }
            .confirmationDialog("Uitloggen bij Noodpakket?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Uitloggen", role: .destructive) { store.signOut() }
            }
        }
        .tint(NoodpakketPalette.brand)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let e = store.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lrCard()
                }
                if let s = store.stats {
                    content(s)
                } else if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ContentUnavailableView("Nog geen gegevens", systemImage: "arrow.down.circle",
                                           description: Text("Trek omlaag om de gegevens op te halen."))
                }
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.load() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await store.load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") }
                .disabled(store.loading)
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button { openURL(NoodpakketStore.web) } label: { Label("Web-beheer openen", systemImage: "safari") }
                Button { openURL(NoodpakketStore.site) } label: { Label("noodpakket.lrvdlinden.app", systemImage: "globe") }
                Button { openURL(NoodpakketStore.releases) } label: { Label("Releases op GitHub", systemImage: "shippingbox") }
                Button { openURL(NoodpakketStore.actions) } label: { Label("Android-builds op GitHub", systemImage: "hammer") }
                Divider()
                Button(role: .destructive) { confirmSignOut = true } label: { Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right") }
            } label: { Label("Meer", systemImage: "ellipsis.circle") }
        }
    }

    @ViewBuilder private func content(_ s: NoodpakketStats) -> some View {
        if !s.apple.configured {
            Label("App Store Connect is nog niet gekoppeld; alleen Android wordt geteld. Zet APPSTORE_CONNECT_P8 en VENDOR_APPSTORE_CONNECT in app.lrvdlinden.secrets en start LRbeheer push.",
                  systemImage: "info.circle")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lrCard()
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            BekendrTile(title: "Totaal", value: s.total, symbol: "arrow.down.circle.fill", color: NoodpakketPalette.brand,
                        note: "Apple + Android")
            BekendrTile(title: "iPhone", value: s.apple.device("iPhone"), symbol: "iphone", color: NoodpakketPalette.iPhone)
            BekendrTile(title: "iPad", value: s.apple.device("iPad"), symbol: "ipad", color: NoodpakketPalette.iPad)
            BekendrTile(title: "Android", value: s.android.total, symbol: "apps.iphone", color: NoodpakketPalette.android,
                        note: "APK-downloads")
            BekendrTile(title: "Ontvangers", value: s.devices.total, symbol: "bell.badge.fill", color: NoodpakketPalette.yellow,
                        note: "Berichten aan")
        }

        BekendrDaysChart(days: s.days)

        builds(s)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Android").font(Theme.display(.headline))
                Spacer()
                Text(s.android.total.formatted()).font(.headline.monospacedDigit())
            }
            if !s.android.available {
                Text("GitHub was niet bereikbaar; probeer het zo opnieuw.").font(.caption).foregroundStyle(Theme.build)
            }
            if s.android.releases.isEmpty && s.android.available {
                Text("Nog geen release. Een tag vX.Y.Z maakt een release met noodpakket.apk.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(s.android.releases) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(verbatim: r.name).font(.subheadline)
                            if r.tag == s.android.latest {
                                Text("Nieuwste").font(.caption2.weight(.bold)).foregroundStyle(NoodpakketPalette.purple)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(NoodpakketPalette.yellow, in: Capsule())
                            }
                        }
                        if let d = r.date {
                            Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(r.downloads.formatted()).font(.subheadline.monospacedDigit())
                }
                if r.id != s.android.releases.last?.id { Divider() }
            }
            Text("Downloads van de APK in GitHub Releases (ook via de vaste link op de website).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()

        VStack(alignment: .leading, spacing: 10) {
            Text("Apple").font(Theme.display(.headline))
            LabeledContent("Eerste downloads", value: s.apple.downloads.formatted())
            LabeledContent("Opnieuw gedownload", value: s.apple.redownloads.formatted())
            LabeledContent("Updates", value: s.apple.updates.formatted())
            if let d = s.apple.lastDay.flatMap({ BekendrStats.dayFormatter.date(from: $0) }) {
                Text("Laatste dag van App Store Connect: \(d.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Uit de dagelijkse verkoopoverzichten van App Store Connect; die komen een dag later binnen.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()

        VStack(alignment: .leading, spacing: 10) {
            Text("Ontvangers van berichten").font(Theme.display(.headline))
            LabeledContent("iPhone en iPad (pushmelding)", value: s.devices.apple.formatted())
            LabeledContent("Android (laatste 30 dagen actief)", value: s.devices.android.formatted())
            LabeledContent("Nederlands", value: s.devices.nl.formatted())
            LabeledContent("Engels", value: s.devices.en.formatted())
            Text("Alleen apparaten waarop Berichten van Noodpakket aan staat. Geen account of persoonsgegevens.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()

        if let d = s.syncedDate {
            Text("Bijgewerkt \(d.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func builds(_ s: NoodpakketStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Android-builds").font(Theme.display(.headline))
                Spacer()
                Button { openURL(NoodpakketStore.actions) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Android-builds op GitHub")
            }
            if s.builds.isEmpty {
                Text("Nog geen builds, of GitHub was niet bereikbaar.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(s.builds) { b in
                Button {
                    if let u = URL(string: b.url), !b.url.isEmpty { openURL(u) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: b.isRunning ? "clock.fill" : b.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(b.isRunning ? Theme.build : b.succeeded ? Theme.good : Theme.bad)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: b.title).font(.subheadline).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(b.stateLabel)
                                if let d = b.date { Text(verbatim: "·"); Text(d.formatted(.relative(presentation: .named))) }
                                if !b.branch.isEmpty { Text(verbatim: "· \(b.branch)") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if b.id != s.builds.last?.id { Divider() }
            }
            if s.builds.first.map({ $0.status == "queued" }) == true {
                Text("Staat een build lang in de wachtrij, kijk dan in GitHub Actions naar de limieten van je account.")
                    .font(.caption).foregroundStyle(Theme.build)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
    }
}

// MARK: berichten

/// Bericht opstellen en versturen, met een voorbeeld van de melding; eerder verstuurde berichten met bereik en intrekken.
struct NoodpakketMessagesView: View {
    @Bindable var store: NoodpakketStore
    @State private var draft = NoodpakketDraft()
    @State private var confirm = false
    @State private var result: String?
    @State private var failure: String?
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Titel", text: $draft.title, axis: .vertical)
                    .focused($focused)
                TextField("Tekst", text: $draft.body, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focused)
                TextField("Link (optioneel, https://)", text: $draft.link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
            } header: {
                Text("Nieuw bericht")
            } footer: {
                HStack {
                    Text("Titel \(draft.titleCount)/80 · tekst \(draft.bodyCount)/400")
                    if !draft.linkOK { Text("· link moet met https:// beginnen").foregroundStyle(Theme.bad) }
                }
            }
            Section("Voor wie") {
                Picker("Apparaten", selection: $draft.platform) {
                    Text("Alle apparaten").tag(NoodpakketDraft.Platform.all)
                    Text("iPhone en iPad").tag(NoodpakketDraft.Platform.apple)
                    Text(verbatim: "Android").tag(NoodpakketDraft.Platform.android)
                }
                Picker("Taal van de app", selection: $draft.lang) {
                    Text("Alle talen").tag(NoodpakketDraft.Lang.all)
                    Text("Nederlands").tag(NoodpakketDraft.Lang.nl)
                    Text("Engels").tag(NoodpakketDraft.Lang.en)
                }
                if let d = store.stats?.devices {
                    LabeledContent("Bereik (ongeveer)", value: reach(d).formatted())
                }
            }
            Section("Voorbeeld") {
                preview
            }
            Section {
                Button {
                    Task { await send(test: true) }
                } label: { Label("Test naar mijn LRbeheer", systemImage: "iphone.radiowaves.left.and.right") }
                    .disabled(!draft.isValid || store.sending)
                Button {
                    focused = false
                    confirm = true
                } label: {
                    HStack {
                        if store.sending { ProgressView() }
                        Label("Versturen", systemImage: "paperplane.fill").bold()
                    }
                }
                .disabled(!draft.isValid || store.sending)
            } footer: {
                Text("iPhone en iPad krijgen direct een pushmelding. Android haalt nieuwe berichten zelf op, binnen een paar uur. Gebruik berichten alleen voor wat er echt toe doet, zoals een oproep om je pakket na te lopen.")
            }
            if let result {
                Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
            }

            Section("Verstuurd") {
                let list = store.stats?.messages ?? []
                if list.isEmpty {
                    Text("Nog geen berichten verstuurd.").foregroundStyle(.secondary)
                }
                ForEach(list) { m in
                    messageRow(m)
                        .swipeActions(edge: .trailing) {
                            if !m.withdrawn {
                                Button(role: .destructive) { Task { await store.withdraw(m) } } label: {
                                    Label("Intrekken", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                        .contextMenu {
                            Button { draft = NoodpakketDraft(title: m.title, body: m.body, link: m.url,
                                                             lang: .init(rawValue: m.lang) ?? .all, platform: .init(rawValue: m.platform) ?? .all) } label: {
                                Label("Opnieuw gebruiken", systemImage: "doc.on.doc")
                            }
                            if !m.withdrawn {
                                Button(role: .destructive) { Task { await store.withdraw(m) } } label: {
                                    Label("Intrekken", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .refreshable { await store.load() }
        .confirmationDialog("Bericht versturen?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Versturen") { Task { await send(test: false) } }
        } message: {
            Text("\(draft.title)\n\nNaar ongeveer \(reach(store.stats?.devices).formatted()) apparaten. Dit kan niet worden teruggedraaid op iPhone en iPad.")
        }
        .sensoryFeedback(.success, trigger: result)
    }

    private func reach(_ d: NoodpakketStats.Devices?) -> Int {
        guard let d else { return 0 }
        let n: Int = switch draft.platform {
        case .all: d.total
        case .apple: d.apple
        case .android: d.android
        }
        guard draft.lang != .all, d.nl + d.en > 0 else { return n }
        let share = Double(draft.lang == .nl ? d.nl : d.en) / Double(d.nl + d.en)
        return Int((Double(n) * share).rounded())
    }

    /// Zo ziet de melding er ongeveer uit op het toegangsscherm.
    private var preview: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("Env/noodpakket").resizable().frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: "Noodpakket").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("nu").font(.caption).foregroundStyle(.secondary)
                }
                Text(draft.title.isEmpty ? String(localized: "Titel van je bericht") : draft.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(draft.title.isEmpty ? .secondary : .primary)
                if !draft.body.isEmpty { Text(draft.body).font(.subheadline).lineLimit(4) }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .listRowBackground(LinearGradient(colors: [NoodpakketPalette.purple, Color(rgb: 0x2E0F47)], startPoint: .top, endPoint: .bottom))
        .accessibilityElement(children: .combine)
    }

    private func messageRow(_ m: NoodpakketStats.Message) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: m.title).font(.subheadline.weight(.semibold)).strikethrough(m.withdrawn)
                Spacer()
                if m.withdrawn { Text("Ingetrokken").font(.caption.weight(.semibold)).foregroundStyle(Theme.build) }
            }
            if !m.body.isEmpty { Text(verbatim: m.body).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
            HStack(spacing: 6) {
                if let d = m.date { Text(d.formatted(date: .abbreviated, time: .shortened)) }
                Text(verbatim: "· \(m.audience)")
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if m.platform != "android" {
                    count(m.sentApple, "iphone").help("Afgeleverd op iPhone en iPad")
                    if m.failedApple > 0 { count(m.failedApple, "xmark.circle").foregroundStyle(Theme.bad).help("Niet afgeleverd") }
                }
                if m.platform != "apple" { count(m.fetchedAndroid, "apps.iphone").help("Opgehaald door Android") }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func count(_ n: Int, _ symbol: String) -> some View {
        Label { Text(verbatim: n.formatted()) } icon: { Image(systemName: symbol) }
    }

    private func send(test: Bool) async {
        result = nil
        failure = nil
        do {
            result = try await store.send(draft, test: test)
            if !test { draft = NoodpakketDraft() }
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: inloggen

struct NoodpakketLoginView: View {
    let store: NoodpakketStore
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case user, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Env/noodpakket")
                    .resizable().scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 84 * 0.2237, style: .continuous))
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Noodpakket beheer").font(Theme.display(.title2))
                    Text(verbatim: "noodpakket.lrvdlinden.app/beheer").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    TextField("Gebruikersnaam", text: $user)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .user)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Wachtwoord", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                }
                .textFieldStyle(.roundedBorder)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: signIn) {
                    HStack {
                        if busy { ProgressView().tint(NoodpakketPalette.purple) }
                        Text("Inloggen").bold().foregroundStyle(NoodpakketPalette.purple)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(NoodpakketPalette.yellow)
                .disabled(busy || user.isEmpty || password.isEmpty)
                Text("De gedeelde beheer-inlog. Je sessie (12 uur) wordt alleen op dit apparaat bewaard, in de sleutelhanger.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.error, trigger: error)
    }

    private func signIn() {
        guard !busy, !user.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await store.signIn(user: user.trimmingCharacters(in: .whitespaces), password: password)
                password = ""
                await store.load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
