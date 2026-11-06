import Foundation
import LocalAuthentication
import SwiftUI

/// Onderdelen van de app (tabs op de iPhone, zijbalk op iPad en Mac).
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, downloads, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("Overzicht")
        case .downloads: return L("Downloads")
        case .settings: return L("Instellingen")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.xyaxis.line"
        case .downloads: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }
}

/// Inlogsessie, vergrendeling en gedeelde toestand van de app.
@MainActor
final class Session: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var expiresAt: Date?
    /// Melding op het inlogscherm (bv. "Je sessie is verlopen").
    @Published var loginMessage: String?

    @Published var section: AppSection = .overview
    /// Wordt opgehoogd door ⌘R / Vernieuwen: het zichtbare onderdeel laadt opnieuw.
    @Published private(set) var refreshTick = 0

    /// Face ID / Touch ID / toegangscode (standaard aan; schakelaar in Instellingen).
    @Published var lockEnabled: Bool = true {
        didSet { UserDefaults.module.set(lockEnabled, forKey: Self.lockKey) }
    }
    @Published private(set) var isLocked = false
    /// Eén keer vanzelf om Face ID vragen per vergrendeling (niet opnieuw na annuleren).
    var autoUnlockTried = false

    private let api = AdminAPI()
    private var inactiveSince: Date?

    private static let keychainAccount = "session"
    private static let lockKey = "lockEnabled"
    /// Vergrendelen na zo lang op de achtergrond (of op de Mac niet voorop).
    static let lockAfter: TimeInterval = 5 * 60

    var isSignedIn: Bool { token != nil }

    init() {
        UserDefaults.module.register(defaults: [Self.lockKey: true])
        lockEnabled = UserDefaults.module.bool(forKey: Self.lockKey)

        if let data = Keychain.read(Self.keychainAccount),
           let stored = try? JSONDecoder().decode(StoredToken.self, from: data),
           stored.expires > Date() {
            token = stored.token
            expiresAt = stored.expires
        } else {
            Keychain.delete(Self.keychainAccount)
        }
        // vergrendeld bij het starten
        isLocked = isSignedIn && lockEnabled && canLock
    }

    private struct StoredToken: Codable {
        let token: String
        let expires: Date
    }

    // MARK: inloggen

    func login(user: String, password: String) async throws {
        let r = try await api.send("login", token: nil, params: ["user": user, "password": password], as: LoginResponse.self)
        let exp = r.expires?.date ?? Date().addingTimeInterval(12 * 3600)
        if let data = try? JSONEncoder().encode(StoredToken(token: r.token, expires: exp)) {
            Keychain.write(Self.keychainAccount, data)
        }
        token = r.token
        expiresAt = exp
        loginMessage = nil
        isLocked = false
        section = .overview
    }

    func logout(_ message: String? = nil) {
        Keychain.delete(Self.keychainAccount)
        token = nil
        expiresAt = nil
        isLocked = false
        loginMessage = message
    }

    /// Overal uitloggen (actie `logout_all`): alle beheer-tokens vervallen, ook op het web en andere apparaten.
    func logoutAll() async throws {
        _ = try await api.raw("logout_all", token: token)
        logout(L("Je bent overal uitgelogd."))
    }

    /// Actie van de functie `admin` met het token. 401 (verlopen, ingetrokken): terug naar inloggen.
    func call<T: Decodable>(_ action: String, _ params: [String: Any] = [:], as type: T.Type) async throws -> T {
        if let exp = expiresAt, exp <= Date() {
            logout(L("Je sessie is verlopen. Log opnieuw in."))
            throw APIError(code: "unauthorized", status: 401)
        }
        do {
            return try await api.send(action, token: token, params: params, as: type)
        } catch let e as APIError where e.isUnauthorized {
            logout(L("Je sessie is verlopen. Log opnieuw in."))
            throw e
        }
    }

    // MARK: vernieuwen

    func requestRefresh() {
        guard isSignedIn, !isLocked else { return }
        refreshTick &+= 1
    }

    // MARK: vergrendelen

    var canLock: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default:
            #if os(macOS)
            return L("wachtwoord")
            #else
            return L("toegangscode")
            #endif
        }
    }

    var biometryIcon: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.open"
        }
    }

    func unlock() async {
        let ctx = LAContext()
        ctx.localizedCancelTitle = L("Annuleren")
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // geen toegangscode/wachtwoord ingesteld: niet vastzetten
            isLocked = false
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("Ontgrendel BeheerTunr"))
            if ok { isLocked = false }
        } catch {
            // geannuleerd of mislukt: vergrendeld laten
        }
    }

    func setLockEnabled(_ on: Bool) async {
        if on {
            lockEnabled = true
            return
        }
        // uitzetten alleen na bevestigen met Face ID / Touch ID / code
        let ctx = LAContext()
        ctx.localizedCancelTitle = L("Annuleren")
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            lockEnabled = false
            return
        }
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("Vergrendeling uitzetten"))) == true {
            lockEnabled = false
        } else {
            // schakelaar terugzetten
            lockEnabled = true
        }
    }

    /// App niet meer actief (iOS: achtergrond/app-wisselaar; Mac: ander programma voorop of verborgen).
    func didLeaveForeground() {
        if inactiveSince == nil { inactiveSince = Date() }
    }

    /// Weer actief: na meer dan 5 minuten weg vergrendelen.
    func didEnterForeground() {
        defer { inactiveSince = nil }
        guard let since = inactiveSince, lockEnabled, isSignedIn, !isLocked else { return }
        if Date().timeIntervalSince(since) >= Self.lockAfter && canLock {
            isLocked = true
            autoUnlockTried = false
        }
    }
}
