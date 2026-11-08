import SwiftUI

// MARK: - Gemelde fouten ("Klopt deze melding niet?"): GET /v1/beheer/feedback, POST/DELETE /v1/beheer/feedback/:id

struct GemeldeFout: Decodable, Identifiable, Hashable {
    let id: Int
    let guid: String
    let reden: String
    let toelichting: String?
    let lat: Double?
    let lon: Double?
    let platform: String?
    let at: String
    let status: String
    let title: String?
    let stad: String?

    static let redenen = ["locatie": "De plek klopt niet", "dienst": "Verkeerde hulpdienst", "prioriteit": "Verkeerde prioriteit",
                          "dubbel": "Dubbele melding", "test": "Test- of proefalarm", "anders": "Iets anders"]
    var redenTekst: String { Self.redenen[reden] ?? reden }
    var isOpen: Bool { status == "open" }
}

private struct FoutenAntwoord: Decodable { let open: Int; let items: [GemeldeFout] }
private struct StatusBody: Encodable { let status: String }
private struct OK: Decodable { let ok: Bool? }

struct FoutenView: View {
    @Environment(Session.self) private var session
    @State private var filter = "open"
    @State private var items: [GemeldeFout] = []
    @State private var open = 0
    @State private var error: String?
    @State private var bewerk: AdminMelding?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                if items.isEmpty && error == nil {
                    ContentUnavailableView("Geen gemelde fouten", systemImage: "checkmark.seal",
                                           description: Text("Gebruikers melden dit anoniem via \"Klopt deze melding niet?\" onderaan een melding."))
                }
                ForEach(items) { f in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(f.redenTekst).font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background((f.isOpen ? Color.orange : Color.blue).opacity(0.18), in: Capsule())
                            Spacer()
                            Text(Self.datum(f.at)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(f.title ?? "(melding verwijderd)").font(.headline)
                        if let s = f.stad, !s.isEmpty { Text(s.capitalized).font(.subheadline).foregroundStyle(.secondary) }
                        if let t = f.toelichting, !t.isEmpty { Text(t).font(.callout) }
                        HStack(spacing: 12) {
                            Text(f.platform ?? "?").font(.caption).foregroundStyle(.secondary)
                            if let lat = f.lat, let lon = f.lon, let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=Juiste%20plek") {
                                Link("Juiste plek", destination: url).font(.caption)
                            }
                            if let url = URL(string: "https://a-alerts.nl/melding/\(f.guid)") { Link("Melding", destination: url).font(.caption) }
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await verwijder(f) } } label: { Label("Verwijder", systemImage: "trash") }
                        Button { Task { await zet(f, f.isOpen ? "afgehandeld" : "open") } } label: {
                            Label(f.isOpen ? "Afgehandeld" : "Heropen", systemImage: f.isOpen ? "checkmark" : "arrow.uturn.backward")
                        }
                        .tint(f.isOpen ? .green : .blue)
                    }
                    .contextMenu {
                        Button(f.isOpen ? "Afgehandeld" : "Heropen") { Task { await zet(f, f.isOpen ? "afgehandeld" : "open") } }
                        if f.title != nil { Button("Bewerk melding") { Task { await openMelding(f.guid) } } }
                        Button("Verwijder", role: .destructive) { Task { await verwijder(f) } }
                    }
                }
            }
            .navigationTitle("Gemelde fouten")
            .toolbar {
                ToolbarItem {
                    Picker("Filter", selection: $filter) {
                        Text("Open (\(open))").tag("open")
                        Text("Afgehandeld").tag("afgehandeld")
                        Text("Alles").tag("")
                    }
                    .pickerStyle(.menu)
                }
            }
            .onChange(of: filter) { _, _ in Task { await load() } }
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $bewerk) { m in MeldingEditView(melding: m) { _ in } }
        }
    }

    private func load() async {
        do {
            let r: FoutenAntwoord = try await session.call {
                try await BeheerAPI.shared.getJSON("v1/beheer/feedback", query: filter.isEmpty ? [:] : ["status": filter], token: $0)
            }
            items = r.items; open = r.open; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func zet(_ f: GemeldeFout, _ status: String) async {
        do {
            let _: OK = try await session.call { try await BeheerAPI.shared.sendJSON("POST", "v1/beheer/feedback/\(f.id)", body: StatusBody(status: status), token: $0) }
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func verwijder(_ f: GemeldeFout) async {
        do {
            let _: OK = try await session.call { try await BeheerAPI.shared.sendJSON("DELETE", "v1/beheer/feedback/\(f.id)", body: StatusBody(status: ""), token: $0) }
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func openMelding(_ guid: String) async {
        do { bewerk = try await session.call { try await BeheerAPI.shared.getJSON("v1/beheer/meldingen/\(guid)", token: $0) } }
        catch { self.error = error.localizedDescription }
    }

    static func datum(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}
