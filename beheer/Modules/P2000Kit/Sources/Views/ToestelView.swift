import SwiftUI

// MARK: - Toestel zoeken: the Toestel-ID a user reads in the app (Instellingen, under Disclaimer).
// GET /v1/beheer/toestel/:code, POST /v1/beheer/toestel/:code/test

struct ToestelZoekResultaat: Decodable { let gevonden: Int; let toestellen: [GevondenToestel] }

struct GevondenToestel: Decodable, Identifiable {
    struct Push: Decodable, Identifiable {
        let id: String
        let platform: String
        let omgeving: String
        let app_version: String?
        let aan: Bool
        let stille_uren: Bool
        let straal_km: Double?
        let bijgewerkt: String?
        let profielen: Int
        let heli_zones: Int
        let groot_incident: Bool
        let capcodes: Int
    }
    var id: String { code }
    let code: String
    let platform: String
    let model: String?
    let os: String?
    let app_version: String?
    let build: String?
    let apple_login: Bool
    let push_aan: Bool
    let eerst: String
    let laatst: String
    let push: [Push]
}

private struct TestResultaat: Decodable {
    struct R: Decodable { let platform: String; let ok: Bool; let status: Int?; let reason: String? }
    let ok: Bool
    let resultaten: [R]
}
private struct LeegBody: Encodable {}

struct ToestelView: View {
    @Environment(Session.self) private var session
    @State private var code = ""
    @State private var resultaat: ToestelZoekResultaat?
    @State private var error: String?
    @State private var bezig = false
    @State private var testTekst: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Toestel-ID, bijv. 3F9A-12BC", text: $code)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await zoek() } }
                        Button("Zoek") { Task { await zoek() } }.disabled(code.count < 6 || bezig)
                    }
                } footer: {
                    Text("De gebruiker vindt het toestel-ID in de app bij Instellingen, onder Disclaimer.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                if let r = resultaat, r.gevonden == 0 {
                    ContentUnavailableView("Niet gevonden", systemImage: "questionmark.circle",
                                           description: Text("Geen toestel met dit ID. Heeft de app al eens verbinding gehad?"))
                }
                ForEach(resultaat?.toestellen ?? []) { t in
                    Section(t.code) {
                        LabeledContent("Toestel", value: "\(t.model ?? "?") · \(t.platform) \(t.os ?? "")")
                        LabeledContent("App", value: "\(t.app_version ?? "?") (\(t.build ?? "?"))")
                        LabeledContent("Pushmeldingen in de app", value: t.push_aan ? "aan" : "uit")
                        LabeledContent("Inloggen met Apple", value: t.apple_login ? "ja" : "nee")
                        LabeledContent("Eerst gezien", value: FoutenView.datum(t.eerst))
                        LabeledContent("Laatst gezien", value: FoutenView.datum(t.laatst))
                        if t.push.isEmpty {
                            Text("Geen pushregistratie gekoppeld: pushmeldingen staan uit, of de app is ouder dan build 56.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(t.push) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(p.platform) · \(p.omgeving) · \(p.app_version ?? "")").font(.subheadline.bold())
                                Text([p.aan ? "aan" : "uit", p.stille_uren ? "stille uren" : nil, p.straal_km.map { "\(Int($0)) km" },
                                      "\(p.profielen) profiel(en)", "\(p.heli_zones) heli-zone(s)", p.groot_incident ? "groot incident" : nil,
                                      p.capcodes > 0 ? "\(p.capcodes) capcode(s)" : nil, p.bijgewerkt.map { "bijgewerkt \(FoutenView.datum($0))" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if !t.push.isEmpty {
                            Button("Stuur testmelding") { Task { await test(t.code) } }
                            if let tekst = testTekst[t.code] { Text(tekst).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Toestel zoeken")
        }
    }

    private func zoek() async {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard c.count >= 6 else { return }
        bezig = true; defer { bezig = false }
        do {
            resultaat = try await session.call { try await BeheerAPI.shared.getJSON("v1/beheer/toestel/\(c)", token: $0) }
            error = nil
        } catch { self.error = error.localizedDescription; resultaat = nil }
    }

    private func test(_ c: String) async {
        testTekst[c] = "Versturen…"
        do {
            let r: TestResultaat = try await session.call { try await BeheerAPI.shared.sendJSON("POST", "v1/beheer/toestel/\(c)/test", body: LeegBody(), token: $0) }
            testTekst[c] = r.resultaten.map { "\($0.platform): \($0.ok ? "verstuurd" : "mislukt (\($0.status ?? 0) \($0.reason ?? ""))")" }.joined(separator: " · ")
        } catch { testTekst[c] = error.localizedDescription }
    }
}
