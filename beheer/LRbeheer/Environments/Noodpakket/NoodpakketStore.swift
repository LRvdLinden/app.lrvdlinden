import Foundation
import Observation
import TunrKit

/// Beheer van Noodpakket: downloads (App Store Connect en de APK in GitHub Releases), Android-builds en berichten aan
/// de gebruikers van de app.
///
/// Noodpakket heeft geen eigen server; het beheer praat met de centrale functie `lrbeheer` (Supabase-project van Tunr),
/// net als het web-beheer op noodpakket.lrvdlinden.app/beheer/. Inloggen met de gedeelde beheer-inlog (BEHEER_APP_USER /
/// BEHEER_APP_PASSWORD) geeft een token van 12 uur; dat token staat alleen in de sleutelhanger van dit apparaat.
@MainActor
@Observable
final class NoodpakketStore {
    static let shared = NoodpakketStore()
    static let web = URL(string: "https://noodpakket.lrvdlinden.app/beheer/")!
    static let site = URL(string: "https://noodpakket.lrvdlinden.app")!
    static let releases = URL(string: "https://github.com/LRvdLinden/app.lrvdlinden.noodkoffer/releases")!
    static let actions = URL(string: "https://github.com/LRvdLinden/app.lrvdlinden.noodkoffer/actions/workflows/android.yml")!
    /// Noodpakket-API (Cloudflare Worker) met de optionele accounts; eigen beheer-inlog via /admin/login.
    static let api = URL(string: "https://noodpakket-api.noodpakket.workers.dev")!

    struct Session: Codable { let token: String; let expires: TimeInterval }

    enum Failure: LocalizedError {
        case unauthorized, notConfigured, network, decode, duplicate
        case invalid(String)
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: String(localized: "Onjuiste gebruikersnaam of wachtwoord.")
            case .notConfigured: String(localized: "Het Noodpakket-beheer is nog niet ingesteld op de server.")
            case .network: String(localized: "Geen verbinding met de server.")
            case .decode: String(localized: "Onverwacht antwoord van de server.")
            case .duplicate: String(localized: "Dit bericht is net al verstuurd.")
            case let .invalid(code):
                switch code {
                case "bad_title": String(localized: "De titel moet 3 tot 80 tekens zijn.")
                case "bad_body": String(localized: "De tekst mag hoogstens 400 tekens zijn.")
                case "bad_url": String(localized: "De link moet met https:// beginnen.")
                default: String(localized: "Het bericht klopt niet.")
                }
            case let .server(s): String(format: String(localized: "De server gaf HTTP %lld."), s)
            }
        }
    }

    private(set) var session: Session?
    private(set) var stats: NoodpakketStats?
    /// Accounts en gezinnen uit de Noodpakket-API (nil = nog niet geladen of geen token).
    private(set) var accounts: NoodpakketAccounts?
    private(set) var accountsNeedLogin = false
    private var workerSession: Session?
    private(set) var loading = false
    private(set) var sending = false
    var error: String?

    var isSignedIn: Bool { (session?.expires ?? 0) > Date().timeIntervalSince1970 + 60 }

    private static let account = "noodpakket.session"
    private static let workerAccount = "noodpakket.worker"

    private init() {
        session = Keychain.readCodable(Self.account, as: Session.self)
        workerSession = Keychain.readCodable(Self.workerAccount, as: Session.self)
    }

    func signIn(user: String, password: String) async throws {
        let o = try await call(["action": "noodpakket_login", "user": user, "password": password], token: nil)
        guard let token = o["token"] as? String, let exp = o["expires"] as? Double else { throw Failure.decode }
        let s = Session(token: token, expires: exp)
        Keychain.writeCodable(Self.account, s)
        session = s
        await workerSignIn(user: user, password: password)
    }

    func signOut() {
        Keychain.delete(Self.account)
        Keychain.delete(Self.workerAccount)
        session = nil
        workerSession = nil
        stats = nil
        accounts = nil
    }

    /// Zelfde beheer-inlog bij de Noodpakket-API (voor de accounts). Mislukt dit, dan werkt de rest gewoon.
    private func workerSignIn(user: String, password: String) async {
        var req = URLRequest(url: Self.api.appending(path: "admin/login"), timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["user": user, "password": password])
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = o["token"] as? String, let exp = o["expires"] as? Double else { return }
        let s = Session(token: token, expires: exp)
        Keychain.writeCodable(Self.workerAccount, s)
        workerSession = s
    }

    private func loadAccounts() async {
        guard let w = workerSession, w.expires > Date().timeIntervalSince1970 + 60 else {
            accountsNeedLogin = true
            return
        }
        var req = URLRequest(url: Self.api.appending(path: "admin/stats"), timeoutInterval: 30)
        req.setValue("Bearer \(w.token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return }
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            Keychain.delete(Self.workerAccount)
            workerSession = nil
            accountsNeedLogin = true
            return
        }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        if let a = try? d.decode(NoodpakketAccounts.self, from: data) {
            accounts = a
            accountsNeedLogin = false
        }
    }

    func load() async {
        guard let s = session, isSignedIn, !loading else {
            if session != nil && !isSignedIn { signOut() }
            return
        }
        loading = true
        defer { loading = false }
        do {
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            stats = try d.decode(NoodpakketStats.self, from: try await raw(["action": "noodpakket_stats"], token: s.token))
            error = nil
            await loadAccounts()
        } catch Failure.unauthorized {
            signOut()
        } catch is DecodingError {
            error = Failure.decode.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Bericht versturen. `test`: alleen als pushmelding naar de apparaten met LRbeheer.
    /// Geeft een korte uitslag terug ("Verstuurd naar 12 iPhones en iPads").
    func send(_ draft: NoodpakketDraft, test: Bool) async throws -> String {
        guard let s = session, isSignedIn else { throw Failure.unauthorized }
        sending = true
        defer { sending = false }
        var body: [String: Any] = [
            "action": "noodpakket_send", "title": draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            "body": draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
            "lang": draft.lang.rawValue, "platform": draft.platform.rawValue,
            "url": draft.link.trimmingCharacters(in: .whitespaces),
        ]
        if test { body["test"] = true }
        do {
            let o = try await call(body, token: s.token)
            let why = Self.explain(o["errors"] as? [String: Int])
            if test {
                let line = String(format: String(localized: "Testmelding verstuurd naar %lld apparaten met LRbeheer."), (o["sent"] as? Int) ?? 0)
                return why.map { line + "\n" + $0 } ?? line
            }
            await load()
            if ((o["failed_apple"] as? Int) ?? 0) > 0, let why { return why }
            let apple = (o["sent_apple"] as? Int) ?? 0
            return draft.platform == .android
                ? String(localized: "Verstuurd. Android-toestellen halen het bericht binnen een paar uur op.")
                : String(format: String(localized: "Verstuurd naar %lld iPhones en iPads; Android haalt het binnen een paar uur op."), apple)
        } catch Failure.unauthorized {
            signOut()
            throw Failure.unauthorized
        }
    }

    /// Bericht intrekken: Android haalt het dan niet meer op (iPhone en iPad hebben het al).
    func withdraw(_ m: NoodpakketStats.Message) async {
        guard let s = session, isSignedIn else { return }
        do {
            _ = try await call(["action": "noodpakket_message_delete", "id": m.id], token: s.token)
            await load()
        } catch Failure.unauthorized {
            signOut()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Uitleg bij de reden waarom APNs een melding weigerde (nil als er geen fout was).
    static func explain(_ errors: [String: Int]?) -> String? {
        guard let errors, let code = errors.max(by: { $0.value < $1.value })?.key else { return nil }
        let reason: String = switch code {
        case "apns_BadDeviceToken": String(localized: "Het pushtoken past niet bij deze omgeving (Xcode-build of TestFlight). Zet Berichten in de app uit en weer aan.")
        case "apns_BadEnvironmentKeyInToken": String(localized: "De APNs-sleutel mag niet voor deze omgeving. Test met TestFlight, of zet de sleutel in Apple Developer op Sandbox en Production.")
        case "apns_TopicDisallowed", "apns_BadTopic": String(localized: "De APNs-sleutel mag geen meldingen sturen voor app.lrvdlinden.noodpakket. Zet de sleutel in Apple Developer op het hele team (of voeg deze app toe).")
        case "apns_DeviceTokenNotForTopic": String(localized: "Het pushtoken hoort bij een andere app dan app.lrvdlinden.noodpakket.")
        case "apns_InvalidProviderToken", "apns_bad_key": String(localized: "De APNs-sleutel of het Team ID klopt niet. Controleer APN_KEY_ID, APN_P8_CERT en TEAM_ID en start LRbeheer push.")
        case "apns_Unregistered", "apns_410": String(localized: "Dit apparaat is niet meer aangemeld; de app is verwijderd of Berichten staat uit.")
        case "apns_unreachable": String(localized: "APNs was niet bereikbaar. Probeer het zo opnieuw.")
        default: String(format: String(localized: "APNs weigerde de melding (%@)."), code.replacingOccurrences(of: "apns_", with: ""))
        }
        return String(format: String(localized: "Niet afgeleverd: %@"), reason)
    }

    // MARK: netwerk

    private func call(_ body: [String: Any], token: String?) async throws -> [String: Any] {
        let data = try await raw(body, token: token)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.decode }
        return o
    }

    private func raw(_ body: [String: Any], token: String?) async throws -> Data {
        guard let url = URL(string: TunrEnvironment.supabaseURL + "/functions/v1/lrbeheer") else { throw Failure.network }
        var req = URLRequest(url: url, timeoutInterval: 60)
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
        case 400:
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? ""
            throw Failure.invalid(code)
        case 401: throw Failure.unauthorized
        case 409: throw Failure.duplicate
        case 503: throw Failure.notConfigured
        case let s: throw Failure.server(s)
        }
    }
}

/// Een bericht in wording.
struct NoodpakketDraft: Equatable {
    enum Lang: String, CaseIterable, Identifiable { case all, nl, en; var id: String { rawValue } }
    enum Platform: String, CaseIterable, Identifiable { case all, apple, android; var id: String { rawValue } }

    var title = ""
    var body = ""
    var link = ""
    var lang = Lang.all
    var platform = Platform.all

    var titleCount: Int { title.trimmingCharacters(in: .whitespacesAndNewlines).count }
    var bodyCount: Int { body.trimmingCharacters(in: .whitespacesAndNewlines).count }
    var linkOK: Bool {
        let l = link.trimmingCharacters(in: .whitespaces)
        return l.isEmpty || (l.lowercased().hasPrefix("https://") && URL(string: l) != nil)
    }
    var isValid: Bool { (3...80).contains(titleCount) && bodyCount <= 400 && linkOK }
}

/// Antwoord van noodpakket_stats.
struct NoodpakketStats: Decodable {
    let today: String
    let syncedAt: String?
    let apple: BekendrStats.Apple
    let android: Android
    let builds: [Build]
    let days: [BekendrStats.Day]
    let devices: Devices
    let messages: [Message]

    struct Android: Decodable {
        let total: Int
        let releases: [BekendrStats.Release]
        let available: Bool
        let latest: String?
    }

    struct Build: Decodable, Identifiable {
        let id: Int
        let title: String
        let status: String
        let conclusion: String?
        let createdAt: String
        let url: String
        let branch: String

        var date: Date? { NoodpakketStats.date(createdAt) }
        var isRunning: Bool { status != "completed" }
        var succeeded: Bool { conclusion == "success" }
        var stateLabel: String {
            if status == "queued" || status == "waiting" || status == "pending" { return String(localized: "In de wachtrij") }
            if isRunning { return String(localized: "Bezig") }
            switch conclusion {
            case "success": return String(localized: "Gelukt")
            case "cancelled": return String(localized: "Geannuleerd")
            case "skipped": return String(localized: "Overgeslagen")
            default: return String(localized: "Mislukt")
            }
        }
    }

    struct Devices: Decodable {
        let apple: Int
        let android: Int
        let nl: Int
        let en: Int
        var total: Int { apple + android }
    }

    struct Message: Decodable, Identifiable {
        let id: Int
        let at: String
        let title: String
        let body: String
        let lang: String
        let platform: String
        let url: String
        let sentApple: Int
        let failedApple: Int
        let fetchedAndroid: Int
        let withdrawn: Bool
        let errors: [String: Int]?

        var date: Date? { NoodpakketStats.date(at) }
        var audience: String {
            let l: String = switch lang {
            case "nl": String(localized: "Nederlands")
            case "en": String(localized: "Engels")
            default: String(localized: "Alle talen")
            }
            let p: String = switch platform {
            case "apple": String(localized: "iPhone en iPad")
            case "android": "Android"
            default: String(localized: "Alle apparaten")
            }
            return "\(p) · \(l)"
        }
    }

    var total: Int { apple.downloads + android.total }
    var syncedDate: Date? { syncedAt.flatMap(Self.date) }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Antwoord van /admin/stats van de Noodpakket-API: de optionele accounts en gezinnen.
struct NoodpakketAccounts: Decodable {
    let accounts: Int
    let confirmed: Int
    let unconfirmed: Int
    let active30d: Int
    let households: Int
    let sharedHouseholds: Int
    let sharedMembers: Int
    let openInvites: Int
    let records: Int
    let days: [Day]

    struct Day: Decodable {
        let day: String
        let signup: Int?
        let confirm: Int?
        let login: Int?
        let invite: Int?
        let joined: Int?
        let bot: Int?
        let apk: Int?
        let deleted: Int?
    }

    /// Optelling over de laatste 30 dagen.
    func sum(_ key: KeyPath<Day, Int?>) -> Int { days.reduce(0) { $0 + ($1[keyPath: key] ?? 0) } }
}
