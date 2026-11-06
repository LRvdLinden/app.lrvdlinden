import Foundation

/// Vertaalde tekst uit Localizable.strings (Nederlands is de standaard en tevens de sleutel; Engels in en.lproj).
func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Tunr", comment: "")
}

enum AppLanguage {
    /// Taal waarin de app nu draait ("nl" of "en").
    static var code: String {
        let first = Bundle.main.preferredLocalizations.first ?? "nl"
        return first.hasPrefix("en") ? "en" : "nl"
    }

    /// Locale voor namen van landen en talen, datums en getallen in de taal van de app.
    static var locale: Locale {
        Locale(identifier: code == "en" ? "en_GB" : "nl_NL")
    }
}
