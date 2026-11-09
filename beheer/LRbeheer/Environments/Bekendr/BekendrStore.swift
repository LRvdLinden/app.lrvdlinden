import Foundation
import Observation
import TunrKit

/// Beheer van Bekendr: downloads van de app op iPhone, iPad, Mac (App Store Connect) en Android (APK in GitHub Releases).
///
/// Bekendr heeft geen eigen server; het beheer praat met de centrale functie `lrbeheer` (Supabase-project van Tunr), net
/// als het web-beheer op bekendr.lrvdlinden.app/beheer. Inloggen met de gedeelde beheer-inlog (BEHEER_APP_USER /
/// BEHEER_APP_PASSWORD) geeft een token van 12 uur; dat token staat alleen in de sleutelhanger van dit apparaat.
@MainActor
@Observable
final class BekendrStore {
    static let shared = BekendrStore()
    static let web = URL(string: "https://bekendr.lrvdlinden.app/beheer/")!
    static let site = URL(string: "https://bekendr.lrvdlinden.app")!

    struct Session: Codable { let token: String; let expires: TimeInterval }

    enum Failure: LocalizedError {
        case unauthorized, notConfigured, network, decode
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: String(localized: "Onjuiste gebruikersnaam of wachtwoord.")
            case .notConfigured: String(localized: "Het Bekendr-beheer is nog niet ingesteld op de server.")
            case .network: String(localized: "Geen verbinding met de server.")
            case .decode: String(localized: "Onverwacht antwoord van de server.")
            case let .server(s): String(format: String(localized: "De server gaf HTTP %lld."), s)
            }
        }
    }

    private(set) var session: Session?
    private(set) var stats: BekendrStats?
    private(set) var feedback: [BekendrFeedback] = []
    private(set) var feedbackOpen = 0
    private(set) var feedbackLoading = false
    var feedbackOnlyOpen = true
    private(set) var loading = false
    var error: String?

    var isSignedIn: Bool { (session?.expires ?? 0) > Date().timeIntervalSince1970 + 60 }

    private static let account = "bekendr.session"

    private init() {
        session = Keychain.readCodable(Self.account, as: Session.self)
    }

    func signIn(user: String, password: String) async throws {
        let o = try await call(["action": "bekendr_login", "user": user, "password": password], token: nil)
        guard let token = o["token"] as? String, let exp = o["expires"] as? Double else { throw Failure.decode }
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
            let data = try await raw(["action": "bekendr_stats"], token: s.token)
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            stats = try d.decode(BekendrStats.self, from: data)
            error = nil
        } catch Failure.unauthorized {
            signOut()
        } catch is DecodingError {
            error = Failure.decode.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: feedback

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func loadFeedback(onlyOpen: Bool) async {
        guard let s = session, isSignedIn else { return }
        feedbackLoading = true
        defer { feedbackLoading = false }
        do {
            var body: [String: Any] = ["action": "bekendr_feedback_list"]
            if onlyOpen { body["status"] = "nieuw" }
            let r = try decoder.decode(FeedbackList.self, from: try await raw(body, token: s.token))
            feedback = r.items
            feedbackOpen = r.open
            error = nil
        } catch Failure.unauthorized {
            signOut()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setHandled(_ item: BekendrFeedback, _ handled: Bool) async {
        await update(["id": item.id, "status": handled ? "afgehandeld" : "nieuw"])
    }

    func delete(_ item: BekendrFeedback) async {
        await update(["id": item.id, "delete": true])
        feedback.removeAll { $0.id == item.id }
    }

    private func update(_ params: [String: Any]) async {
        guard let s = session, isSignedIn else { return }
        do {
            var body = params
            body["action"] = "bekendr_feedback_update"
            let o = try await call(body, token: s.token)
            feedbackOpen = (o["open"] as? Int) ?? feedbackOpen
            if let id = params["id"] as? Int, let status = params["status"] as? String,
               let i = feedback.firstIndex(where: { $0.id == id }) {
                feedback[i].status = status
            }
        } catch Failure.unauthorized {
            signOut()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private struct FeedbackList: Decodable { let items: [BekendrFeedback]; let open: Int }

    // MARK: netwerk

    private func call(_ body: [String: Any], token: String?) async throws -> [String: Any] {
        let data = try await raw(body, token: token)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.decode }
        return o
    }

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

/// Feedback uit de app op een bekendmaking.
struct BekendrFeedback: Decodable, Identifiable, Equatable {
    let id: Int
    let at: String
    let noticeId: String
    let noticeTitle: String
    let noticeUrl: String
    let reason: String
    let message: String
    let platform: String
    let appVersion: String
    var status: String

    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: at) ?? ISO8601DateFormatter().date(from: at)
    }
    var isOpen: Bool { status == "nieuw" }
    var reasonLabel: String {
        switch reason {
        case "locatie": String(localized: "Locatie klopt niet")
        case "categorie": String(localized: "Verkeerde categorie")
        case "gemeente": String(localized: "Verkeerde gemeente")
        case "link": String(localized: "Link werkt niet")
        default: String(localized: "Anders")
        }
    }
    var reasonSymbol: String {
        switch reason {
        case "locatie": "mappin.slash"
        case "categorie": "square.grid.2x2"
        case "gemeente": "building.2"
        case "link": "link"
        default: "ellipsis.bubble"
        }
    }
    var platformLabel: String {
        switch platform {
        case "ios": "iPhone"
        case "ipados": "iPad"
        case "macos": "Mac"
        case "android": "Android"
        default: platform
        }
    }
}

/// Antwoord van bekendr_stats.
struct BekendrStats: Decodable {
    let today: String
    let syncedAt: String?
    let apple: Apple
    let android: Android
    let days: [Day]
    let feedbackOpen: Int?

    struct Apple: Decodable {
        let configured: Bool
        let totals: [String: Int]
        let byDevice: [String: Int]
        let lastDay: String?

        var downloads: Int { totals["download"] ?? 0 }
        var redownloads: Int { totals["redownload"] ?? 0 }
        var updates: Int { totals["update"] ?? 0 }
        func device(_ name: String) -> Int { byDevice[name] ?? 0 }
        var otherDevices: Int { byDevice.filter { !["iPhone", "iPad", "Mac"].contains($0.key) }.values.reduce(0, +) }
    }

    struct Android: Decodable {
        let total: Int
        let releases: [Release]
        let available: Bool
    }

    struct Release: Decodable, Identifiable {
        let tag: String
        let name: String
        let publishedAt: String
        let downloads: Int
        var id: String { tag }
        var date: Date? { ISO8601DateFormatter().date(from: publishedAt) }
    }

    struct Day: Decodable, Identifiable {
        let day: String
        let iPhone: Int
        let iPad: Int
        let Mac: Int
        let other: Int
        let android: Int
        var id: String { day }
        var date: Date { BekendrStats.dayFormatter.date(from: day) ?? .distantPast }
        var total: Int { iPhone + iPad + Mac + other + android }

        private enum CodingKeys: String, CodingKey { case day, iPhone, iPad, Mac, other, android }
    }

    var total: Int { apple.downloads + android.total }
    var syncedDate: Date? {
        guard let s = syncedAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
