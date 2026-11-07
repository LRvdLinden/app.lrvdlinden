import SwiftUI

// MARK: - Status (a-alerts.nl/status): GET /v1/beheer/status, incidents via /v1/beheer/status/incidenten

struct BeheerStatus: Decodable {
    struct Dag: Decodable { let dag: String; let staat: String }
    struct Onderdeel: Decodable, Identifiable {
        let id: String
        let naam: String
        let staat: String
        let detail: String?
        let uptime: Double?
        let fout: String?
        let dagen: [Dag]
    }
    struct Groep: Decodable, Identifiable { let id: String; let naam: String; let onderdelen: [Onderdeel] }
    struct Update: Decodable { let at: String; let fase: String; let tekst: String }
    struct Incident: Decodable, Identifiable {
        let id: Int
        let titel: String
        let soort: String
        let onderdelen: [String]
        let start: String
        let einde: String?
        let gepland_start: String?
        let gepland_einde: String?
        let updates: [Update]
    }
    struct Incidenten: Decodable { let actief: [Incident]; let gepland: [Incident]; let recent: [Incident] }
    struct Afwijking: Decodable, Identifiable { let id: String; let tekst: String }
    let bijgewerkt: String
    let staat: String
    let groepen: [Groep]
    let incidenten: Incidenten
    let afwijkingen: [Afwijking]?
}

enum StatusStijl {
    static func kleur(_ s: String) -> Color {
        switch s {
        case "ok": Color(red: 0.086, green: 0.639, blue: 0.290)
        case "warn": Color(red: 0.961, green: 0.620, blue: 0.043)
        case "down": Color(red: 0.863, green: 0.149, blue: 0.149)
        case "maint": Color(red: 0.231, green: 0.510, blue: 0.965)
        default: .gray
        }
    }
    static func label(_ s: String) -> String {
        ["ok": "Werkt", "warn": "Verstoord", "down": "Storing", "maint": "Onderhoud"][s] ?? "Geen gegevens"
    }
    static let soorten = [("storing", "Storing"), ("vertraagd", "Verstoord / vertraagd"), ("onderhoud", "Gepland onderhoud")]
    static func soort(_ s: String) -> String { soorten.first { $0.0 == s }?.1 ?? s }
    static let fasen = [("onderzoek", "Onderzoek"), ("oorzaak", "Oorzaak gevonden"), ("herstel", "Herstel"), ("monitoren", "Monitoren"),
                        ("opgelost", "Opgelost"), ("gepland", "Gepland"), ("bezig", "Bezig"), ("afgerond", "Afgerond")]
    static func fase(_ s: String) -> String { fasen.first { $0.0 == s }?.1 ?? s }
}

extension BeheerAPI {
    struct NieuwIncident: Encodable {
        var soort: String
        var titel: String
        var titel_en: String?
        var onderdelen: [String]
        var tekst: String
        var tekst_en: String?
        var gepland_start: String?
        var gepland_einde: String?
    }
    struct IncidentUpdate: Encodable { var fase: String?; var tekst: String; var tekst_en: String?; var opgelost: Bool }
    struct OK: Decodable { let ok: Bool? }

    func beheerStatus(token: String) async throws -> BeheerStatus { try await getJSON("v1/beheer/status", token: token) }
    func maakIncident(_ i: NieuwIncident, token: String) async throws -> BeheerStatus.Incident {
        try await sendJSON("POST", "v1/beheer/status/incidenten", body: i, token: token)
    }
    func updateIncident(_ id: Int, _ u: IncidentUpdate, token: String) async throws -> BeheerStatus.Incident {
        try await sendJSON("POST", "v1/beheer/status/incidenten/\(id)", body: u, token: token)
    }
    func verwijderIncident(_ id: Int, token: String) async throws {
        let _: OK = try await sendJSON("DELETE", "v1/beheer/status/incidenten/\(id)", body: [String: String](), token: token)
    }
}

struct StatusBeheerView: View {
    @Environment(Session.self) private var session
    @State private var data: BeheerStatus?
    @State private var error: String?
    @State private var nieuw = false
    @State private var update: (id: Int, klaar: Bool)?

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(text: error).listRowBackground(Color.clear) }
                if let d = data {
                    Section {
                        HStack(spacing: 10) {
                            Circle().fill(StatusStijl.kleur(d.staat)).frame(width: 12, height: 12)
                            Text(d.staat == "ok" ? "Alle systemen werken" : "Status: \(StatusStijl.label(d.staat))").font(.headline)
                        }
                        Link(destination: URL(string: "https://a-alerts.nl/status/")!) { Label("Openbare statuspagina", systemImage: "safari") }
                    } footer: { Text("Bijgewerkt \(Fmt.relative(d.bijgewerkt))") }

                    if let a = d.afwijkingen, !a.isEmpty {
                        Section("Afwijkingen (alleen beheer)") {
                            ForEach(a) { Label($0.tekst, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        }
                    }
                    incidentSectie("Lopend", d.incidenten.actief, open: true)
                    incidentSectie("Gepland onderhoud", d.incidenten.gepland, open: true)
                    ForEach(d.groepen) { g in
                        Section(g.naam) {
                            ForEach(g.onderdelen) { o in onderdeelRij(o) }
                        }
                    }
                    incidentSectie("Afgelopen 30 dagen", d.incidenten.recent, open: false)
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Status")
            .toolbar {
                ToolbarItem { Button { nieuw = true } label: { Label("Storing melden", systemImage: "plus") } }
                ToolbarItem { Button { Task { await load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") } }
            }
            .refreshable { await load() }
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .sheet(isPresented: $nieuw) {
                NieuwIncidentSheet(onderdelen: data?.groepen.flatMap(\.onderdelen) ?? []) { await load() }
            }
            .sheet(isPresented: Binding(get: { update != nil }, set: { if !$0 { update = nil } })) {
                if let u = update { IncidentUpdateSheet(id: u.id, klaar: u.klaar) { await load() } }
            }
        }
    }

    private func onderdeelRij(_ o: BeheerStatus.Onderdeel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(StatusStijl.kleur(o.staat)).frame(width: 10, height: 10)
                Text(o.naam).font(.callout.weight(.semibold))
                Spacer()
                Text(StatusStijl.label(o.staat)).font(.caption).foregroundStyle(.secondary)
            }
            if let d = o.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
            if let f = o.fout { Text(f).font(.caption).foregroundStyle(.red) }
            HStack(spacing: 1) {
                ForEach(Array(o.dagen.suffix(30).enumerated()), id: \.offset) { _, d in
                    RoundedRectangle(cornerRadius: 1.5).fill(StatusStijl.kleur(d.staat))
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            if let u = o.uptime { Text("\(u.formatted(.number.precision(.fractionLength(0...2))))% uptime (90 dagen)").font(.caption2).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func incidentSectie(_ titel: String, _ list: [BeheerStatus.Incident], open: Bool) -> some View {
        if !list.isEmpty {
            Section(titel) {
                ForEach(list) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(StatusStijl.soort(i.soort)).font(.caption.weight(.bold)).foregroundStyle(i.soort == "onderhoud" ? .blue : .orange)
                        Text(i.titel).font(.callout.weight(.semibold))
                        ForEach(Array(i.updates.enumerated()), id: \.offset) { _, u in
                            Text("\(StatusStijl.fase(u.fase)) · \(Fmt.relative(u.at))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(u.tekst).font(.caption)
                        }
                    }
                    .swipeActions {
                        Button("Verwijder", role: .destructive) { Task { await verwijder(i.id) } }
                        if open {
                            Button(i.soort == "onderhoud" ? "Afgerond" : "Opgelost") { update = (i.id, true) }.tint(.green)
                            Button("Update") { update = (i.id, false) }.tint(.blue)
                        }
                    }
                    .contextMenu {
                        if open {
                            Button("Update plaatsen") { update = (i.id, false) }
                            Button(i.soort == "onderhoud" ? "Afgerond" : "Opgelost") { update = (i.id, true) }
                        }
                        Button("Verwijder", role: .destructive) { Task { await verwijder(i.id) } }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            data = try await session.call { try await BeheerAPI.shared.beheerStatus(token: $0) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verwijder(_ id: Int) async {
        do {
            try await session.call { try await BeheerAPI.shared.verwijderIncident(id, token: $0) }
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

private struct NieuwIncidentSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onderdelen: [BeheerStatus.Onderdeel]
    let done: () async -> Void
    @State private var soort = "storing"
    @State private var titel = ""
    @State private var tekst = ""
    @State private var titelEn = ""
    @State private var tekstEn = ""
    @State private var gekozen: Set<String> = []
    @State private var start = Date.now.addingTimeInterval(86_400)
    @State private var einde = Date.now.addingTimeInterval(86_400 + 900)
    @State private var bezig = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Soort", selection: $soort) { ForEach(StatusStijl.soorten, id: \.0) { Text($0.1).tag($0.0) } }
                TextField("Titel", text: $titel)
                TextField("Bericht", text: $tekst, axis: .vertical).lineLimit(3...6)
                if soort == "onderhoud" {
                    DatePicker("Begin", selection: $start)
                    DatePicker("Einde", selection: $einde)
                }
                Section("Onderdelen") {
                    ForEach(onderdelen) { o in
                        Toggle(o.naam, isOn: Binding(get: { gekozen.contains(o.id) }, set: { aan in
                            if aan { gekozen.insert(o.id) } else { gekozen.remove(o.id) }
                        }))
                    }
                }
                Section("Engels (optioneel)") {
                    TextField("Title", text: $titelEn)
                    TextField("Message", text: $tekstEn, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    if let error { Text(error).foregroundStyle(.red) }
                } footer: {
                    Text("Komt direct op a-alerts.nl/status en in de apps (Instellingen › Status). Gebruikers krijgen geen pushmelding.")
                }
            }
            .navigationTitle("Storing melden")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Plaats") { Task { await plaats() } }.disabled(bezig || titel.trimmingCharacters(in: .whitespaces).isEmpty || tekst.isEmpty)
                }
            }
        }
    }

    private func plaats() async {
        bezig = true
        defer { bezig = false }
        let iso = ISO8601DateFormatter()
        let body = BeheerAPI.NieuwIncident(soort: soort, titel: titel, titel_en: titelEn.isEmpty ? nil : titelEn, onderdelen: Array(gekozen),
                                           tekst: tekst, tekst_en: tekstEn.isEmpty ? nil : tekstEn,
                                           gepland_start: soort == "onderhoud" ? iso.string(from: start) : nil,
                                           gepland_einde: soort == "onderhoud" ? iso.string(from: einde) : nil)
        do {
            _ = try await session.call { try await BeheerAPI.shared.maakIncident(body, token: $0) }
            await done()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct IncidentUpdateSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let id: Int
    let klaar: Bool
    let done: () async -> Void
    @State private var fase = "oorzaak"
    @State private var tekst = ""
    @State private var tekstEn = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if !klaar {
                    Picker("Fase", selection: $fase) {
                        ForEach(StatusStijl.fasen.filter { !["opgelost", "afgerond", "gepland"].contains($0.0) }, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                TextField("Bericht", text: $tekst, axis: .vertical).lineLimit(3...6)
                TextField("Message (English, optional)", text: $tekstEn, axis: .vertical).lineLimit(2...5)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(klaar ? "Afronden" : "Update plaatsen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(klaar ? "Rond af" : "Plaats") { Task { await plaats() } }.disabled(!klaar && tekst.isEmpty) }
            }
            .onAppear {
                if klaar { tekst = "Opgelost: alles werkt weer normaal."; tekstEn = "Resolved: everything is working normally again." }
            }
        }
    }

    private func plaats() async {
        let u = BeheerAPI.IncidentUpdate(fase: klaar ? nil : fase, tekst: tekst, tekst_en: tekstEn.isEmpty ? nil : tekstEn, opgelost: klaar)
        do {
            _ = try await session.call { try await BeheerAPI.shared.updateIncident(id, u, token: $0) }
            await done()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
