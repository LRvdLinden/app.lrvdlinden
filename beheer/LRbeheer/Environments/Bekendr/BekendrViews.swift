import Charts
import SwiftUI

/// Beheeromgeving Bekendr: downloads van de app op iPhone, iPad, Mac en Android.
/// Zelfde gegevens en inlog als het web-beheer op bekendr.lrvdlinden.app/beheer.
struct BekendrRoot: View {
    @State private var store = BekendrStore.shared

    var body: some View {
        Group {
            if store.isSignedIn {
                BekendrMain(store: store)
            } else {
                BekendrLoginView(store: store)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

enum BekendrPalette {
    static let brand = Color(rgb: 0x2747E8)
    static let iPhone = Color(rgb: 0x2747E8)
    static let iPad = Color(rgb: 0x7B4BD6)
    static let mac = Color(rgb: 0x0F8A8A)
    static let android = Color(rgb: 0x2E8B57)
    static let other = Color(rgb: 0x8A91A3)
}

// MARK: overzicht

struct BekendrMain: View {
    @Bindable var store: BekendrStore
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
            .navigationTitle("Bekendr")
            .toolbar { toolbar }
            .task { if store.stats == nil { await store.load() } }
            .confirmationDialog("Uitloggen bij Bekendr?", isPresented: $confirmSignOut, titleVisibility: .visible) {
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
                Button { openURL(BekendrStore.web) } label: { Label("Web-beheer openen", systemImage: "safari") }
                Button { openURL(BekendrStore.site) } label: { Label("bekendr.lrvdlinden.app", systemImage: "globe") }
                Divider()
                Button(role: .destructive) { confirmSignOut = true } label: { Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right") }
            } label: { Label("Meer", systemImage: "ellipsis.circle") }
        }
    }

    @ViewBuilder private func content(_ s: BekendrStats) -> some View {
        if !s.apple.configured {
            Label("App Store Connect is nog niet gekoppeld; alleen Android wordt geteld. Zet P8_APPSTORE_CONNECT en VENDOR_APPSTORE_CONNECT in app.lrvdlinden.secrets en start LRbeheer push.",
                  systemImage: "info.circle")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lrCard()
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            BekendrTile(title: "Totaal", value: s.total, symbol: "arrow.down.circle.fill", color: BekendrPalette.brand,
                        note: "Apple + Android")
            BekendrTile(title: "iPhone", value: s.apple.device("iPhone"), symbol: "iphone", color: BekendrPalette.iPhone)
            BekendrTile(title: "iPad", value: s.apple.device("iPad"), symbol: "ipad", color: BekendrPalette.iPad)
            BekendrTile(title: "Mac", value: s.apple.device("Mac"), symbol: "macbook", color: BekendrPalette.mac)
            BekendrTile(title: "Android", value: s.android.total, symbol: "apps.iphone", color: BekendrPalette.android,
                        note: "APK-downloads")
        }

        BekendrDaysChart(days: s.days)

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
            Text("Uit de dagelijkse verkoopoverzichten van App Store Connect; die komen een dag later binnen.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Android").font(Theme.display(.headline))
                Spacer()
                Text(s.android.total.formatted()).font(.headline.monospacedDigit())
            }
            if !s.android.available {
                Text("GitHub was niet bereikbaar; probeer het zo opnieuw.").font(.caption).foregroundStyle(Theme.build)
            }
            ForEach(s.android.releases) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: r.name).font(.subheadline)
                        if let d = r.date {
                            Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(r.downloads.formatted()).font(.subheadline.monospacedDigit())
                }
                if r.id != s.android.releases.last?.id { Divider() }
            }
            Text("Downloads van de APK in GitHub Releases (ook via de vaste link naar de nieuwste versie).")
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
}

struct BekendrTile: View {
    let title: LocalizedStringKey
    let value: Int
    let symbol: String
    let color: Color
    var note: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(value.formatted())
                .font(Theme.display(.title))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
    }
}

/// Downloads per dag, gestapeld per platform (laatste 30 dagen).
struct BekendrDaysChart: View {
    let days: [BekendrStats.Day]

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
             Point(date: d.date, platform: String(localized: "Overig"), value: d.other),
             Point(date: d.date, platform: "Android", value: d.android)]
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
                Text("Nog geen downloads in de afgelopen 30 dagen. Android telt per dag vanaf de eerste meting; Apple komt een dag later binnen.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(points) { p in
                    BarMark(x: .value("Dag", p.date, unit: .day), y: .value("Downloads", p.value))
                        .foregroundStyle(by: .value("Platform", p.platform))
                }
                .chartForegroundStyleScale([
                    "iPhone": BekendrPalette.iPhone, "iPad": BekendrPalette.iPad, "Mac": BekendrPalette.mac,
                    String(localized: "Overig"): BekendrPalette.other, "Android": BekendrPalette.android,
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

struct BekendrLoginView: View {
    let store: BekendrStore
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case user, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Env/bekendr")
                    .resizable().scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 84 * 0.2237, style: .continuous))
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Bekendr beheer").font(Theme.display(.title2))
                    Text(verbatim: "bekendr.lrvdlinden.app/beheer").font(.subheadline).foregroundStyle(.secondary)
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
                .tint(BekendrPalette.brand)
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
