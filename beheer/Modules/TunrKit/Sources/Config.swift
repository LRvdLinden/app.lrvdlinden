import Foundation

/// Openbare instellingen van het Supabase-project **tunr** (zelfde waarden als web/config.js; zie docs/CONTRACT.md).
/// De publishable key is bedoeld om openbaar te zijn. Zolang de URL leeg is, toont de app "Nog niet ingericht".
enum Config {
    static let supabaseURL = "https://vbhkewgyujzgbukkbtml.supabase.co"
    static let publishableKey = "sb_publishable_0Fp86h5uCovv00KReb3Pvg_lTH7TwU6"

    /// Is het project ingericht (URL en sleutel ingevuld)?
    static var isConfigured: Bool {
        !supabaseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !publishableKey.trimmingCharacters(in: .whitespaces).isEmpty
            && adminFunction != nil
    }

    /// `{SUPABASE_URL}/functions/v1/admin`
    static var adminFunction: URL? {
        var base = supabaseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/functions/v1/admin")
    }

    static let website = URL(string: "https://tunr.online")!
    static let webPlayer = URL(string: "https://tunr.online/web/")!
    static let beheerSite = URL(string: "https://beheer.tunr.online")!
}
