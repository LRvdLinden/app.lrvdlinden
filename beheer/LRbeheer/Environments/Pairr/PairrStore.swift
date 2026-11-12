import Foundation
import Observation
import TunrKit

/// Beheer van Pairr: downloads van de app op iPhone, iPad en Mac (App Store Connect) en open meldingen (GitHub Issues).
///
/// Pairr heeft geen eigen server en geen Android-versie; het beheer praat met de centrale functie `lrbeheer`
/// (Supabase-project van Tunr), net als het web-beheer op pairr.lrvdlinden.app/beheer. Inloggen met de gedeelde
/// beheer-inlog geeft een token van 12 uur (scope `pairr`); dat staat alleen in de sleutelhanger van dit apparaat.
@MainActor
@Observable
final class PairrStore {
    static let shared = PairrStore()
    static let web = URL(string: "https://pairr.lrvdlinden.app/beheer/")!
    static let site = URL(string: "https://pairr.lrvdlinden.app")!
    static let issues = URL(string: "https://github.com/LRvdLinden/app.lrvdlinden.pairr/issues")!

    struct Session: Codable { let token: String; let expires: TimeInterval }

    enum Failure: LocalizedError {
        case unauthorized, notConfigured, network, decode
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: String(localized: "Onjuiste gebruikersnaam of wachtwoord.")
            case .notConfigured: String(localized: "Het Pairr-beheer is nog niet ingesteld op de server.")
            case .network: String(localized: "Geen verbinding met de server.")
            case .decode: String(localized: "Onverwacht antwoord van de server.")
            case let .server(s): String(format: String(localized: "De server gaf HTTP %lld."), s)
            }
        }
    }

    private(set) var session: Session?
    private(set) var stats: PairrStats?
    private(set) var loading = false
    var error: String?

    var isSignedIn: Bool { (session?.expires ?? 0) > Date().timeIntervalSince1970 + 60 }

    private static let account = "pairr.session"

    private init() {
        session = Keychain.readCodable(Self.account, as: Session.self)
    }

    func signIn(user: String, password: String) async throws {
        let data = try await raw(["action": "pairr_login", "user": user, "password": password], token: nil)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = o["token"] as? String, let exp = o["expires"] as? Double else { throw Failure.decode }
        let s = Session(token: token, expires: exp)
        Keychain.writeCodable(Self.account, s)
        session = s
    }

    func signOut() {
        Keychain.delete(Self.account)
        session = nil
        stats = nil
    }

    func load() async {
        guard let s = session, isSignedIn, !loading else {
            if session != nil && !isSignedIn { signOut() }
            return
        }
        loading = true
        defer { loading = false }
        do {
            let data = try await raw(["action": "pairr_stats"], token: s.token)
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            stats = try d.decode(PairrStats.self, from: data)
            error = nil
        } catch Failure.unauthorized {
            signOut()
        } catch is DecodingError {
            error = Failure.decode.localizedDescription
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: netwerk

    private func raw(_ body: [String: Any], token: String?) async throws -> Data {
        guard let url = URL(string: TunrEnvironment.supabaseURL + "/functions/v1/lrbeheer") else { throw Failure.network }
        var req = URLRequest(url: url, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(TunrEnvironment.publishableKey, forHTTPHeaderField: "apikey")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw Failure.network
        }
        switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401: throw Failure.unauthorized
        case 503: throw Failure.notConfigured
        case let s: throw Failure.server(s)
        }
    }
}

/// Antwoord van pairr_stats.
struct PairrStats: Decodable {
    let today: String
    let syncedAt: String?
    let apple: BekendrStats.Apple
    let days: [Day]
    let issues: Issues
    let revenue: Revenue?

    /// Omzet: opbrengst na Apple (Units × Developer Proceeds), omgerekend naar euro met de ECB-koers.
    struct Revenue: Decodable {
        let totalEur: Double
        let monthEur: Double
        let units: Int
        let lastDay: String?
        let unconverted: Int
        let byCurrency: [String: Currency]
        let days: [Day]

        struct Currency: Decodable { let units: Int; let proceeds: Double }
        struct Day: Decodable, Identifiable {
            let day: String
            let eur: Double
            let units: Int
            var id: String { day }
            var date: Date { BekendrStats.dayFormatter.date(from: day) ?? .distantPast }
        }
    }

    struct Day: Decodable, Identifiable {
        let day: String
        let iPhone: Int
        let iPad: Int
        let Mac: Int
        let other: Int
        var id: String { day }
        var date: Date { BekendrStats.dayFormatter.date(from: day) ?? .distantPast }
        var total: Int { iPhone + iPad + Mac + other }

        private enum CodingKeys: String, CodingKey { case day, iPhone, iPad, Mac, other }
    }

    struct Issues: Decodable {
        let available: Bool
        let open: Int
        let items: [Issue]
        let url: String?
    }

    struct Issue: Decodable, Identifiable {
        let number: Int
        let title: String
        let url: String
        let createdAt: String
        let comments: Int
        let labels: [String]
        var id: Int { number }
        var link: URL? { url.hasPrefix("https://github.com/") ? URL(string: url) : nil }
        var date: Date? { ISO8601DateFormatter().date(from: createdAt) }
    }

    var syncedDate: Date? {
        guard let s = syncedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
