import Foundation
import Observation

/// Beheer van 112Heli: status van de server, toestellen, meldingen van gebruikers en eigen pushberichten.
///
/// Praat met de eigen worker van 112Heli (Cloudflare, `112heli-api.112heli.workers.dev`), net als het web-beheer op
/// 112heli.lrvdlinden.app/beheer. Inloggen met de gedeelde beheer-inlog geeft een token van 30 dagen; dat staat alleen
/// in de sleutelhanger van dit apparaat.
@MainActor
@Observable
final class Heli112Store {
    static let shared = Heli112Store()
    static let api = URL(string: "https://112heli-api.112heli.workers.dev")!
    static let web = URL(string: "https://112heli.lrvdlinden.app/beheer/")!
    static let site = URL(string: "https://112heli.lrvdlinden.app")!

    struct Session: Codable { let token: String; let expires: Date }

    enum Failure: LocalizedError {
        case unauthorized, notConfigured, tooMany, network, decode
        case server(Int, String?)

        var errorDescription: String? {
            switch self {
            case .unauthorized: String(localized: "Onjuiste gebruikersnaam of wachtwoord.")
            case .notConfigured: String(localized: "Het 112Heli-beheer is nog niet ingesteld op de server.")
            case .tooMany: String(localized: "Te veel pogingen. Probeer het over een kwartier opnieuw.")
            case .network: String(localized: "Geen verbinding met de server.")
            case .decode: String(localized: "Onverwacht antwoord van de server.")
            case let .server(s, m): m ?? String(format: String(localized: "De server gaf HTTP %lld."), s)
            }
        }
    }

    private(set) var session: Session?
    private(set) var overview: Heli112Overview?
    private(set) var aircraft: [Heli112Aircraft] = []
    private(set) var reports: [Heli112Report] = []
    private(set) var messages: [Heli112Message] = []
    private(set) var loading = false
    var error: String?

    var isSignedIn: Bool { (session?.expires ?? .distantPast) > Date().addingTimeInterval(60) }
    var openReports: Int { reports.filter { $0.status == "nieuw" }.count }

    private static let account = "heli112.session"

    private init() {
        session = Keychain.readCodable(Self.account, as: Session.self)
    }

    // MARK: inloggen

    func signIn(user: String, password: String) async throws {
        struct Login: Decodable { let token: String; let expires: String }
        let data = try await request("/v1/beheer/login", method: "POST", body: ["user": user, "password": password], auth: false)
        guard let l = try? JSONDecoder().decode(Login.self, from: data) else { throw Failure.decode }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let s = Session(token: l.token, expires: f.date(from: l.expires) ?? Date().addingTimeInterval(29 * 86_400))
        Keychain.writeCodable(Self.account, s)
        session = s
    }

    func signOut() {
        Keychain.delete(Self.account)
        session = nil
        overview = nil
        aircraft = []
        reports = []
        messages = []
    }

    // MARK: laden

    func load() async {
        guard isSignedIn, !loading else {
            if session != nil && !isSignedIn { signOut() }
            return
        }
        loading = true
        defer { loading = false }
        do {
            async let o: Heli112Overview = get("/v1/beheer/overview")
            async let a: Heli112AircraftList = get("/v1/beheer/aircraft")
            async let r: Heli112ReportList = get("/v1/beheer/reports")
            async let m: Heli112MessageList = get("/v1/beheer/push")
            let (ov, al, rl, ml) = try await (o, a, r, m)
            overview = ov
            aircraft = al.toestellen
            reports = rl.reports
            messages = ml.berichten
            error = nil
        } catch Failure.unauthorized {
            signOut()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: acties

    func setStatus(_ report: Heli112Report, _ status: String) async {
        do {
            _ = try await request("/v1/beheer/reports/\(report.id)", method: "POST", body: ["status": status])
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ report: Heli112Report) async {
        do {
            _ = try await request("/v1/beheer/reports/\(report.id)", method: "DELETE")
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func reach(soorten: Set<String>) async -> Int? {
        struct Reach: Decodable { let bereik: Int }
        let q = soorten.sorted().joined(separator: ",")
        return (try? await get("/v1/beheer/push/bereik?soorten=\(q)") as Reach)?.bereik
    }

    struct SendResult: Decodable { let bereik: Int; let verstuurd: Int; let mislukt: Int }

    func send(title: String, text: String, soorten: Set<String>) async throws -> SendResult {
        let body: [String: Any] = ["titel": title, "tekst": text, "soorten": soorten.sorted(), "doel": "alle"]
        let data = try await request("/v1/beheer/push", method: "POST", body: body)
        guard let r = try? JSONDecoder().decode(SendResult.self, from: data) else { throw Failure.decode }
        await load()
        return r
    }

    // MARK: netwerk

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await request(path)
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw Failure.decode }
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, auth: Bool = true) async throws -> Data {
        guard let url = URL(string: Self.api.absoluteString + path) else { throw Failure.network }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let s = session { req.setValue("Bearer \(s.token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw Failure.network
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401: throw Failure.unauthorized
        case 429: throw Failure.tooMany
        case 503 where path.hasSuffix("/login"): throw Failure.notConfigured
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw Failure.server(status, message)
        }
    }
}

// MARK: modellen (antwoorden van de worker)

struct Heli112Overview: Decodable {
    struct Status: Decodable {
        let lastIngest: Double?
        let ingestOk: Bool
        let apns: Bool
        let mapkit: Bool
        let weer: Double?
    }
    struct Tellers: Decodable {
        let toestellen, inLucht, gezien24, apparaten, apparatenAan, metZones, liveActivities: Int
        let vluchtenVandaag, vluchten7, inzetten7, openMeldingen, actieveInzetten: Int
    }
    struct Count: Decodable, Identifiable {
        let platform: String?
        let versie: String?
        let soort: String?
        let naam: String?
        let n: Int
        var id: String { "\(platform ?? "")|\(versie ?? "")|\(soort ?? "")" }
        var label: String {
            if let platform { return Heli112Overview.platformName(platform) }
            return naam ?? versie ?? soort ?? "?"
        }
    }
    struct Day: Decodable, Identifiable {
        let dag: String
        let vluchten: Int
        let apparaten: Int
        let inzetten: Int
        var id: String { dag }
        var date: Date { BekendrStats.dayFormatter.date(from: dag) ?? .distantPast }
    }

    let status: Status
    let tellers: Tellers
    let platforms: [Count]
    let versies: [Count]
    let perSoort: [Count]
    let dagen: [Day]

    static func platformName(_ p: String) -> String {
        switch p {
        case "ios": "iPhone"
        case "ipados": "iPad"
        case "macos": "Mac"
        case "tvos": "Apple TV"
        default: p
        }
    }
}

struct Heli112Aircraft: Decodable, Identifiable {
    let hex: String
    let reg: String?
    let callsign: String?
    let soortNaam: String
    let type: String?
    let naam: String?
    let basis: String?
    let seen: Double?
    let inLucht: Bool
    let vluchten30: Int
    var id: String { hex }
    var title: String { naam ?? callsign ?? hex.uppercased() }
    var seenDate: Date? { seen.map { Date(timeIntervalSince1970: $0) } }
}

struct Heli112AircraftList: Decodable { let toestellen: [Heli112Aircraft] }

struct Heli112Report: Decodable, Identifiable {
    let id: Int
    let createdAt: Double
    let hex: String?
    let naam: String?
    let reg: String?
    let soort: String?
    let tekst: String
    let platform: String?
    let appVersion: String?
    let status: String
    var date: Date { Date(timeIntervalSince1970: createdAt) }

    private enum CodingKeys: String, CodingKey {
        case id, hex, naam, reg, soort, tekst, platform, status
        case createdAt = "created_at", appVersion = "app_version"
    }
}

struct Heli112ReportList: Decodable { let reports: [Heli112Report] }

struct Heli112Message: Decodable, Identifiable {
    let id: Int
    let createdAt: Double
    let titel: String?
    let tekst: String
    let soorten: [String]
    let bereik: Int
    let ok: Int
    var date: Date { Date(timeIntervalSince1970: createdAt) }

    private enum CodingKeys: String, CodingKey {
        case id, titel, tekst, soorten, bereik, ok
        case createdAt = "created_at"
    }
}

struct Heli112MessageList: Decodable { let berichten: [Heli112Message] }

/// Soorten toestellen, zoals in de app (voor pushberichten per soort).
enum Heli112Soort {
    static let all: [(id: String, name: LocalizedStringResource)] = [
        ("trauma", "Lifeliner"), ("politie", "Politie"), ("kustwacht", "Kustwacht"), ("defensie", "Defensie"),
        ("kmar", "Marechaussee"), ("regering", "Regering"), ("bijzonder", "Bijzonder"),
    ]
    static func name(_ id: String?) -> String {
        guard let id, let s = all.first(where: { $0.id == id }) else { return id ?? "" }
        return String(localized: s.name)
    }
}
