import SwiftUI
import Charts

// MARK: - Models (A-Alerts: GET /v1/beheer/overview → aAlerts, GET /v1/beheer/waarschuwingen)

struct AAlertsOverview: Decodable {
    struct Bron: Decodable {
        let naam: String
        let laatsteStatus: String?
        let laatstOk: String?
        let laatsteFout: String?
        let storing: Bool
    }
    struct Heli: Decodable, Identifiable {
        let naam: String
        let soort: String
        let hoogte_m: Int?
        let snelheid_kmh: Int?
        let gezien: String
        var id: String { naam }
    }
    struct Telling: Decodable { let actief: Int; let week: Int }
    struct Waarschuwingen: Decodable { let perBron: [String: Telling]; let verborgen: Int }
    struct Knmi: Decodable { let yellow: Int; let orange: Int; let red: Int }
    struct Wil: Decodable { let nlalert: Int; let burgernet: Int; let knmi: Knmi }
    struct Plaats: Decodable, Identifiable { let plaats: String; let n: Int; var id: String { plaats } }
    struct Profielen: Decodable {
        let pushToestellen: Int
        let metProfielen: Int
        let zonderProfielen: Int
        let gemiddeld: Double
        let verdeling: [String: Int]
        let metTijden: Int
        let allesUit: Int
        let waarschuwingen: Wil
        let topPlaatsen: [Plaats]
    }
    let bronnen: [String: Bron]
    let inDeLucht: [Heli]
    let waarschuwingen: Waarschuwingen
    let profielen: Profielen
}

struct AdminWaarschuwing: Codable, Identifiable, Hashable {
    let id: String
    let bron: String
    let titel: String?
    let tekst: String?
    let plaats: String?
    let niveau: String?
    let soort: String?
    let status: String
    let start: String
    let einde: String?
    let link: String?
    var verborgen: Bool
    var handmatig_beeindigd: Bool

    var bronNaam: String { WaarschuwingStijl.naam(bron) }
    var kop: String {
        if bron == "knmi" { return "\(WaarschuwingStijl.code(niveau)) · \(soort ?? "KNMI")" }
        if bron == "burgernet" { return "Burgernet · \(plaats ?? "Apeldoorn")" }
        if bron == "amber" { return "AMBER Alert" }
        if bron == "vermistkind" { return "Vermist Kind Alert · \(plaats ?? "Apeldoorn")" }
        return "NL-Alert"
    }
}

enum WaarschuwingStijl {
    static let bronnen = ["nlalert", "burgernet", "knmi", "amber", "vermistkind"]
    static func naam(_ b: String) -> String {
        switch b { case "nlalert": "NL-Alert"; case "burgernet": "Burgernet"; case "knmi": "KNMI"; case "amber": "AMBER Alert"; case "vermistkind": "Vermist Kind Alert"; case "kind": "AMBER Alert / Vermist Kind (Burgernet)"; case "helikopters": "Helikopters (adsb.lol)"; case "verkeer": "Verkeer (NDW, Koyeb)"; default: b }
    }
    static func code(_ n: String?) -> String {
        switch n { case "yellow": "Code geel"; case "orange": "Code oranje"; case "red": "Code rood"; default: "Code" }
    }
    static func color(_ b: String, _ niveau: String? = nil) -> Color {
        switch b {
        case "nlalert": return Color(red: 1, green: 0.78, blue: 0)
        case "burgernet": return Color(red: 0, green: 0.4, blue: 0.69)
        case "amber", "kind": return Color(red: 0.93, green: 0.43, blue: 0.14)
        case "vermistkind": return Color(red: 0.11, green: 0.15, blue: 0.37)
        default:
            switch niveau { case "red": return .red; case "orange": return .orange; default: return Color(red: 1, green: 0.84, blue: 0) }
        }
    }
    static func symbol(_ b: String) -> String {
        switch b { case "nlalert": "exclamationmark.triangle.fill"; case "burgernet": "megaphone.fill"; case "amber", "vermistkind", "kind": "figure.child"; case "helikopters": "airplane"; default: "cloud.sun.rain.fill" }
    }
    static func status(_ s: String) -> String {
        switch s { case "actief": "Actief"; case "verwacht": "Verwacht"; case "beeindigd": "Beëindigd"; default: s }
    }
}

/// Zelfde iconen als in de A-Alerts-app: NL-Alert-driehoek en Burgernet-huisje; KNMI als gekleurd vlak.
struct WaarschuwingIcoon: View {
    let bron: String
    var niveau: String? = nil
    var size: CGFloat = 32

    var body: some View {
        // KNMI with a code shows the code colour; without one the KNMI tile, like the app.
        if bron == "nlalert" || bron == "burgernet" || (bron == "knmi" && niveau == nil) {
            Image("aalerts_icon_\(bron)")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: WaarschuwingStijl.symbol(bron))
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(niveau == "yellow" ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(WaarschuwingStijl.color(bron, niveau), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        }
    }
}

// MARK: - API

extension BeheerAPI {
    func waarschuwingen(bron: String?, status: String?, query: String, token: String) async throws -> [AdminWaarschuwing] {
        var q = ["days": "30"]
        if let bron { q["bron"] = bron }
        if let status { q["status"] = status }
        if !query.isEmpty { q["q"] = query }
        return try await getJSON("v1/beheer/waarschuwingen", query: q, token: token)
    }

    struct WaarschuwingUpdate: Encodable { var verborgen: Bool?; var beeindigd: Bool? }

    func updateWaarschuwing(_ id: String, _ change: WaarschuwingUpdate, token: String) async throws -> AdminWaarschuwing {
        try await sendJSON("PATCH", "v1/beheer/waarschuwingen/\(id)", body: change, token: token)
    }
}

// MARK: - Dashboard cards

struct AAlertsDashboardCards: View {
    let a: AAlertsOverview

    var body: some View {
        bronnenCard
        heliCard
        waarschuwingenCard
        profielenCard
    }

    private var bronnenCard: some View {
        Card(title: "A-Alerts-bronnen", icon: "antenna.radiowaves.left.and.right") {
            ForEach(["nlalert", "burgernet", "knmi", "kind", "verkeer", "helikopters"], id: \.self) { key in
                if let b = a.bronnen[key] {
                    StatusRow(ok: !b.storing, title: WaarschuwingStijl.naam(key),
                              detail: b.storing ? (b.laatsteFout ?? "geen gegevens") : "\(Fmt.relative(b.laatstOk)) · \(b.laatsteStatus ?? "")")
                }
            }
            Text("Storing = langer dan 30 minuten geen gegevens. Je krijgt dan een pushmelding als 'Storing bronnen' aan staat.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var heliCard: some View {
        Card(title: "Helikopters in de lucht", icon: "airplane") {
            if a.inDeLucht.isEmpty {
                EmptyChart(text: "Er is nu geen Lifeliner of Zulu in de lucht.")
            } else {
                ForEach(a.inDeLucht) { h in
                    HStack {
                        Image(systemName: "airplane")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Dienst.color(h.soort == "trauma" ? "traumaheli" : "politie"), in: Circle())
                        Text(h.naam).font(.callout.weight(.semibold))
                        Spacer()
                        Text([h.hoogte_m.map { $0 == 0 ? "op de grond" : "\($0) m" }, h.snelheid_kmh.map { "\($0) km/u" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var waarschuwingenCard: some View {
        Card(title: "Waarschuwingen", icon: "exclamationmark.triangle") {
            Chart(WaarschuwingStijl.bronnen, id: \.self) { b in
                BarMark(x: .value("Bron", WaarschuwingStijl.naam(b)), y: .value("Aantal", a.waarschuwingen.perBron[b]?.week ?? 0))
                    .foregroundStyle(WaarschuwingStijl.color(b, "orange"))
                    .annotation(position: .top) { Text("\(a.waarschuwingen.perBron[b]?.week ?? 0)").font(.caption2) }
            }
            .frame(height: 140)
            HStack {
                ForEach(WaarschuwingStijl.bronnen, id: \.self) { b in
                    LegendDot(color: WaarschuwingStijl.color(b, "orange"), title: "\(WaarschuwingStijl.naam(b)): \(a.waarschuwingen.perBron[b]?.actief ?? 0) actief")
                }
            }
            Text("Laatste 7 dagen\(a.waarschuwingen.verborgen > 0 ? " · \(a.waarschuwingen.verborgen) verborgen" : "")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var profielenCard: some View {
        Card(title: "Notificatieprofielen", icon: "person.2.badge.gearshape") {
            let p = a.profielen
            if p.metProfielen == 0 {
                EmptyChart(text: "Nog geen toestellen met profielen. Dat begint bij A-Alerts 1.0.0 (17).")
            } else {
                Chart((1...5).map { "\($0)" }, id: \.self) { n in
                    BarMark(x: .value("Profielen", n), y: .value("Toestellen", p.verdeling[n] ?? 0))
                        .foregroundStyle(Theme.red)
                }
                .frame(height: 110)
                LegendRow(color: Theme.red, title: "Toestellen met profielen", value: p.metProfielen)
                LegendRow(color: .gray, title: "Nog zonder profielen (oudere versie)", value: p.zonderProfielen)
                LegendRow(color: .indigo, title: "Met eigen tijden", value: p.metTijden)
                if p.allesUit > 0 { LegendRow(color: .secondary, title: "Alle profielen uit", value: p.allesUit) }
                Divider()
                LegendRow(color: WaarschuwingStijl.color("nlalert"), title: "Wil NL-Alert", value: p.waarschuwingen.nlalert)
                LegendRow(color: WaarschuwingStijl.color("burgernet"), title: "Wil Burgernet", value: p.waarschuwingen.burgernet)
                LegendRow(color: .orange, title: "Wil KNMI geel / oranje / rood",
                          value: p.waarschuwingen.knmi.yellow + p.waarschuwingen.knmi.orange + p.waarschuwingen.knmi.red)
                    .help("\(p.waarschuwingen.knmi.yellow) / \(p.waarschuwingen.knmi.orange) / \(p.waarschuwingen.knmi.red)")
                if !p.topPlaatsen.isEmpty {
                    Divider()
                    Text("Populairste plaatsen").font(.caption.weight(.semibold))
                    ForEach(p.topPlaatsen.prefix(6)) { pl in
                        HStack { Text(pl.plaats).font(.callout); Spacer(); Text("\(pl.n)").font(.callout.monospacedDigit()) }
                    }
                }
                Text("Gemiddeld \(p.gemiddeld.formatted(.number.precision(.fractionLength(1)))) profiel per toestel · \(p.pushToestellen) toestellen met push")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Waarschuwingen tab

struct WaarschuwingenView: View {
    @Environment(Session.self) private var session
    @State private var items: [AdminWaarschuwing] = []
    @State private var bron: String?
    @State private var status: String?
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(text: error).listRowBackground(Color.clear) }
                Section {
                    Picker("Bron", selection: $bron) {
                        Text("Alle bronnen").tag(String?.none)
                        ForEach(WaarschuwingStijl.bronnen, id: \.self) { Text(WaarschuwingStijl.naam($0)).tag(Optional($0)) }
                    }
                    Picker("Status", selection: $status) {
                        Text("Alle").tag(String?.none)
                        ForEach(["actief", "verwacht", "beeindigd"], id: \.self) { Text(WaarschuwingStijl.status($0)).tag(Optional($0)) }
                    }
                }
                Section {
                    if items.isEmpty && !loading {
                        Text("Geen waarschuwingen in de laatste 30 dagen.").foregroundStyle(.secondary)
                    }
                    ForEach(items) { w in
                        NavigationLink { WaarschuwingBeheerView(item: w) { updated in replace(updated) } } label: { row(w) }
                            .swipeActions {
                                Button(w.verborgen ? "Tonen" : "Verberg") { Task { await change(w, .init(verborgen: !w.verborgen)) } }
                                    .tint(w.verborgen ? .green : .gray)
                            }
                    }
                } footer: {
                    Text("Verbergen haalt een waarschuwing weg uit de apps en de website. Beëindigen zet hem op beëindigd als de bron dat niet zelf doet. De brongegevens blijven ongewijzigd.")
                }
            }
            .searchable(text: $query)
            .navigationTitle("Waarschuwingen")
            .toolbar {
                ToolbarItem {
                    Button { Task { await load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") }
                }
            }
            .refreshable { await load() }
            .task(id: "\(bron ?? "")|\(status ?? "")|\(query)") {
                try? await Task.sleep(for: .milliseconds(250))
                await load()
            }
        }
    }

    private func row(_ w: AdminWaarschuwing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            WaarschuwingIcoon(bron: w.bron, niveau: w.niveau, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(w.kop).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(w.titel ?? "–").font(.callout.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(WaarschuwingStijl.status(w.status))
                    Text("·")
                    Text(Fmt.relative(w.start))
                    if w.verborgen { Label("Verborgen", systemImage: "eye.slash").foregroundStyle(.orange) }
                    if w.handmatig_beeindigd { Label("Handmatig", systemImage: "hand.raised").foregroundStyle(.orange) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .opacity(w.verborgen ? 0.55 : 1)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await session.call { try await BeheerAPI.shared.waarschuwingen(bron: bron, status: status, query: query, token: $0) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func change(_ w: AdminWaarschuwing, _ c: BeheerAPI.WaarschuwingUpdate) async {
        do {
            let updated = try await session.call { try await BeheerAPI.shared.updateWaarschuwing(w.id, c, token: $0) }
            replace(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func replace(_ w: AdminWaarschuwing) {
        if let i = items.firstIndex(where: { $0.id == w.id }) { items[i] = w }
    }
}

struct WaarschuwingBeheerView: View {
    @Environment(Session.self) private var session
    @State var item: AdminWaarschuwing
    var onChange: (AdminWaarschuwing) -> Void
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Form {
            if let error { ErrorBanner(text: error) }
            Section {
                LabeledContent("Bron", value: item.bronNaam)
                LabeledContent("Status", value: WaarschuwingStijl.status(item.status))
                if let p = item.plaats { LabeledContent("Plaats", value: p) }
                if let s = item.soort { LabeledContent("Soort", value: s) }
                if item.bron == "knmi" { LabeledContent("Code", value: WaarschuwingStijl.code(item.niveau)) }
                LabeledContent("Start", value: Fmt.parse(item.start).map(Fmt.dateTime) ?? item.start)
                if let e = item.einde { LabeledContent("Einde", value: Fmt.parse(e).map(Fmt.dateTime) ?? e) }
                if let l = item.link, let url = URL(string: l) { Link("Bekijk bij de bron", destination: url) }
            }
            Section("Bericht") {
                Text(item.titel ?? "–").font(.headline)
                if let t = item.tekst, t != item.titel { Text(t).font(.callout).textSelection(.enabled) }
            }
            Section {
                Toggle("Verbergen in apps en website", isOn: Binding(get: { item.verborgen }, set: { v in Task { await change(.init(verborgen: v)) } }))
                Toggle("Handmatig beëindigd", isOn: Binding(get: { item.handmatig_beeindigd }, set: { v in Task { await change(.init(beeindigd: v)) } }))
            } footer: {
                Text("Werkt direct in de apps (binnen een minuut). Zet je het terug, dan geldt weer wat de bron zegt.")
            }
            .disabled(busy)
            Section { Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .formStyle(.grouped)
        .navigationTitle(item.bronNaam)
    }

    private func change(_ c: BeheerAPI.WaarschuwingUpdate) async {
        busy = true
        defer { busy = false }
        do {
            let updated = try await session.call { try await BeheerAPI.shared.updateWaarschuwing(item.id, c, token: $0) }
            item = updated
            onChange(updated)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
