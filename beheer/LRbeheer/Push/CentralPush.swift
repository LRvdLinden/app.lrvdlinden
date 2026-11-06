import Foundation
import Observation
import TunrKit
import UIKit
import UserNotifications

/// Centraal pushsysteem van LRbeheer voor de omgevingen die nog geen eigen beheer-push hadden: LRvdLinden, PixelForges
/// en Tunr. Server: Edge Function `lrbeheer` (beheer/server/supabase), in het Supabase-project van Tunr.
///
/// Hergebruikt de beheer-inlog van TunrBeheer: de app meldt zich aan met het Tunr-beheertoken (de functie controleert het
/// met dezelfde sleutel TUNR_TOKEN_SECRET en tokenversie als de functie `admin`). Geen extra wachtwoord in de app.
/// Bingr, Pasr en P2000 houden hun eigen, bestaande pushsysteem (zie de bruggen in Modules/*/Bridge).
@MainActor
@Observable
final class CentralPush {
    static let shared = CentralPush()

    enum Permission: Equatable { case unknown, notDetermined, denied, allowed }

    /// Soorten per omgeving (schakelaars in Instellingen → Meldingen). Standaard alles aan.
    struct Prefs: Codable, Equatable {
        var lrvdlindenStore = true
        var lrvdlindenDeploy = true
        var pixelforgesDeploy = true
        var pixelforgesContent = true
        var pixelforgesContact = true
        var tunrInstalls = true
        var tunrPresskit = true

        var params: [String: Any] {
            ["lrvdlinden": ["store": lrvdlindenStore, "deploy": lrvdlindenDeploy],
             "pixelforges": ["deploy": pixelforgesDeploy, "content": pixelforgesContent, "contact": pixelforgesContact],
             "tunr": ["installs": tunrInstalls, "presskit": tunrPresskit]]
        }
    }

    private(set) var permission: Permission = .unknown
    private(set) var registered = false
    private(set) var lastError: String?
    var prefs: Prefs {
        didSet {
            guard prefs != oldValue else { return }
            if let d = try? JSONEncoder().encode(prefs) { defaults.set(d, forKey: K.prefs) }
            sync(force: true)
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var syncing = false

    private enum K {
        static let deviceID = "push.central.device_id"
        static let prefs = "push.central.prefs"
        static let registration = "push.central.registration"
    }

    private init() {
        prefs = defaults.data(forKey: K.prefs).flatMap { try? JSONDecoder().decode(Prefs.self, from: $0) } ?? Prefs()
        registered = defaults.string(forKey: K.registration) != nil
    }

    var deviceID: String {
        if let id = defaults.string(forKey: K.deviceID) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: K.deviceID)
        return id
    }

    /// Ingelogd bij Tunr? Dan kan dit apparaat zich aanmelden voor de centrale meldingen.
    var canRegister: Bool { TunrEnvironment.adminToken != nil }

    static var sandbox: Bool {
        #if DEBUG
        return true
        #else
        return ProvisioningProfileInfo.apsEnvironment == "development"
        #endif
    }

    func start() {
        Task { await refresh() }
    }

    /// Toestemming lezen en (als het mag) opnieuw registreren bij APNs; elke start levert zo een eventueel nieuw token.
    func refresh() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .notDetermined: permission = .notDetermined
        case .denied: permission = .denied
        default: permission = .allowed
        }
        if permission == .allowed { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Eén systeemvraag voor alle omgevingen (Instellingen → Meldingen → Aanzetten).
    func requestPermission() async {
        if permission == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
            return
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        sync(force: false)
    }

    private var signature: String? {
        token.map { [$0, Self.sandbox ? "sandbox" : "production", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""].joined(separator: "|") }
    }

    func sync(force: Bool) {
        guard !syncing, permission == .allowed, let token, let sig = signature, let auth = TunrEnvironment.adminToken else { return }
        if !force, defaults.string(forKey: K.registration) == sig { registered = true; return }
        syncing = true
        Task {
            defer { syncing = false }
            do {
                try await call("register", auth: auth, [
                    "device_id": deviceID, "apns_token": token, "sandbox": Self.sandbox, "platform": Self.platform,
                    "app_build": Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0,
                    "prefs": prefs.params,
                ])
                defaults.set(sig, forKey: K.registration)
                registered = true
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func sendTest() async throws {
        guard let auth = TunrEnvironment.adminToken else { throw CentralError.notSignedIn }
        if !registered { sync(force: true) }
        try await call("test", auth: auth, ["device_id": deviceID])
    }

    func unregister() async {
        guard let auth = TunrEnvironment.adminToken else { return }
        if (try? await call("unregister", auth: auth, ["device_id": deviceID])) != nil {
            defaults.removeObject(forKey: K.registration)
            registered = false
        }
    }

    static var platform: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios" }

    // MARK: server

    enum CentralError: LocalizedError {
        case notSignedIn, server(String), network
        var errorDescription: String? {
            switch self {
            case .notSignedIn: String(localized: "Log in bij Tunr om de centrale meldingen te gebruiken.")
            case let .server(c): String(format: String(localized: "De pushfunctie gaf een fout (%@)."), c)
            case .network: String(localized: "Geen verbinding met de server.")
            }
        }
    }

    @discardableResult
    private func call(_ action: String, auth: String, _ params: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: TunrEnvironment.supabaseURL + "/functions/v1/lrbeheer") else { throw CentralError.network }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(TunrEnvironment.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        var body = params
        body["action"] = action
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch { throw CentralError.network }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            throw CentralError.server(obj["error"] as? String ?? (status == 404 ? "not_deployed" : "HTTP \(status)"))
        }
        return obj
    }
}

/// `aps-environment` uit het ingebedde provisioning-profiel (zoals ProvisioningProfile in BingrBeheer en PasrBeheer).
enum ProvisioningProfileInfo {
    static let apsEnvironment: String? = {
        let url = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let dict = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any],
              let ent = dict["Entitlements"] as? [String: Any] else { return nil }
        return ent["aps-environment"] as? String
    }()
}
