import Foundation

// Antwoorden van de functie `admin` (docs/CONTRACT.md). Ruim gedecodeerd: ontbrekende velden worden 0 of leeg,
// zodat een iets nieuwere server de app niet breekt.

/// Getal of tekst ("14" of 14) uit JSON.
struct FlexValue: Decodable, Hashable {
    let text: String?
    let number: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            text = nil; number = nil
        } else if let i = try? c.decode(Int.self) {
            text = String(i); number = Double(i)
        } else if let d = try? c.decode(Double.self) {
            text = d.rounded() == d ? String(Int(d)) : String(d); number = d
        } else if let s = try? c.decode(String.self) {
            text = s; number = Double(s)
        } else if let b = try? c.decode(Bool.self) {
            text = b ? "true" : "false"; number = b ? 1 : 0
        } else {
            text = nil; number = nil
        }
    }

    /// Als datum: ISO 8601 (met of zonder fracties), `yyyy-MM-dd`, of Unix-tijd (seconden of milliseconden).
    var date: Date? {
        if let s = text, let d = Fmt.parseDate(s) { return d }
        if let n = number {
            return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n)
        }
        return nil
    }
}

struct LoginResponse: Decodable {
    let token: String
    let expires: FlexValue?
}

struct OKResponse: Decodable {
    let ok: Bool?
}

// MARK: stats

struct Stats: Decodable {
    let generated: FlexValue?
    let totals: Totals
    /// Periode van `per_day` (ontbreekt bij een oudere server: dan berekent de app hem uit de keuze).
    let range: StatsRangeInfo?
    let perDay: [DayPoint]
    /// Samenvatting per reeks over `per_day` (ontbreekt bij een oudere server: dan rekent de app hem zelf uit).
    let summary: StatsSummary?
    let platforms: [Bucket]
    let devices: [Bucket]
    let versions: [Bucket]
    let countries: [Bucket]
    let langs: [Bucket]
    /// Presskit: versie en downloads (ontbreekt bij een oudere server).
    let presskit: PresskitInfo?

    enum CodingKeys: String, CodingKey {
        case generated, totals, range, summary, platforms, devices, versions, countries, langs, presskit
        case perDay = "per_day"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generated = try? c.decodeIfPresent(FlexValue.self, forKey: .generated)
        totals = ((try? c.decodeIfPresent(Totals.self, forKey: .totals)) ?? nil) ?? Totals.empty
        range = (try? c.decodeIfPresent(StatsRangeInfo.self, forKey: .range)) ?? nil
        perDay = ((try? c.decodeIfPresent([DayPoint].self, forKey: .perDay)) ?? nil) ?? []
        summary = (try? c.decodeIfPresent(StatsSummary.self, forKey: .summary)) ?? nil
        platforms = ((try? c.decodeIfPresent([Bucket].self, forKey: .platforms)) ?? nil) ?? []
        devices = ((try? c.decodeIfPresent([Bucket].self, forKey: .devices)) ?? nil) ?? []
        versions = ((try? c.decodeIfPresent([Bucket].self, forKey: .versions)) ?? nil) ?? []
        countries = ((try? c.decodeIfPresent([Bucket].self, forKey: .countries)) ?? nil) ?? []
        langs = ((try? c.decodeIfPresent([Bucket].self, forKey: .langs)) ?? nil) ?? []
        presskit = (try? c.decodeIfPresent(PresskitInfo.self, forKey: .presskit)) ?? nil
    }
}

// MARK: presskit (stats → presskit)

/// Blok `presskit` van `stats`: huidige versie (uit presskit.json op tunr.online) en de downloadtellingen.
struct PresskitInfo: Decodable {
    struct VersionCount: Identifiable {
        let version: String
        let count: Int
        var id: String { version }
    }

    struct DayCount: Identifiable {
        let day: String
        let count: Int
        var id: String { day }
        var date: Date { Fmt.parseDay(day) ?? Date.distantPast }
    }

    static let zipURL = URL(string: "https://tunr.online/presskit/Tunr-PressKit.zip")!

    let available: Bool
    let version: String
    let date: Date?
    let size: Int
    let files: Int
    let platforms: [String]
    let url: URL
    let downloadsTotal: Int
    let downloads30d: Int
    let perVersion: [VersionCount]
    let perDay: [DayCount]

    enum CodingKeys: String, CodingKey {
        case available, version, date, size, files, platforms, url
        case downloadsTotal = "downloads_total"
        case downloads30d = "downloads_30d"
        case perVersion = "per_version"
        case perDay = "per_day"
    }

    private struct Row: Decodable {
        let version: String
        let day: String
        let count: Int

        enum CodingKeys: String, CodingKey { case version, day, count }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func flex(_ k: CodingKeys) -> FlexValue? { (try? c.decodeIfPresent(FlexValue.self, forKey: k)) ?? nil }
            version = flex(.version)?.text ?? ""
            day = String((flex(.day)?.text ?? "").prefix(10))
            count = max(0, Int(flex(.count)?.number ?? 0))
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flex(_ k: CodingKeys) -> FlexValue? { (try? c.decodeIfPresent(FlexValue.self, forKey: k)) ?? nil }
        func int(_ k: CodingKeys) -> Int { max(0, Int(flex(k)?.number ?? 0)) }
        version = flex(.version)?.text ?? ""
        available = ((try? c.decodeIfPresent(Bool.self, forKey: .available)) ?? nil) ?? !version.isEmpty
        date = flex(.date)?.date
        size = int(.size)
        files = int(.files)
        platforms = ((try? c.decodeIfPresent([FlexValue].self, forKey: .platforms)) ?? nil)?.compactMap(\.text) ?? []
        // alleen een link naar de zip op tunr.online (nooit iets anders openen)
        if let s = flex(.url)?.text, s.hasPrefix(PresskitInfo.zipURL.absoluteString), let u = URL(string: s) {
            url = u
        } else {
            url = PresskitInfo.zipURL
        }
        downloadsTotal = int(.downloadsTotal)
        downloads30d = int(.downloads30d)
        let versions = ((try? c.decodeIfPresent([Row].self, forKey: .perVersion)) ?? nil) ?? []
        perVersion = versions.filter { $0.count > 0 }.map { VersionCount(version: $0.version, count: $0.count) }
        let days = ((try? c.decodeIfPresent([Row].self, forKey: .perDay)) ?? nil) ?? []
        perDay = days.filter { $0.day.count == 10 }.map { DayCount(day: $0.day, count: $0.count) }.sorted { $0.day < $1.day }
    }
}

struct Totals: Decodable {
    var installs = 0
    var activeToday = 0
    var active7d = 0
    var active30d = 0
    var newToday = 0
    var new7d = 0
    var carplay = 0

    static let empty = Totals()

    enum CodingKeys: String, CodingKey {
        case installs, carplay
        case activeToday = "active_today"
        case active7d = "active_7d"
        case active30d = "active_30d"
        case newToday = "new_today"
        case new7d = "new_7d"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ k: CodingKeys) -> Int {
            Int(((try? c.decodeIfPresent(FlexValue.self, forKey: k)) ?? nil)?.number ?? 0)
        }
        installs = int(.installs)
        activeToday = int(.activeToday)
        active7d = int(.active7d)
        active30d = int(.active30d)
        newToday = int(.newToday)
        new7d = int(.new7d)
        carplay = int(.carplay)
    }
}

struct DayPoint: Decodable, Identifiable {
    let day: String
    let active: Int
    let new: Int

    var id: String { day }
    var date: Date { Fmt.parseDay(day) ?? Date.distantPast }

    enum CodingKeys: String, CodingKey { case day, active, new }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = ((try? c.decodeIfPresent(String.self, forKey: .day)) ?? nil) ?? ""
        active = Int(((try? c.decodeIfPresent(FlexValue.self, forKey: .active)) ?? nil)?.number ?? 0)
        new = Int(((try? c.decodeIfPresent(FlexValue.self, forKey: .new)) ?? nil)?.number ?? 0)
    }
}

/// `range` van `stats`: `{from, to, days, offset}` (datums als `YYYY-MM-DD`, UTC).
struct StatsRangeInfo: Decodable, Equatable {
    let from: String
    let to: String
    let days: Int
    let offset: Int

    enum CodingKeys: String, CodingKey { case from, to, days, offset }

    init(from: String, to: String, days: Int, offset: Int) {
        self.from = from; self.to = to; self.days = days; self.offset = offset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flex(_ k: CodingKeys) -> FlexValue? { (try? c.decodeIfPresent(FlexValue.self, forKey: k)) ?? nil }
        from = String((flex(.from)?.text ?? "").prefix(10))
        to = String((flex(.to)?.text ?? "").prefix(10))
        days = Int(flex(.days)?.number ?? 0)
        offset = Int(flex(.offset)?.number ?? 0)
    }

    var isValid: Bool { from.count == 10 && to.count == 10 && from <= to }
}

/// Min, max, gemiddelde, laatste (en totaal) van één reeks.
struct SeriesSummary: Decodable, Equatable {
    var min = 0
    var max = 0
    var avg = 0.0
    var last = 0
    var total: Int? = nil

    enum CodingKeys: String, CodingKey { case min, max, avg, last, total }

    init(values: [Int], withTotal: Bool) {
        if let lo = values.min(), let hi = values.max(), let l = values.last {
            let sum = values.reduce(0, +)
            min = lo; max = hi; last = l
            avg = (Double(sum) / Double(values.count) * 10).rounded() / 10
        }
        if withTotal { total = values.reduce(0, +) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func n(_ k: CodingKeys) -> Double? { ((try? c.decodeIfPresent(FlexValue.self, forKey: k)) ?? nil)?.number }
        min = Int(n(.min) ?? 0)
        max = Int(n(.max) ?? 0)
        avg = n(.avg) ?? 0
        last = Int(n(.last) ?? 0)
        total = n(.total).map { Int($0) }
    }
}

struct StatsSummary: Decodable, Equatable {
    let active: SeriesSummary?
    let new: SeriesSummary?

    enum CodingKeys: String, CodingKey { case active, new }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = (try? c.decodeIfPresent(SeriesSummary.self, forKey: .active)) ?? nil
        new = (try? c.decodeIfPresent(SeriesSummary.self, forKey: .new)) ?? nil
    }
}

/// Eén rij van een verdeling (platform, apparaat, versie, land of taal).
struct Bucket: Decodable, Identifiable {
    let key: String
    let installs: Int
    let active30d: Int?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, installs
        case active30d = "active_30d"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = ((try? c.decodeIfPresent(FlexValue.self, forKey: .key)) ?? nil)?.text ?? ""
        installs = Int(((try? c.decodeIfPresent(FlexValue.self, forKey: .installs)) ?? nil)?.number ?? 0)
        if let a = ((try? c.decodeIfPresent(FlexValue.self, forKey: .active30d)) ?? nil)?.number {
            active30d = Int(a)
        } else {
            active30d = nil
        }
    }
}

// MARK: builds

struct BuildsResponse: Decodable {
    let ready: Bool
    let platforms: [String: [BuildInfo]]

    enum CodingKeys: String, CodingKey { case ready, platforms }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ready = ((try? c.decodeIfPresent(Bool.self, forKey: .ready)) ?? nil) ?? false
        platforms = ((try? c.decodeIfPresent([String: [BuildInfo]].self, forKey: .platforms)) ?? nil) ?? [:]
    }
}

struct BuildInfo: Decodable, Identifiable, Hashable {
    let version: String
    let build: String
    let file: String
    let size: Int?
    let sha256: String
    let date: Date?
    let notes: String

    var id: String { file }

    enum CodingKeys: String, CodingKey { case version, build, file, size, sha256, date, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flex(_ k: CodingKeys) -> FlexValue? { (try? c.decodeIfPresent(FlexValue.self, forKey: k)) ?? nil }
        version = flex(.version)?.text ?? ""
        build = flex(.build)?.text ?? ""
        file = flex(.file)?.text ?? ""
        size = flex(.size)?.number.map { Int($0) }
        sha256 = flex(.sha256)?.text ?? ""
        date = flex(.date)?.date
        notes = (flex(.notes)?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "1.0.0 (build 14)"
    var title: String {
        let b = build.isEmpty ? "" : String(format: L("build %@"), build)
        if version.isEmpty { return b.isEmpty ? file : b }
        return b.isEmpty ? version : "\(version) (\(b))"
    }

    /// Datum en grootte op één regel (oudere builds).
    var detail: String {
        [date.map { Fmt.date($0) }, size.map { Fmt.bytes($0) }].compactMap { $0 }.joined(separator: " · ")
    }
}

struct BuildLinkResponse: Decodable {
    let url: String
    let expires: FlexValue?
}

/// De platforms op de tab Downloads (play = Google Play, Android App Bundle; windows = Windows-installer).
enum BuildPlatform: String, CaseIterable, Identifiable {
    case apple, android, play, windows, beheer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return L("Apple")
        case .android: return L("Android")
        case .play: return "Google Play"
        case .windows: return "Windows"
        case .beheer: return "BeheerTunr"
        }
    }

    var hint: String {
        switch self {
        case .apple: return L("Xcode-project (zip) voor iPhone, iPad, Mac, Apple TV, Apple Watch en CarPlay")
        case .android: return L("APK voor telefoon, tablet, Android TV en Android Auto")
        case .play: return L("Android App Bundle (.aab) voor de Play Console")
        case .windows: return L("Installer (.exe) voor de desktop-app voor Windows")
        case .beheer: return L("Xcode-project (zip) van deze beheer-app")
        }
    }

    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .android: return "smartphone"
        case .play: return "play.rectangle"
        case .windows: return "pc"
        case .beheer: return "gauge.with.dots.needle.67percent"
        }
    }
}
