import Charts
import SwiftUI

/// Beheeromgeving Pairr: downloads van de app op iPhone, iPad en Mac en de open meldingen op GitHub.
/// Zelfde gegevens en inlog als het web-beheer op pairr.lrvdlinden.app/beheer.
struct PairrRoot: View {
    @State private var store = PairrStore.shared

    var body: some View {
        Group {
            if store.isSignedIn {
                PairrMain(store: store)
            } else {
                PairrLoginView(store: store)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

enum PairrPalette {
    static let brand = Color(light: 0x0A8FD6, dark: 0x38C8FF)
    static let iPhone = Color(light: 0x0A8FD6, dark: 0x38C8FF)
    static let iPad = Color(light: 0x14A884, dark: 0x2ED3A3)
    static let mac = Color(light: 0x7B61FF, dark: 0xA08CFF)
    static let other = Color(rgb: 0x8A97A6)
}

// MARK: overzicht

struct PairrMain: View {
    @Bindable var store: PairrStore
    @State private var confirmSignOut = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
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
                                               description: Text("Trek omlaag om de downloads op te halen."))
                    }
                }
                .padding(16)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await store.load() }
            .background(Theme.bg)
            .navigationTitle("Pairr")
            .toolbar { toolbar }
            .task { if store.stats == nil { await store.load() } }
            .confirmationDialog("Uitloggen bij Pairr?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Uitloggen", role: .destructive) { store.signOut() }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await store.load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") }
                .disabled(store.loading)
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button { openURL(PairrStore.web) } label: { Label("Web-beheer openen", systemImage: "safari") }
                Button { openURL(PairrStore.site) } label: { Label(String("pairr.lrvdlinden.app"), systemImage: "globe") }
                Button { openURL(PairrStore.issues) } label: { Label("Meldingen op GitHub", systemImage: "exclamationmark.bubble") }
                Divider()
                Button(role: .destructive) { confirmSignOut = true } label: { Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right") }
            } label: { Label("Meer", systemImage: "ellipsis.circle") }
        }
    }

    @ViewBuilder private func content(_ s: PairrStats) -> some View {
        if !s.apple.configured {
            Label("App Store Connect is nog niet gekoppeld. Zet APPSTORE_CONNECT_P8 en VENDOR_APPSTORE_CONNECT in app.lrvdlinden.secrets en start LRbeheer push.",
                  systemImage: "info.circle")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lrCard()
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            BekendrTile(title: "Totaal", value: s.apple.downloads, symbol: "arrow.down.circle.fill", color: PairrPalette.brand,
                        note: "Eerste downloads")
            BekendrTile(title: "iPhone", value: s.apple.device("iPhone"), symbol: "iphone", color: PairrPalette.iPhone)
            BekendrTile(title: "iPad", value: s.apple.device("iPad"), symbol: "ipad", color: PairrPalette.iPad)
            BekendrTile(title: "Mac", value: s.apple.device("Mac"), symbol: "macbook", color: PairrPalette.mac)
            if let r = s.revenue {
                PairrMoneyTile(title: "Omzet", value: r.totalEur, note: String(format: String(localized: "Deze maand %@"), PairrMoney.eur(r.monthEur)))
            }
            BekendrTile(title: "Meldingen", value: s.issues.open, symbol: "exclamationmark.bubble.fill", color: Theme.build,
                        note: "Open op GitHub")
        }

        PairrDaysChart(days: s.days)

        VStack(alignment: .leading, spacing: 10) {
            Text("Apple").font(Theme.display(.headline))
            LabeledContent("Eerste downloads", value: s.apple.downloads.formatted())
            LabeledContent("Opnieuw gedownload", value: s.apple.redownloads.formatted())
            LabeledContent("Updates", value: s.apple.updates.formatted())
            if s.apple.otherDevices > 0 {
                LabeledContent("Andere apparaten", value: s.apple.otherDevices.formatted())
            }
            if let d = s.apple.lastDay.flatMap({ BekendrStats.dayFormatter.date(from: $0) }) {
                Text("Laatste dag van App Store Connect: \(d.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Uit de dagelijkse verkoopoverzichten van App Store Connect; die komen een dag later binnen. De Watch-app zit in de iPhone-download.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()

        if let r = s.revenue { PairrRevenueCard(revenue: r) }

        PairrIssuesCard(issues: s.issues)

        if let d = s.syncedDate {
            Text("Bijgewerkt \(d.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

enum PairrMoney {
    static func eur(_ v: Double) -> String { v.formatted(.currency(code: "EUR")) }
    static func amount(_ v: Double, _ code: String) -> String { v.formatted(.currency(code: code)) }
    static let color = Color(light: 0x0E9F6E, dark: 0x34D399)
}

struct PairrMoneyTile: View {
    let title: LocalizedStringKey
    let value: Double
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "eurosign.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PairrMoney.color)
            Text(PairrMoney.eur(value))
                .font(Theme.display(.title))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
    }
}

/// Omzet per dag (30 dagen) met totaal, deze maand, verkochte exemplaren en per valuta.
struct PairrRevenueCard: View {
    let revenue: PairrStats.Revenue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Omzet per dag").font(Theme.display(.headline))
                Spacer()
                Text("30 dagen, in euro").font(.caption).foregroundStyle(.secondary)
            }
            if revenue.days.allSatisfy({ $0.eur == 0 }) {
                Text("Nog geen verkopen in de afgelopen 30 dagen.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(revenue.days) { d in
                    BarMark(x: .value("Dag", d.date, unit: .day), y: .value("Euro", d.eur))
                        .foregroundStyle(PairrMoney.color)
                }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let e = v.as(Double.self) { Text(PairrMoney.eur(e)) } } } }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 200)
            }
            LabeledContent("Totaal (opbrengst)", value: PairrMoney.eur(revenue.totalEur))
            LabeledContent("Deze maand", value: PairrMoney.eur(revenue.monthEur))
            LabeledContent("Verkochte exemplaren", value: revenue.units.formatted())
            if revenue.byCurrency.count > 1 {
                ForEach(revenue.byCurrency.sorted { $0.value.proceeds > $1.value.proceeds }, id: \.key) { code, c in
                    LabeledContent {
                        Text(PairrMoney.amount(c.proceeds, code))
                    } label: {
                        Text(verbatim: code)
                        Text("\(c.units) verkocht")
                    }
                }
            }
            if revenue.unconverted > 0 {
                Text("\(revenue.unconverted) dag(en) in een valuta zonder ECB-koers; niet meegeteld in euro.")
                    .font(.caption).foregroundStyle(Theme.build)
            }
            Text("Opbrengst na Apple uit de dagelijkse verkoopoverzichten, terugbetalingen eraf. Andere valuta omgerekend met de ECB-koers; Apple betaalt later definitief uit in euro, dus het bedrag kan iets afwijken.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
    }
}

/// Open meldingen (GitHub Issues) van gebruikers; tikken opent de melding op GitHub.
struct PairrIssuesCard: View {
    let issues: PairrStats.Issues
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Meldingen").font(Theme.display(.headline))
                if issues.open > 0 {
                    Text("\(issues.open) open").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(PairrPalette.brand, in: Capsule())
                }
                Spacer()
                Button("Alle op GitHub") { openURL(PairrStore.issues) }
                    .font(.subheadline).buttonStyle(.borderless)
            }
            if !issues.available {
                Text("GitHub was niet bereikbaar; probeer het zo opnieuw.").font(.caption).foregroundStyle(Theme.build)
            } else if issues.items.isEmpty {
                Text("Geen open meldingen.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(issues.items) { i in
                Button {
                    if let u = i.link { openURL(u) }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "#\(i.number) \(i.title)").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if let d = i.date { Text(d.formatted(date: .abbreviated, time: .shortened)) }
                            if i.comments > 0 { Text("\(i.comments) reacties") }
                            ForEach(i.labels, id: \.self) { l in
                                Text(verbatim: l).font(.caption2.weight(.semibold)).foregroundStyle(PairrPalette.brand)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(PairrPalette.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(i.link == nil)
                if i.id != issues.items.last?.id { Divider() }
            }
            Text("Problemen en ideeën van gebruikers, via de supportpagina (GitHub Issues).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
    }
}

/// Downloads per dag, gestapeld per apparaat (laatste 30 dagen).
struct PairrDaysChart: View {
    let days: [PairrStats.Day]

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let platform: String
        let value: Int
    }

    private var points: [Point] {
        days.flatMap { d in
            [Point(date: d.date, platform: "iPhone", value: d.iPhone),
             Point(date: d.date, platform: "iPad", value: d.iPad),
             Point(date: d.date, platform: "Mac", value: d.Mac),
             Point(date: d.date, platform: String(localized: "Overig"), value: d.other)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Downloads per dag").font(Theme.display(.headline))
                Spacer()
                Text("30 dagen").font(.caption).foregroundStyle(.secondary)
            }
            if days.allSatisfy({ $0.total == 0 }) {
                Text("Nog geen downloads in de afgelopen 30 dagen. Apple komt een dag later binnen.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(points) { p in
                    BarMark(x: .value("Dag", p.date, unit: .day), y: .value("Downloads", p.value))
                        .foregroundStyle(by: .value("Platform", p.platform))
                }
                .chartForegroundStyleScale([
                    "iPhone": PairrPalette.iPhone, "iPad": PairrPalette.iPad, "Mac": PairrPalette.mac,
                    String(localized: "Overig"): PairrPalette.other,
                ])
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .chartLegend(position: .bottom)
                .frame(height: 220)
            }
        }
        .lrCard()
    }
}

// MARK: inloggen

struct PairrLoginView: View {
    let store: PairrStore
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case user, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Env/pairr")
                    .resizable().scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 84 * 0.2237, style: .continuous))
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Pairr beheer").font(Theme.display(.title2))
                    Text(verbatim: "pairr.lrvdlinden.app/beheer").font(.subheadline).foregroundStyle(.secondary)
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
                        if busy { ProgressView().tint(.white) }
                        Text("Inloggen").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(PairrPalette.brand)
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
