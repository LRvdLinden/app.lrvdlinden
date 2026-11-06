import Foundation

/// Client for the beheer part of the P2000 Apeldoorn API (/v1/beheer/…).
struct BeheerAPI: Sendable {
    static let shared = BeheerAPI()

    static var base: URL {
        if let s = Bundle.main.object(forInfoDictionaryKey: "P2000APIURL") as? String, let url = URL(string: s), url.host != nil {
            return url
        }
        return URL(string: "https://p2000-apeldoorn-api.lrvdlinden.workers.dev")!
    }

    enum APIError: LocalizedError {
        case unauthorized(String)
        case server(Int, String)
        var errorDescription: String? {
            switch self {
            case .unauthorized(let m): return m
            case .server(let code, let m): return m.isEmpty ? "Server gaf foutcode \(code)" : m
            }
        }
    }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private struct ErrorBody: Decodable { let error: String? }
    private struct LoginResult: Decodable { let token: String; let user: String; let expires: String }

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: Encodable? = nil,
                         token: String? = nil) async throws -> Data {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? ""
            if status == 401 { throw APIError.unauthorized(message.isEmpty ? "Niet ingelogd" : message) }
            throw APIError.server(status, message)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], token: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await request("GET", path, query: query, token: token))
    }

    // MARK: Session

    func login(user: String, password: String) async throws -> (token: String, user: String, expires: Date?) {
        let data = try await request("POST", "v1/beheer/login", body: ["user": user, "password": password])
        let r = try JSONDecoder().decode(LoginResult.self, from: data)
        return (r.token, r.user, Fmt.parse(r.expires))
    }

    // MARK: Data

    func overview(token: String) async throws -> Overview { try await get("v1/beheer/overview", token: token) }

    func meldingen(query: String, onlyHidden: Bool, token: String) async throws -> [AdminMelding] {
        var q = ["limit": "300"]
        if !query.isEmpty { q["q"] = query }
        if onlyHidden { q["hidden"] = "1" }
        return try await get("v1/beheer/meldingen", query: q, token: token)
    }

    struct MeldingUpdate: Encodable {
        var hidden: Bool?
        var title: String?
        var categorie: String?
        var locatie: String?
        var lat: Double?
        var lon: Double?
        var reset: Bool?
    }

    func update(_ guid: String, _ change: MeldingUpdate, token: String) async throws -> AdminMelding {
        let data = try await request("PATCH", "v1/beheer/meldingen/\(guid)", body: change, token: token)
        return try JSONDecoder().decode(AdminMelding.self, from: data)
    }

    struct BroadcastRequest: Encodable { let title: String; let body: String; let plaatsen: [String]; let guid: String? }

    func broadcast(_ b: BroadcastRequest, token: String) async throws -> Int {
        let data = try await request("POST", "v1/beheer/push", body: b, token: token)
        return try JSONDecoder().decode(QueuedResult.self, from: data).queued
    }

    func broadcastHistory(token: String) async throws -> [BroadcastItem] { try await get("v1/beheer/push", token: token) }

    func content(_ name: String, token: String) async throws -> ContentDoc { try await get("v1/beheer/content/\(name)", token: token) }
    func saveContent(_ name: String, _ doc: ContentDoc, token: String) async throws {
        _ = try await request("PUT", "v1/beheer/content/\(name)", body: doc, token: token)
    }
    func resetContent(_ name: String, token: String) async throws {
        _ = try await request("DELETE", "v1/beheer/content/\(name)", token: token)
    }
    func changelog(token: String) async throws -> [ChangelogEntry] { try await get("v1/beheer/content/changelog", token: token) }
    func saveChangelog(_ entries: [ChangelogEntry], token: String) async throws {
        _ = try await request("PUT", "v1/beheer/content/changelog", body: entries, token: token)
    }

    struct DeviceRequest: Encodable { let token: String; let environment: String; let platform: String }
    func registerDevice(_ d: DeviceRequest, token: String) async throws {
        _ = try await request("POST", "v1/beheer/devices", body: d, token: token)
    }
    func testPush(token: String) async throws {
        _ = try await request("POST", "v1/beheer/devices/test", token: token)
    }
}

/// Type-erased Encodable so request(body:) can take any Encodable value.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
