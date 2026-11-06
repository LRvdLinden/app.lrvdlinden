import Foundation
import Observation

/// Praat met een bestaande webbeheeromgeving (lrvdlinden.app of pixelforges.nl) precies zoals beheer.html:
/// dezelfde PHP-endpoints, dezelfde beheer-header, en de inlog van .htaccess (HTTP Basic, dezelfde gebruikersnaam en
/// hetzelfde wachtwoord als beheer.html). Er verandert niets aan de sites; de app stuurt geen Origin mee, dus de
/// controle "aanvraag van een andere website" in de PHP-bestanden laat hem door zoals de eigen beheerpagina.
struct SiteClient: Sendable {
    let base: URL
    /// "X-LR-Beheer" of "X-PF-Beheer"
    let headerName: String
    let user: String
    let password: String

    enum Failure: LocalizedError {
        case unauthorized
        case server(String)
        case network
        case decode

        var errorDescription: String? {
            switch self {
            case .unauthorized: return String(localized: "Onjuiste gebruikersnaam of wachtwoord.")
            case let .server(m): return m
            case .network: return String(localized: "Geen verbinding met de server.")
            case .decode: return String(localized: "Onverwacht antwoord van de server.")
            }
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    private var authHeader: String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    func request(_ method: String, _ path: String, query: [String: String] = [:], json body: Data? = nil,
                 beheerHeader: Bool = true) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if beheerHeader { req.setValue("1", forHTTPHeaderField: headerName) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await Self.session.data(for: req) } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw Failure.network
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw Failure.unauthorized }
        if !(200..<300).contains(status) {
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let e = o["error"] as? String {
                throw Failure.server(e)
            }
            throw Failure.server(String(format: String(localized: "De server gaf HTTP %lld."), status))
        }
        return data
    }

    /// JSON-antwoord van een PHP-endpoint ({"ok":…}); ok=false wordt een fout met de tekst van de server.
    func call(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> [String: Any] {
        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let data = try await request(method, path, query: query, json: payload)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.decode }
        if (o["ok"] as? Bool) == false { throw Failure.server(o["error"] as? String ?? String(localized: "Onbekende fout.")) }
        return o
    }

    /// Publiceren met een ruwe JSON-body (data als geordende JSON), zoals publish() in beheer.html.
    func publish(data: JSON, files: [(path: String, base64: String)], message: String) async throws -> [String: Any] {
        var body = "{\"data\":" + data.serialized() + ",\"files\":["
        body += files.map { "{\"path\":" + JSON.string($0.path).serialized() + ",\"data\":\"" + $0.base64 + "\"}" }
            .joined(separator: ",")
        body += "],\"message\":" + JSON.string(message).serialized() + "}"
        let resp = try await request("POST", "publish.php", json: Data(body.utf8))
        guard let o = try? JSONSerialization.jsonObject(with: resp) as? [String: Any] else { throw Failure.decode }
        if (o["ok"] as? Bool) != true { throw Failure.server(o["error"] as? String ?? String(localized: "Publiceren mislukt.")) }
        return o
    }

    /// Controleert de inlog met een verzoek naar beheer.html (achter dezelfde .htaccess-login).
    func verify() async throws {
        _ = try await request("GET", "beheer.html", beheerHeader: false)
    }
}

/// Inloggegevens van een site (Keychain) en de toestand van inloggen.
@MainActor
@Observable
final class SiteAccount {
    struct Credentials: Codable { let user: String; let password: String }

    let id: String
    let base: URL
    let headerName: String
    private(set) var credentials: Credentials?
    var isSignedIn: Bool { credentials != nil }

    init(id: String, base: URL, headerName: String) {
        self.id = id
        self.base = base
        self.headerName = headerName
        credentials = Keychain.readCodable("site.\(id)", as: Credentials.self)
    }

    var client: SiteClient? {
        credentials.map { SiteClient(base: base, headerName: headerName, user: $0.user, password: $0.password) }
    }

    func signIn(user: String, password: String) async throws {
        let c = SiteClient(base: base, headerName: headerName, user: user, password: password)
        try await c.verify()
        let cred = Credentials(user: user, password: password)
        Keychain.writeCodable("site.\(id)", cred)
        credentials = cred
    }

    func signOut() {
        Keychain.delete("site.\(id)")
        credentials = nil
    }
}
