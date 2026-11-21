import SwiftUI
import Charts

// MARK: - Bronnen: GET /v1/beheer/bronnen (api.a-alerts.nl)
// Every source of the own server with its state, plus how complete the P2000 alerts of the last 24 hours are.

struct BeheerBronnen: Decodable {
    struct Dekking: Decodable {
        let meldingen: Int
        let capcodes: Int
        let prioriteit: Int
        let dienst: Int
        let plaats: Int
        let regio: Int
        let straat: Int
        let opschaling: Int
        let locatie: Int
    }
    struct P2000: Decodable {
        let bron: String
        let dekking: Dekking
        let perBron: [String: Int]?
        let perUur: [Int]
    }
    struct Bron: Decodable, Identifiable {
        let id: String
        let naam: String
        let staat: String
        let laatst: String?
        let detail: String?
    }
    struct Tabel: Decodable, Identifiable {
        var id: String { tabel }
        let tabel: String
        let label: String
        let aantal: Int?
    }
    let bijgewerkt: String
    let p2000: P2000
    let bronnen: [Bron]
    let database: Bool
    let tabellen: [Tabel]
}

extension BeheerAPI {
    func bronnen(token: String) async throws -> BeheerBronnen { try await getJSON("v1/beheer/bronnen", token: token) }
}

struct BronnenView: View {
    @Environment(Session.self) private var session
    @State private var data: BeheerBronnen?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { ErrorBanner(text: error) }
                    if let d = data {
                        p2000Kaart(d.p2000)
                        dekkingKaart(d.p2000.dekking)
                        Card(title: "Bronnen", icon: "antenna.radiowaves.left.and.right") {
                            ForEach(d.bronnen) { b in bronRij(b) }
                        }
                        Card(title: "Database (MySQL)", icon: "cylinder.split.1x2") {
                            StatusRow(ok: d.database, title: "Verbinding", detail: d.database ? "bereikbaar" : "niet bereikbaar")
                            ForEach(d.tabellen) { t in
                                HStack {
                                    Text(t.label)
                                    Spacer()
                                    Text(t.aantal.map { $0.formatted() } ?? "—").monospacedDigit().foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                        Text("Bijgewerkt \(Fmt.relative(d.bijgewerkt)) · api.a-alerts.nl")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if error == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding()
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Bronnen")
            .toolbar { ToolbarItem { Button { Task { await load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") } } }
            .refreshable { await load() }
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    private func p2000Kaart(_ p: BeheerBronnen.P2000) -> some View {
        Card(title: "P2000 · \(p.bron)", icon: "light.beacon.max.fill") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(p.dekking.meldingen.formatted()).font(.system(size: 40, weight: .bold)).monospacedDigit()
                Text("meldingen in de laatste 24 uur").foregroundStyle(.secondary)
            }
            Chart(Array(p.perUur.enumerated()), id: \.offset) { item in
                BarMark(x: .value("Uur", item.offset - 23), y: .value("Meldingen", item.element))
                    .foregroundStyle(Color.red.gradient)
            }
            .chartXAxis {
                AxisMarks(values: [-23, -18, -12, -6, 0]) { v in
                    AxisValueLabel { if let h = v.as(Int.self) { Text(h == 0 ? "nu" : "\(h) u") } }
                }
            }
            .frame(height: 120)
            if let per = p.perBron, !per.isEmpty {
                Text(per.sorted { $0.value > $1.value }.map { "\($0.key): \($0.value)" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Share of the alerts with the field filled, as in the comparison of P2000 sources.
    private func dekkingKaart(_ d: BeheerBronnen.Dekking) -> some View {
        let velden: [(String, Int)] = [("Capcodes", d.capcodes), ("Prioriteit", d.prioriteit), ("Dienst", d.dienst), ("Plaats", d.plaats),
                                       ("Regio", d.regio), ("Straat", d.straat), ("Plek op kaart", d.locatie), ("Opschaling", d.opschaling)]
        return Card(title: "Dekking van de velden", icon: "square.grid.3x3.fill") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(velden, id: \.0) { naam, pct in
                    VStack(spacing: 4) {
                        Text("\(pct)%").font(.title3.bold()).monospacedDigit()
                        Text(naam).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(pct >= 50 ? .white : .primary)
                    .background(Color.blue.opacity(0.15 + 0.85 * Double(pct) / 100), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Text("Aandeel van de meldingen van de laatste 24 uur waarin het veld is ingevuld. Opschaling staat alleen bij meldingen met GRIP of opschaling, dus een laag percentage is normaal.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func bronRij(_ b: BeheerBronnen.Bron) -> some View {
        let kleur: Color = switch b.staat {
        case "live", "ok": .green
        case "overname", "gepland": .blue
        case "uit": .gray
        default: .orange
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(kleur).frame(width: 9, height: 9)
                Text(b.naam).font(.callout.weight(.semibold))
                Spacer()
                if let l = b.laatst { Text(Fmt.relative(l)).font(.caption).foregroundStyle(.secondary) }
            }
            if let d = b.detail, !d.isEmpty {
                Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do {
            data = try await session.call { try await BeheerAPI.shared.bronnen(token: $0) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
