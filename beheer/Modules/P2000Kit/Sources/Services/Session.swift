import Foundation
import Observation
import LocalAuthentication

/// Login state, the Face ID / Touch ID lock and helpers to call the API with the token.
@MainActor
@Observable
final class Session {
    static let shared = Session()

    private(set) var token: String?
    private(set) var user: String?
    private(set) var expires: Date?
    var isLocked = false
    var faceIDEnabled: Bool {
        didSet { UserDefaults.module.set(faceIDEnabled, forKey: "beheer.faceID") }
    }

    var isLoggedIn: Bool { token != nil }

    private init() {
        token = Keychain.get("token")
        user = Keychain.get("user")
        expires = Fmt.parse(Keychain.get("expires"))
        faceIDEnabled = UserDefaults.module.object(forKey: "beheer.faceID") as? Bool ?? true
        if let expires, expires < .now { clear() }
        isLocked = token != nil && faceIDEnabled && Self.biometricsAvailable
    }

    static var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "toegangscode"
        }
    }

    func login(user: String, password: String) async throws {
        let r = try await BeheerAPI.shared.login(user: user, password: password)
        token = r.token
        self.user = r.user
        expires = r.expires
        Keychain.set(r.token, for: "token")
        Keychain.set(r.user, for: "user")
        Keychain.set(r.expires.map { ISO8601DateFormatter().string(from: $0) }, for: "expires")
        isLocked = false
        PushRegistrar.shared.syncIfPossible()
    }

    func logout() {
        clear()
        isLocked = false
    }

    private func clear() {
        token = nil; user = nil; expires = nil
        Keychain.set(nil, for: "token"); Keychain.set(nil, for: "user"); Keychain.set(nil, for: "expires")
    }

    func lockIfNeeded() {
        if isLoggedIn && faceIDEnabled && Self.biometricsAvailable { isLocked = true }
    }

    func unlock() async {
        guard isLocked else { return }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Annuleer"
        do {
            if try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ontgrendel A-Alerts-beheer") {
                isLocked = false
            }
        } catch {}
    }

    /// Runs an API call with the current token; a 401 logs out.
    func call<T>(_ work: (String) async throws -> T) async throws -> T {
        guard let token else { throw BeheerAPI.APIError.unauthorized("Niet ingelogd") }
        do {
            return try await work(token)
        } catch BeheerAPI.APIError.unauthorized(let m) {
            logout()
            throw BeheerAPI.APIError.unauthorized(m)
        }
    }
}
