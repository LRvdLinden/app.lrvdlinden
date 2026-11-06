// Gegenereerd door tools/import_modules.py — niet met de hand wijzigen.
import Foundation

extension UserDefaults {
    /// Eigen UserDefaults-suite van deze beheeromgeving binnen LRbeheer, zodat sleutels van de verschillende
    /// beheerapps (bv. push.device_id, lockEnabled) niet botsen.
    static let module: UserDefaults = UserDefaults(suiteName: "app.lrvdlinden.lrbeheer.pasr") ?? .standard
}
