import BingrKit
import LocalAuthentication
import Observation
import P2000Kit
import PasrKit
import SwiftUI
import TunrKit
import UIKit

/// Gedeelde toestand van LRbeheer: welke omgeving actief is, de laatstgebruikte, en het doorsturen van deeplinks en
/// pushmeldingen naar de juiste omgeving.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// nil = het overzicht met de zes omgevingen.
    var active: BeheerEnvironment? = nil {
        didSet {
            if let active {
                UserDefaults.standard.set(active.rawValue, forKey: Keys.last)
                lastUsed = active
            }
        }
    }
    private(set) var lastUsed: BeheerEnvironment?

    var showSettings = false
    var showSwitcher = false

    /// Instelling: laatstgebruikte omgeving automatisch openen.
    var reopenLast: Bool {
        didSet { UserDefaults.standard.set(reopenLast, forKey: Keys.reopen) }
    }

    /// Ontgrendelen met Face ID bij openen (LRbeheer zelf: overzicht, LRvdLinden en PixelForges; de andere omgevingen
    /// hebben hun eigen vergrendeling uit de oorspronkelijke apps).
    var lockEnabled: Bool {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: Keys.lock) }
    }
    var isLocked = false

    enum Keys {
        static let last = "ui.lastEnvironment"
        static let reopen = "ui.reopenLast"
        static let lock = "lock.enabled"
    }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [Keys.reopen: true, Keys.lock: true])
        reopenLast = d.bool(forKey: Keys.reopen)
        lockEnabled = d.bool(forKey: Keys.lock)
        lastUsed = d.string(forKey: Keys.last).flatMap(BeheerEnvironment.init(rawValue:))
        if reopenLast { active = lastUsed }
        isLocked = lockEnabled && AppLock.canLock
    }

    /// Bij het starten: alle omgevingen koppelen (sessies, pushregistratie), ook de niet-zichtbare.
    func start() {
        BingrEnvironment.start()
        TunrEnvironment.start()
        PasrEnvironment.start()
        P2000Environment.start()
        CentralPush.shared.start()
    }

    func switchTo(_ env: BeheerEnvironment?) {
        withAnimation(.snappy(duration: 0.25)) { active = env }
    }

    /// Deeplink (lrbeheer://bingr/support/1001, bingrbeheer://…, pasrbeheer://…, widgets van Bingr).
    func open(_ url: URL) {
        guard let env = BeheerEnvironment.allCases.first(where: { $0.owns(url) }) else { return }
        switchTo(env)
        if url.scheme?.lowercased() == "lrbeheer" {
            // lrbeheer://<omgeving>/<rest> → de eigen link van de omgeving
            if let inner = Self.innerURL(url, env) { env.open(inner) }
        } else {
            env.open(url)
        }
    }

    /// lrbeheer://bingr/support/1001 → bingrbeheer://support/1001 (zelfde voor pasr).
    static func innerURL(_ url: URL, _ env: BeheerEnvironment) -> URL? {
        let rest = url.path.split(separator: "/").joined(separator: "/")
        switch env {
        case .bingr: return URL(string: "bingrbeheer://" + rest)
        case .pasr: return URL(string: "pasrbeheer://" + rest)
        case .tunr: return URL(string: "https://beheer.tunr.online/" + rest)
        default: return nil
        }
    }

    // MARK: pushmeldingen

    /// Tik op een pushmelding: welke omgeving (veld `lrenv`, anders het URL-schema van `url`), daarheen wisselen en het
    /// relevante onderdeel openen via de originele code van die omgeving.
    func handleNotification(_ info: [AnyHashable: Any]) {
        let url = info["url"] as? String
        let env = Self.environment(of: info)
        guard let env else { return }
        switchTo(env)
        switch env {
        case .bingr: BingrEnvironment.handleNotification(url: url)
        case .pasr: PasrEnvironment.handleNotification(url: url)
        default:
            if let s = url, let u = URL(string: s) { open(u) }
        }
    }

    /// Omgeving van een melding. Bingr en Pasr sturen `url` met hun eigen schema; P2000 en de centrale pushfunctie
    /// sturen `lrenv` mee (zie server/README.md).
    static func environment(of info: [AnyHashable: Any]) -> BeheerEnvironment? {
        if let e = info["lrenv"] as? String, let env = BeheerEnvironment(rawValue: e) { return env }
        if let s = info["url"] as? String, let u = URL(string: s) {
            return BeheerEnvironment.allCases.first { $0.owns(u) }
        }
        return nil
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        BingrEnvironment.scenePhaseChanged(phase)
        TunrEnvironment.scenePhaseChanged(phase)
        PasrEnvironment.scenePhaseChanged(phase)
        P2000Environment.scenePhaseChanged(phase)
        if phase == .background, lockEnabled, AppLock.canLock { isLocked = true }
        if phase == .active { Task { await CentralPush.shared.refresh() } }
    }
}

/// Face ID / Touch ID / toegangscode voor LRbeheer zelf.
enum AppLock {
    static var canLock: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "toegangscode")
        }
    }

    static var biometryIcon: String {
        switch biometryName {
        case "Face ID": "faceid"
        case "Touch ID": "touchid"
        case "Optic ID": "opticid"
        default: "lock"
        }
    }

    static func unlock() async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = String(localized: "Annuleren")
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Ontgrendel LRbeheer"))) == true
    }
}
