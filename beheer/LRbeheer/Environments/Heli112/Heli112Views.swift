import Charts
import SwiftUI

/// Beheeromgeving 112Heli: status, toestellen, meldingen van gebruikers en eigen pushberichten.
/// Zelfde gegevens en inlog als het web-beheer op 112heli.lrvdlinden.app/beheer.
struct Heli112Root: View {
    @State private var store = Heli112Store.shared

    var body: some View {
        Group {
            if store.isSignedIn {
                Heli112Main(store: store)
            } else {
                Heli112LoginView(store: store)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

enum Heli112Palette {
    static let brand = Color(light: 0x2747E8, dark: 0x4C6BFF)
    static let red = Color(rgb: 0xE11D48)
    static let air = Color(light: 0x16A34A, dark: 0x34D399)
}

// MARK: hoofdscherm met onderdelen

struct Heli112Main: View {
    @Bindable var store: Heli112Store
    @State private var section: Section = .overview
    @State private var confirmSignOut = false
    @Environment(\.openURL) private var openURL

    enum Section: String, CaseIterable, Identifiable {
        case overview, aircraft, reports, push
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .overview: "Overzicht"
            case .aircraft: "Toestellen"
            case .reports: "Meldingen"
            case .push: "Pushbericht"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Onderdeel", selection: $section) {
                        ForEach(Section.allCases) { s in
                            if s == .reports && store.openReports > 0 {
                                Text("Meldingen (\(store.openReports))").tag(s)
                            } else {
                                Text(s.title).tag(s)
                            }
                        }
                    }
                    .pickerStyle(.segmented)

                    if let e = store.error {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Theme.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lrCard()
                    }

                    if let o = store.overview {
                        switch section {
                        case .overview: Heli112OverviewView(overview: o)
                        case .aircraft: Heli112AircraftView(aircraft: store.aircraft)
                        case .reports: Heli112ReportsView(store: store)
                        case .push: Heli112PushView(store: store)
                        }
                    } else if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        ContentUnavailableView("Nog geen gegevens", systemImage: "antenna.radiowaves.left.and.right",
                                               description: Text("Trek omlaag om de gegevens op te halen."))
                    }
                }
                .padding(16)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await store.load() }
            .background(Theme.bg)
            .navigationTitle("112Heli")
            .toolbar { toolbar }
            .task { if store.overview == nil { await store.load() } }
            .confirmationDialog("Uitloggen bij 112Heli?", isPresented: $confirmSignOut, titleVisibility: .visible) {
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
                Button { openURL(Heli112Store.web) } label: { Label("Web-beheer openen", systemImage: "safari") }
                Button { openURL(Heli112Store.site) } label: { Label(String("112heli.lrvdlinden.app"), systemImage: "globe") }
                Divider()
                Button(role: .destructive) { confirmSignOut = true } label: { Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right") }
            } label: { Label("Meer", systemImage: "ellipsis.circle") }
        }
    }
}

// MARK: overzicht

struct Heli112OverviewView: View {
    let overview: Heli112Overview

    var body: some View {
        let t = overview.tellers
        let inzetNote: LocalizedStringKey = t.actieveInzetten > 0 ? "\(t.actieveInzetten) nu actief" : "7 dagen"
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            BekendrTile(title: "Nu in de lucht", value: t.inLucht, symbol: "airplane", color: Heli112Palette.air,
                        note: "\(t.gezien24) gezien in 24 uur")
            BekendrTile(title: "Vluchten vandaag", value: t.vluchtenVandaag, symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        color: Heli112Palette.brand, note: "\(t.vluchten7) in 7 dagen")
            BekendrTile(title: "Grote inzetten", value: t.inzetten7, symbol: "exclamationmark.triangle.fill", color: Heli112Palette.red,
                        note: inzetNote)
            BekendrTile(title: "Apparaten", value: t.apparaten, symbol: "iphone", color: Heli112Palette.brand,
                        note: "\(t.apparatenAan) met meldingen aan")
            BekendrTile(title: "Eigen zones", value: t.metZones, symbol: "mappin.circle.fill", color: Theme.good,
                        note: "Apparaten met een zone")
            BekendrTile(title: "Live Activities", value: t.liveActivities, symbol: "lock.iphone", color: Theme.good,
                        note: "Nu gevolgd")
            BekendrTile(title: "Toestellen", value: t.toestellen, symbol: "list.bullet", color: .secondary,
                        note: "Bekend bij 112Heli")
            BekendrTile(title: "Open meldingen", value: t.openMeldingen, symbol: "exclamationmark.bubble.fill", color: Theme.build,
                        note: "Van gebruikers")
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vluchten per dag").font(Theme.display(.headline))
                Spacer()
                Text("14 dagen").font(.caption).foregroundStyle(.secondary)
            }
            Chart(overview.dagen) { d in
                BarMark(x: .value("Dag", d.date, unit: .day), y: .value("Vluchten", d.vluchten))
                    .foregroundStyle(Heli112Palette.brand)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .frame(height: 200)
            Text("Nieuwe apparaten in deze periode: \(overview.dagen.reduce(0) { $0 + $1.apparaten })")
                .font(.caption).foregroundStyle(.secondary)
        }
        .lrCard()

        let s = overview.status
        VStack(alignment: .leading, spacing: 10) {
            Text("Server").font(Theme.display(.headline))
            LabeledContent("Ophalen posities") {
                HStack(spacing: 6) {
                    Image(systemName: s.ingestOk ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(s.ingestOk ? Theme.good : Theme.bad)
                    if let l = s.lastIngest {
                        Text(Date(timeIntervalSince1970: l), format: .relative(presentation: .named))
                    } else {
                        Text("Nooit")
                    }
                }
            }
            LabeledContent("Pushmeldingen (APNs)") { Heli112Flag(ok: s.apns) }
            LabeledContent("Apple Kaarten (website)") { Heli112Flag(ok: s.mapkit) }
            LabeledContent("Weerbeperking") {
                if let w = s.weer { Text(Date(timeIntervalSince1970: w), format: .relative(presentation: .named)) } else { Text("Nooit") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()

        VStack(alignment: .leading, spacing: 10) {
            Text("Vluchten per soort (7 dagen)").font(Theme.display(.headline))
            if overview.perSoort.isEmpty {
                Text("Nog geen vluchten.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(overview.perSoort) { r in LabeledContent(r.label, value: r.n.formatted()) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()

        VStack(alignment: .leading, spacing: 10) {
            Text("Apparaten").font(Theme.display(.headline))
            if overview.platforms.isEmpty {
                Text("Nog geen apparaten met meldingen.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(overview.platforms) { r in LabeledContent(r.label, value: r.n.formatted()) }
            if !overview.versies.isEmpty {
                Text("Versies").font(.subheadline.weight(.semibold)).padding(.top, 6)
                ForEach(overview.versies) { r in LabeledContent(r.label, value: r.n.formatted()) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
    }
}

struct Heli112Flag: View {
    let ok: Bool
    var body: some View {
        Label(ok ? LocalizedStringKey("Ingesteld") : LocalizedStringKey("Niet ingesteld"), systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
            .foregroundStyle(ok ? Theme.good : Theme.bad)
    }
}

// MARK: toestellen

struct Heli112AircraftView: View {
    let aircraft: [Heli112Aircraft]
    @State private var query = ""
    @Environment(\.openURL) private var openURL

    private var filtered: [Heli112Aircraft] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return aircraft }
        return aircraft.filter { a in
            [a.naam, a.reg, a.callsign, a.hex, a.type].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
        }
    }

    var body: some View {
        TextField("Zoek op naam, registratie, roepnaam of hex", text: $query)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        VStack(alignment: .leading, spacing: 0) {
            if filtered.isEmpty {
                Text("Niets gevonden.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(filtered) { a in
                Button {
                    if let u = URL(string: "https://112heli.lrvdlinden.app/toestel/?hex=\(a.hex)") { openURL(u) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(verbatim: a.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                if a.inLucht {
                                    Text("In de lucht").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Heli112Palette.air, in: Capsule())
                                }
                            }
                            Text(verbatim: [a.soortNaam, a.type, a.reg, a.callsign].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            if let d = a.seenDate {
                                Text(d, format: .relative(presentation: .named)).font(.caption)
                            } else {
                                Text("Nooit gezien").font(.caption)
                            }
                            Text("\(a.vluchten30) vluchten").font(.caption2).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if a.id != filtered.last?.id { Divider() }
            }
        }
        .lrCard()

        Text("\(aircraft.count) toestellen. Gegevens komen automatisch uit de herkenning van A-Alerts; corrigeren doe je daar.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: meldingen van gebruikers

struct Heli112ReportsView: View {
    @Bindable var store: Heli112Store
    @State private var deleting: Heli112Report?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.reports.isEmpty {
                Text("Nog geen meldingen van gebruikers.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(store.reports) { r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: r.tekst).font(.subheadline)
                        Spacer()
                        Heli112StatusTag(status: r.status)
                    }
                    Text(verbatim: [r.naam ?? String(localized: "Toestel ontbreekt"), r.reg, r.hex, Heli112Soort.name(r.soort)]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(r.date.formatted(date: .abbreviated, time: .shortened))
                        if let p = r.platform { Text(verbatim: Heli112Overview.platformName(p)) }
                        if let v = r.appVersion { Text(verbatim: v) }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        if r.status == "opgelost" {
                            Button("Heropenen") { Task { await store.setStatus(r, "nieuw") } }
                        } else {
                            Button("Opgelost") { Task { await store.setStatus(r, "opgelost") } }
                        }
                        if r.status == "nieuw" {
                            Button("Bekeken") { Task { await store.setStatus(r, "bekeken") } }
                        }
                        Spacer()
                        Button("Verwijderen", role: .destructive) { deleting = r }
                    }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 10)
                if r.id != store.reports.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
        .confirmationDialog("Deze melding verwijderen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) {
                if let r = deleting { Task { await store.delete(r) } }
                deleting = nil
            }
        }

        Text("Meldingen uit de app: \"Dit toestel klopt niet\" en \"Toestel ontbreekt\".")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct Heli112StatusTag: View {
    let status: String
    var body: some View {
        let color: Color = switch status {
        case "nieuw": Heli112Palette.red
        case "opgelost": Theme.good
        default: .secondary
        }
        Text(verbatim: status).font(.caption2.weight(.bold)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color, in: Capsule())
    }
}

// MARK: pushbericht

struct Heli112PushView: View {
    @Bindable var store: Heli112Store
    @State private var title = ""
    @State private var text = ""
    @State private var soorten: Set<String> = []
    @State private var reach: Int?
    @State private var busy = false
    @State private var confirm = false
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nieuw pushbericht").font(Theme.display(.headline))
            TextField("Titel (optioneel)", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Tekst", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            Text("Alleen naar apparaten die deze soorten volgen (niets gekozen = iedereen)")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Heli112Soort.all, id: \.id) { s in
                    Toggle(isOn: Binding(get: { soorten.contains(s.id) }, set: { on in
                        if on { soorten.insert(s.id) } else { soorten.remove(s.id) }
                    })) { Text(s.name) }
                    .toggleStyle(.button)
                    .tint(Heli112Palette.brand)
                }
            }
            Text(reach.map { String(format: String(localized: "Bereik: %lld apparaten"), $0) } ?? String(localized: "Bereik: …"))
                .font(.subheadline).foregroundStyle(.secondary)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.bad)
            }
            if let result {
                Label(result, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(Theme.good)
            }
            Button {
                confirm = true
            } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text("Versturen").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Heli112Palette.brand)
            .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Gaat naar iPhone, iPad en Mac met meldingen aan, met het eigen 112Heli-geluid.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
        .task(id: soorten) { reach = await store.reach(soorten: soorten) }
        .confirmationDialog("Dit pushbericht nu versturen?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Versturen", action: send)
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("Verstuurd").font(Theme.display(.headline))
            if store.messages.isEmpty {
                Text("Nog geen berichten verstuurd.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(store.messages) { m in
                VStack(alignment: .leading, spacing: 3) {
                    if let t = m.titel { Text(verbatim: t).font(.subheadline.weight(.semibold)) }
                    Text(verbatim: m.tekst).font(.subheadline)
                    HStack(spacing: 6) {
                        Text(m.date.formatted(date: .abbreviated, time: .shortened))
                        Text(verbatim: m.soorten.isEmpty ? String(localized: "Iedereen") : m.soorten.map { Heli112Soort.name($0) }.joined(separator: ", "))
                        Text("\(m.ok) van \(m.bereik)")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                if m.id != store.messages.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard()
    }

    private func send() {
        busy = true
        error = nil
        result = nil
        Task {
            defer { busy = false }
            do {
                let r = try await store.send(title: title.trimmingCharacters(in: .whitespaces),
                                             text: text.trimmingCharacters(in: .whitespacesAndNewlines), soorten: soorten)
                result = String(format: String(localized: "Verstuurd naar %lld van %lld apparaten."), r.verstuurd, r.bereik)
                title = ""
                text = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: inloggen

struct Heli112LoginView: View {
    let store: Heli112Store
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case user, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Env/heli112")
                    .resizable().scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 84 * 0.2237, style: .continuous))
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("112Heli beheer").font(Theme.display(.title2))
                    Text(verbatim: "112heli.lrvdlinden.app/beheer").font(.subheadline).foregroundStyle(.secondary)
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
                .tint(Heli112Palette.brand)
                .disabled(busy || user.isEmpty || password.isEmpty)
                Text("De gedeelde beheer-inlog. Je sessie (30 dagen) wordt alleen op dit apparaat bewaard, in de sleutelhanger.")
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
