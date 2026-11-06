import SwiftUI

// MARK: - Overview (GET /v1/beheer/overview)

struct Overview: Decodable {
    struct Feed: Decodable { let lastOk: String?; let lastError: String? }
    struct Status: Decodable {
        let feed: Feed
        let cron: String?
        let apns: Bool
        let weatherkit: Bool
        let mapkit: Bool
        let mapsServer: Bool
        let meldingenInDatabase: Int
        let outbox: Int
        let beheerApparaten: Int
    }
    struct Meldingen: Decodable {
        let vandaag: Int
        let gisteren: Int
        let perDienst: [String: Int]
        let perDienstGisteren: [String: Int]
    }
    struct DayCount: Decodable, Identifiable { let day: String; let n: Int; var id: String { day } }
    struct Platform: Decodable, Identifiable { let platform: String; let n: Int; var id: String { platform } }
    struct Version: Decodable, Identifiable {
        let version: String?; let build: String?; let n: Int
        var id: String { "\(version ?? "?")-\(build ?? "?")" }
        var label: String { "\(version ?? "?") (\(build ?? "?"))" }
    }
    struct YesNo: Decodable { let ja: Int; let nee: Int }
    struct Push: Decodable { let aan: Int; let uit: Int; let toestellen: Int }
    struct App: Decodable {
        let totaal: Int
        let actief: Int
        let appleLogin: YesNo
        let push: Push
        let platforms: [Platform]
        let versies: [Version]
        let nieuwPerDag: [DayCount]
        let actiefPerDag: [DayCount]
    }
    struct Visit: Decodable, Identifiable { let day: String; let bezoekers: Int; let paginas: Int; var id: String { day } }
    struct Page: Decodable, Identifiable { let path: String; let n: Int; var id: String { path } }
    struct DeviceSplit: Decodable, Identifiable { let device: String?; let n: Int; var id: String { device ?? "?" } }
    struct Website: Decodable {
        let vandaag: Int
        let gisteren: Int
        let bezoeken7: Int
        let bezoeken30: Int
        let paginasVandaag: Int
        let perDag: [Visit]
        let topPaginas: [Page]
        let apparaten: [DeviceSplit]
    }
    struct Top: Decodable, Identifiable {
        let guid: String; let title: String; let dienst: String?; let views: Int; let datum_tijd: String
        var id: String { guid }
    }
    let generated: String
    let status: Status
    let meldingen: Meldingen
    let app: App
    let website: Website
    let topBekeken: [Top]
    /// A-Alerts: bronnen, helikopters, waarschuwingen en profielen (nieuwere server).
    let aAlerts: AAlertsOverview?
}

// MARK: - Alerts

struct AdminMelding: Codable, Identifiable, Hashable {
    let guid: String
    var title: String
    let full_melding: String?
    let dienst: String?
    let prioriteit: String?
    let datum_tijd: String
    var locatie: String?
    var lat: Double?
    var lon: Double?
    let stad: String?
    var categorie: String?
    let capcode: String?
    let views: Int?
    var hidden: Bool?
    var edited: Bool?
    var id: String { guid }
    var date: Date { Fmt.parse(datum_tijd) ?? .distantPast }
    var isHidden: Bool { hidden ?? false }
}

// MARK: - Push

struct BroadcastItem: Decodable, Identifiable {
    let id: String
    let at: String
    let title: String
    let body: String
    let plaatsen: [String]?
    let ontvangers: Int?
}

struct QueuedResult: Decodable { let queued: Int }

// MARK: - Texts

struct ContentDoc: Codable {
    var title: String?
    var content: String
    var version: String?
    var updated_at: String?
}

struct ChangelogEntry: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var version: String
    var release_date: String
    var content: String
}

// MARK: - Helpers

enum Dienst {
    static func color(_ d: String?) -> Color {
        switch d {
        case "brandweer": return Color(red: 0.89, green: 0.02, blue: 0.07)
        case "ambulance": return Color(red: 0.96, green: 0.77, blue: 0.0)
        case "politie": return Color(red: 0.08, green: 0.26, blue: 0.55)
        case "traumaheli": return Color(red: 0.58, green: 0.2, blue: 0.92)
        default: return .gray
        }
    }
    static func symbol(_ d: String?) -> String {
        switch d {
        case "brandweer": return "flame.fill"
        case "ambulance": return "cross.case.fill"
        case "politie": return "shield.lefthalf.filled"
        case "traumaheli": return "airplane"
        default: return "bell.fill"
        }
    }
    static func label(_ d: String?) -> String {
        switch d {
        case "brandweer": return "Brandweer"
        case "ambulance": return "Ambulance"
        case "politie": return "Politie"
        case "traumaheli": return "Lifeliner"
        default: return "Overig"
        }
    }
    static let all = ["brandweer", "ambulance", "politie", "traumaheli"]
}

enum Fmt {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }
    static func dayDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        return f.date(from: s) ?? .now
    }
    static func relative(_ s: String?) -> String {
        guard let d = parse(s) else { return "nooit" }
        return d.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
    static func dateTime(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}

enum PlatformName {
    static func label(_ p: String) -> String {
        switch p {
        case "ios": return "iPhone"
        case "ipados": return "iPad"
        case "macos": return "Mac"
        case "watchos": return "Apple Watch"
        case "tvos": return "Apple TV"
        case "visionos": return "Vision Pro"
        default: return p
        }
    }
    static func color(_ p: String) -> Color {
        switch p {
        case "ios": return .red
        case "ipados": return .orange
        case "macos": return .blue
        case "watchos": return .green
        case "tvos": return .purple
        default: return .gray
        }
    }
}

let PLAATSEN = ["Apeldoorn", "Beekbergen", "Beemte-Broekland", "Hoenderloo", "Hoog Soeren", "Klarenbeek",
                "Lieren", "Loenen", "Radio Kootwijk", "Teuge", "Uddel", "Ugchelen", "Wenum-Wiesel"]
