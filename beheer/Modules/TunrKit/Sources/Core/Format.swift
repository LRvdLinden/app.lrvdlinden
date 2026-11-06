import Foundation

/// Opmaak van getallen, datums, landen, talen en platforms (in de taal van de app).
enum Fmt {
    static func num(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = AppLanguage.locale
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// "12,5%" of "12.5%"; onder 10% met één decimaal.
    static func percent(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "0%" }
        let p = Double(part) / Double(total)
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.locale = AppLanguage.locale
        f.maximumFractionDigits = p < 0.1 ? 1 : 0
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: p)) ?? "\(Int(p * 100))%"
    }

    static func bytes(_ n: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func shortDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: d)
    }

    static func longDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f.string(from: d)
    }

    /// Datum met een sjabloon in de taal van de app (bv. "EEE d" → "ma 12"); Nederlands zonder punten na afkortingen.
    static func day(_ d: Date, template: String) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.setLocalizedDateFormatFromTemplate(template)
        let s = f.string(from: d)
        return AppLanguage.code == "nl" ? s.replacingOccurrences(of: ".", with: "") : s
    }

    /// Periode als "18 sep – 17 okt 2026".
    static func period(_ from: Date, _ to: Date) -> String {
        let f = DateIntervalFormatter()
        f.locale = AppLanguage.locale
        f.dateTemplate = "d MMM y"
        let s = f.string(from: from, to: to)
        return AppLanguage.code == "nl" ? s.replacingOccurrences(of: ".", with: "") : s
    }

    /// Getal met hoogstens één decimaal ("479,1").
    static func decimal(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = AppLanguage.locale
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// `yyyy-MM-dd` als lokale middernacht (voor de grafiek).
    static func parseDay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    /// ISO 8601 met of zonder fracties, of alleen een datum.
    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        if s.count == 10 { return parseDay(s) }
        return nil
    }

    // MARK: namen

    /// Vlag-emoji bij een landcode van twee letters ("NL" → 🇳🇱).
    static func flag(_ code: String) -> String {
        let c = code.uppercased()
        guard c.count == 2, c.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "🏳️" }
        var out = ""
        for s in c.unicodeScalars {
            if let f = UnicodeScalar(127397 + s.value) { out.unicodeScalars.append(f) }
        }
        return out
    }

    static func country(_ code: String) -> String {
        if code.isEmpty { return L("Onbekend") }
        return AppLanguage.locale.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }

    static func language(_ code: String) -> String {
        if code.isEmpty { return L("Onbekend") }
        let name = AppLanguage.locale.localizedString(forLanguageCode: code.lowercased()) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Platformsleutel uit `installs.platform` → naam.
    static func platform(_ key: String) -> String {
        switch key.lowercased() {
        case "ios": return "iPhone"
        case "ipados": return "iPad"
        case "macos": return "Mac"
        case "tvos": return "Apple TV"
        case "watchos": return "Apple Watch"
        case "android": return "Android"
        case "androidtv": return "Android TV"
        case "windows": return "Windows"
        case "web": return "Web"
        case "": return L("Onbekend")
        default: return key
        }
    }

    static func platformIcon(_ key: String) -> String {
        switch key.lowercased() {
        case "ios": return "iphone"
        case "ipados": return "ipad"
        case "macos": return "laptopcomputer"
        case "tvos": return "appletv"
        case "watchos": return "applewatch"
        case "android": return "smartphone"
        case "androidtv": return "tv"
        case "windows": return "pc"
        case "web": return "globe"
        default: return "questionmark.circle"
        }
    }

    /// Type apparaat (zoals de app hem stuurt, bv. "Android-telefoon") → weergave in de taal van de app.
    static func device(_ key: String) -> String {
        if key.isEmpty { return L("Onbekend") }
        switch key {
        case "Android-telefoon": return L("Android-telefoon")
        case "Android-tablet": return L("Android-tablet")
        case "Browser": return L("Browser")
        default: return key
        }
    }

    static func deviceIcon(_ key: String) -> String {
        switch key {
        case "iPhone": return "iphone"
        case "iPad": return "ipad"
        case "Mac": return "laptopcomputer"
        case "Apple TV": return "appletv"
        case "Apple Watch": return "applewatch"
        case "Android-telefoon": return "smartphone"
        case "Android-tablet": return "ipad.landscape"
        case "Android TV", "Google TV", "Fire TV": return "tv"
        case "Browser": return "globe"
        default: return "questionmark.circle"
        }
    }
}
