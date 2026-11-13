import Foundation
import Observation
import UIKit

/// Toestand van het beheer van lrvdlinden.app: apps.json, concept, afbeeldingen, publiceren, store-check en logboek.
/// Zelfde endpoints en regels als site/beheer.html (publish.php, store-refresh.php, store-log.php, translate.php).
@MainActor
@Observable
final class LRvdLindenStore {
    static let shared = LRvdLindenStore()
    static let site = URL(string: "https://lrvdlinden.app/")!

    // store-log.php: GET, achter de .htaccess-login, verandert niets
    let account = SiteAccount(id: "lrvdlinden", base: site, headerName: "X-LR-Beheer", verifyMethod: "GET", verifyPath: "store-log.php")

    private(set) var original: JSON = .object([("apps", .array([]))])
    var data: JSON = .object([("apps", .array([]))]) { didSet { save() } }
    var pending: [String: Data] = [:] { didSet { save() } }
    var selection: String?

    private(set) var loading = false
    private(set) var loaded = false
    private(set) var publishing = false
    private(set) var translating = false
    var fetchingMode: String?
    var result: Banner?
    var toast: String?

    var log: StoreLog?
    var logError: String?

    struct Banner: Identifiable, Equatable {
        enum Kind { case good, warn, bad }
        let id = UUID()
        let kind: Kind
        let text: String
        var runID: String?
    }

    var dirty: Bool { data != original || !pending.isEmpty }
    var apps: [JSON] { data["apps"]?.items ?? [] }

    func app(_ id: String) -> JSON? { apps.first { $0["id"]?.str == id } }

    // MARK: laden

    func load() async {
        guard let client = account.client, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let server = try JSON.parse(try await client.request("GET", "apps.json", beheerHeader: false))
            let draft = DraftStore.load("lrvdlinden")
            original = server
            if let draft {
                if draft.base == server {
                    data = draft.data
                    pending = draft.files
                    if dirty { toast = String(localized: "Je niet-gepubliceerde wijzigingen zijn teruggezet") }
                } else {
                    let m = DraftStore.merge(base: draft.base, draft: draft.data, server: server, list: "apps")
                    data = m.data
                    pending = draft.files
                    if !m.kept.isEmpty {
                        result = Banner(kind: .warn, text: String(format: String(localized: "De site is intussen gewijzigd. Je concept is samengevoegd met de nieuwste versie. Behouden uit je concept: %@. Controleer en publiceer, of gooi de wijzigingen weg."), m.kept.joined(separator: ", ")))
                    }
                }
            } else {
                data = server
            }
            if selection == nil || app(selection!) == nil { selection = apps.first?["id"]?.str }
            loaded = true
        } catch SiteClient.Failure.unauthorized {
            account.signOut()
        } catch {
            result = Banner(kind: .bad, text: String(localized: "apps.json laden mislukt.") + " " + error.localizedDescription)
        }
    }

    private func save() {
        guard loaded else { return }
        if dirty { DraftStore.save("lrvdlinden", Draft(base: original, data: data, files: pending)) } else { DraftStore.clear("lrvdlinden") }
    }

    // MARK: bewerken

    func update(_ id: String, _ change: (inout JSON) -> Void) {
        guard var list = data["apps"]?.items, let i = list.firstIndex(where: { $0["id"]?.str == id }) else { return }
        change(&list[i])
        data["apps"] = .array(list)
    }

    /// ID wijzigen (kleine letters, cijfers en streepjes; uniek), zoals in beheer.html.
    func rename(_ id: String, to raw: String) {
        let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression)
        guard !v.isEmpty, v != id, app(v) == nil else { return }
        update(id) { $0["id"] = .string(v) }
        selection = v
    }

    func newApp() {
        var n = 1
        var nid = "nieuwe-app-1"
        while app(nid) != nil { n += 1; nid = "nieuwe-app-\(n)" }
        let a: JSON = .object([
            ("id", .string(nid)), ("name", .string(String(localized: "Nieuwe app"))), ("section", .string("ios")),
            ("status", .string("dev")), ("featured", .bool(true)), ("category", .string("utilities")),
            ("platforms", .array([.string("iPhone")])),
            ("description", .object([("nl", .string("")), ("en", .string(""))])),
            ("links", .object([])), ("history", .array([])),
        ])
        data["apps"] = .array([a] + apps)
        selection = nid
    }

    func delete(_ id: String) {
        let name = app(id)?["name"]?.str ?? id
        data["apps"] = .array(apps.filter { $0["id"]?.str != id })
        if selection == id { selection = apps.first?["id"]?.str }
        toast = String(format: String(localized: "%@ verwijderd"), name)
    }

    func move(_ id: String, by delta: Int) {
        var list = apps
        guard let i = list.firstIndex(where: { $0["id"]?.str == id }) else { return }
        let j = i + delta
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        data["apps"] = .array(list)
    }

    func discard() {
        guard dirty else { toast = String(localized: "Er zijn geen wijzigingen"); return }
        data = original
        pending = [:]
        DraftStore.clear("lrvdlinden")
        selection = apps.first?["id"]?.str
        toast = String(localized: "Wijzigingen weggegooid")
    }

    /// Bestand openen (Meer → Bestand openen in beheer.html).
    func importFile(_ d: Data) throws {
        let j = try JSON.parse(d)
        guard j["apps"] != nil else { throw JSON.ParseError() }
        data = j
        selection = nil
    }

    // MARK: afbeeldingen

    func setIcon(_ id: String, image: UIImage) {
        guard let bin = ImageTools.cover(image, width: 256, height: 256) else { return }
        let path = "img/\(id).jpg"
        pending = pending.filter { !$0.key.hasPrefix("img/\(id).") }
        pending[path] = bin
        update(id) { $0["icon"] = .string(path) }
        toast = String(localized: "Icoon klaar. Publiceer om het live te zetten.")
    }

    func setBanner(_ id: String, lang: String, image: UIImage) {
        guard let bin = ImageTools.cover(image, width: 1600, height: 900, quality: 0.8) else { return }
        let path = "img/promo-\(id)-\(lang).jpg"
        pending = pending.filter { !$0.key.hasPrefix("img/promo-\(id)-\(lang).") }
        pending[path] = bin
        update(id) { a in
            var promo = a["promo"] ?? .object([])
            var image = promo["image"] ?? .object([])
            if case let .string(s) = image { image = .object([("nl", .string(s))]) }
            image[lang] = .string(path)
            promo["image"] = image
            promo["show"] = .bool(true)
            a["promo"] = promo
        }
        toast = String(format: String(localized: "Banner %@ klaar. Publiceer om hem live te zetten."), lang.uppercased())
    }

    func removeBanner(_ id: String, lang: String) {
        update(id) { a in
            guard var promo = a["promo"], var image = promo["image"] else { return }
            if case let .string(s) = image { image = .object([("nl", .string(s))]) }
            if let p = image[lang]?.str { pending[p] = nil }
            image[lang] = nil
            promo["image"] = image.keys.isEmpty ? nil : image
            a["promo"] = promo
        }
    }

    static func banner(_ a: JSON, _ lang: String) -> String {
        guard let im = a.value(path: "promo.image") else { return "" }
        if case let .string(s) = im { return lang == "nl" ? s : "" }
        return im[lang]?.str ?? ""
    }

    // MARK: publiceren

    private func changedNames() -> [String] {
        let before = original["apps"]?.items ?? []
        let map = Dictionary(before.compactMap { a in a["id"]?.str.map { ($0, a) } }, uniquingKeysWith: { x, _ in x })
        let now = Set(apps.compactMap { $0["id"]?.str })
        let changed = apps.filter { a in a["id"]?.str.flatMap { map[$0] } != a }.compactMap { $0["name"]?.str }
        let removed = before.filter { !now.contains($0["id"]?.str ?? "") }.compactMap { $0["name"]?.str.map { $0 + " (verwijderd)" } }
        return changed + removed
    }

    func publish() async {
        guard let client = account.client, dirty, !publishing else { return }
        let names = changedNames()
        let message = "Beheer: " + (names.isEmpty ? "volgorde of iconen"
            : names.prefix(5).joined(separator: ", ") + (names.count > 5 ? " en \(names.count - 5) meer" : "")) + " bijgewerkt"
        publishing = true
        result = nil
        defer { publishing = false }
        do {
            // Intussen iets veranderd op de site (store-check, content-sync, web-beheer)? Eerst samenvoegen,
            // zodat alleen de apps die je hier wijzigde worden overschreven.
            if let raw = try? await client.request("GET", "apps.json", beheerHeader: false),
               let server = try? JSON.parse(raw), server != original {
                data = DraftStore.merge(base: original, draft: data, server: server, list: "apps").data
                original = server
                save()
            }
            let res = try await client.publish(data: data, files: pending.map { ($0.key, $0.value.base64EncodedString()) },
                                               message: message)
            original = data
            pending = [:]
            DraftStore.clear("lrvdlinden")
            if (res["github"] as? Bool) == false {
                result = Banner(kind: .warn, text: String(localized: "Live gezet.") + " " + (res["warning"] as? String ?? ""))
            } else if (res["unchanged"] as? Bool) == true {
                result = Banner(kind: .good, text: String(localized: "Live gezet. Er was niets veranderd ten opzichte van GitHub."))
            } else {
                result = Banner(kind: .good, text: String(format: String(localized: "Live gezet en opgeslagen in GitHub (commit %@). GitHub zet de site nu opnieuw neer en maakt een zip-release."), res["commit"] as? String ?? ""))
            }
            toast = String(localized: "Gepubliceerd")
        } catch {
            result = Banner(kind: .bad, text: String(localized: "Publiceren mislukt.") + " " + error.localizedDescription + " " + String(localized: "Je wijzigingen staan nog op dit apparaat, probeer het opnieuw."))
        }
    }

    // MARK: vertalen (translate.php)

    func translate(_ id: String, overwrite: Bool) async {
        guard let client = account.client, !translating, let a = app(id) else { return }
        var paths = ["subtitle", "description", "badge", "promo.eyebrow", "promo.title", "promo.text"]
        for (i, _) in (a["history"]?.items ?? []).enumerated() { paths.append("history.\(i).notes") }
        struct Job { let path: String; let to: String; let text: String }
        var jobs: [Job] = []
        for p in paths {
            guard let obj = Self.historyAware(a, p), obj.isObject else { continue }
            let nl = (obj["nl"]?.str ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let en = (obj["en"]?.str ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !nl.isEmpty && (en.isEmpty || overwrite) { jobs.append(Job(path: p, to: "en", text: nl)) }
            else if !en.isEmpty && nl.isEmpty { jobs.append(Job(path: p, to: "nl", text: en)) }
        }
        if jobs.isEmpty {
            toast = overwrite ? String(localized: "Er staan geen Nederlandse teksten bij deze app")
                : String(localized: "Alles is al vertaald. Zet 'overschrijven' aan om opnieuw te vertalen.")
            return
        }
        translating = true
        defer { translating = false }
        do {
            var out: [String] = []
            for start in stride(from: 0, to: jobs.count, by: 40) {
                let chunk = jobs[start..<min(start + 40, jobs.count)]
                let res = try await client.call("POST", "translate.php", body: ["items": chunk.map { ["text": $0.text, "to": $0.to] }])
                out += (res["texts"] as? [Any] ?? []).map { $0 as? String ?? "" }
            }
            var n = 0
            update(id) { app in
                for (i, j) in jobs.enumerated() where i < out.count && !out[i].isEmpty {
                    Self.setHistoryAware(&app, j.path + "." + j.to, out[i])
                    n += 1
                }
            }
            toast = n > 0 ? String(format: String(localized: "%lld teksten vertaald. Controleer ze en publiceer."), n)
                : String(localized: "Er kwam geen vertaling terug")
        } catch {
            result = Banner(kind: .bad, text: String(localized: "Vertalen mislukt.") + " " + error.localizedDescription)
        }
    }

    /// Pad met een index in history ("history.2.notes").
    static func historyAware(_ a: JSON, _ path: String) -> JSON? {
        let parts = path.split(separator: ".").map(String.init)
        if parts.first == "history", parts.count >= 2, let i = Int(parts[1]) {
            let h = a["history"]?.items ?? []
            guard h.indices.contains(i) else { return nil }
            return parts.count == 2 ? h[i] : h[i].value(path: parts.dropFirst(2).joined(separator: "."))
        }
        return a.value(path: path)
    }

    static func setHistoryAware(_ a: inout JSON, _ path: String, _ text: String) {
        let parts = path.split(separator: ".").map(String.init)
        if parts.first == "history", parts.count >= 3, let i = Int(parts[1]) {
            var h = a["history"]?.items ?? []
            guard h.indices.contains(i) else { return }
            h[i].set(path: parts.dropFirst(2).joined(separator: "."), .string(text))
            a["history"] = .array(h)
        } else {
            a.set(path: path, .string(text))
        }
    }

    // MARK: store-check (store-refresh.php) en logboek (store-log.php)

    func fetchStores(mode: String, url addURL: String = "", nlOnly: Bool = false) async {
        guard let client = account.client, fetchingMode == nil else { return }
        fetchingMode = mode
        defer { fetchingMode = nil }
        let started = Date()
        let what = mode == "bijwerken" ? String(localized: "Alle apps worden bijgewerkt.")
            : mode == "toevoegen" ? String(localized: "De app wordt opgehaald en toegevoegd.") : String(localized: "Er wordt naar nieuwe apps gezocht.")
        let dur = mode == "bijwerken" ? String(localized: "3 tot 5 minuten") : mode == "toevoegen" ? String(localized: "1 tot 2 minuten") : String(localized: "1 tot 3 minuten")
        func status(_ t: String) {
            result = Banner(kind: .warn, text: "\(what) \(t) " + String(format: String(localized: "Dit duurt meestal %@; je kunt intussen gewoon verder werken."), dur))
        }
        do {
            status(String(localized: "Opdracht wordt gestart…"))
            var query = ["mode": mode]
            if mode == "toevoegen" {
                query["url"] = addURL
                if nlOnly { query["nlonly"] = "1" }
            }
            let st = try await client.call("POST", "store-refresh.php", query: query)
            let since = st["since"] as? String ?? ""
            var res: [String: Any] = [:]
            while true {
                try await Task.sleep(for: .seconds(6))
                let secs = Int(Date().timeIntervalSince(started))
                if secs > 600 { throw SiteClient.Failure.server(String(localized: "Het duurt langer dan 10 minuten. Kijk op GitHub bij Actions → Store-check.")) }
                res = try await client.call("GET", "store-refresh.php", query: ["since": since])
                let state = res["state"] as? String ?? ""
                if state == "done" { break }
                if state == "failed" { throw SiteClient.Failure.server(String(localized: "De controle op GitHub is mislukt. Bekijk de details in het logboek.")) }
                status(state == "running" ? String(format: String(localized: "Bezig (%lld s)…"), secs) : String(format: String(localized: "In de wachtrij (%lld s)…"), secs))
            }
            // nieuwe gegevens inladen; niet-gepubliceerde wijzigingen blijven behouden
            let server = try JSON.parse(try await client.request("GET", "apps.json", beheerHeader: false))
            let beforeIDs = Set((original["apps"]?.items ?? []).compactMap { $0["id"]?.str })
            let added = (server["apps"]?.items ?? []).filter { !beforeIDs.contains($0["id"]?.str ?? "") }.compactMap { $0["name"]?.str }
            if dirty { data = DraftStore.merge(base: original, draft: data, server: server, list: "apps").data } else { data = server }
            original = server
            save()
            if selection.flatMap({ app($0) }) == nil { selection = apps.first?["id"]?.str }
            if mode == "toevoegen" {
                // de nieuwe (of aangevulde) app meteen openen
                let core = addURL.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                let hit = (server["apps"]?.items ?? []).first { !beforeIDs.contains($0["id"]?.str ?? "") }
                    ?? (server["apps"]?.items ?? []).first { a in
                        let links = a["links"]
                        return (links?.keys ?? []).contains { k in
                            let s = (links?[k]?.str ?? "").replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                            return !s.isEmpty && core.contains(s.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                        }
                    }
                if let id = hit?["id"]?.str { selection = id }
            }
            let runNumber = (res["url"] as? String)?.components(separatedBy: "runs/").last
            let changed = (res["changed"] as? Bool) == true
            let text: String
            if mode == "toevoegen" {
                text = !added.isEmpty
                    ? String(format: String(localized: "%@ is toegevoegd. Controleer de gegevens, zet eventueel Tonen in Nieuw en onderweg, Alleen Nederlands of een banner aan, en publiceer als je iets aanpast. De app staat al live met een eigen pagina."), added.joined(separator: ", "))
                    : changed ? String(localized: "Bestaande app aangevuld met de gegevens van de link.")
                    : String(localized: "Niets toegevoegd. De app staat al op de site of de link gaf geen gegevens. Bekijk het logboek voor details.")
            } else if !added.isEmpty {
                text = String(format: String(localized: "Nieuwe apps toegevoegd: %@. Controleer ze en zet eventueel Tonen in Nieuw en onderweg of een banner aan."), added.joined(separator: ", "))
            } else if changed {
                text = mode == "bijwerken" ? String(localized: "Bijgewerkt. Versies, teksten, beoordelingen of Homey-details zijn vernieuwd.")
                    : String(localized: "Aangevuld. Geen nieuwe apps, wel beta-apps aangevuld met gegevens uit de store.")
            } else {
                text = mode == "bijwerken" ? String(localized: "Alles is al bij. Er waren geen nieuwe versies of beoordelingen.")
                    : String(localized: "Geen nieuwe apps. Alle apps uit de App Store en de Homey App Store staan al op de site.")
            }
            result = Banner(kind: .good, text: text, runID: runNumber)
            if log != nil { await loadLog() }
        } catch is CancellationError {
            result = nil
        } catch {
            result = Banner(kind: .bad, text: String(localized: "Ophalen mislukt.") + " " + error.localizedDescription)
        }
    }

    func loadLog() async {
        guard let client = account.client else { return }
        do {
            let d = try await client.request("GET", "store-log.php")
            log = try JSONDecoder().decode(StoreLog.self, from: d)
            if log?.ok == false { logError = log?.error; log = nil } else { logError = nil }
        } catch {
            logError = error.localizedDescription
        }
    }
}

/// Antwoord van store-log.php: logs/store-check.json plus lopende of mislukte runs op GitHub.
struct StoreLog: Decodable {
    let ok: Bool
    var error: String?
    var runs: [Run] = []
    var active: [Active] = []

    struct Run: Decodable, Identifiable {
        let id: String
        let time: String?
        let mode: String?
        let trigger: String?
        let changed: Bool?
        let lines: [String]?
        let checked: [Checked]?
        let url: String?

        enum CodingKeys: String, CodingKey { case id, time, mode, trigger, changed, lines, checked, url }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            if let s = try? c.decode(String.self, forKey: .id) { id = s } else { id = String((try? c.decode(Int.self, forKey: .id)) ?? 0) }
            time = try? c.decode(String.self, forKey: .time)
            mode = try? c.decode(String.self, forKey: .mode)
            trigger = try? c.decode(String.self, forKey: .trigger)
            changed = try? c.decode(Bool.self, forKey: .changed)
            lines = try? c.decode([String].self, forKey: .lines)
            checked = try? c.decode([Checked].self, forKey: .checked)
            url = try? c.decode(String.self, forKey: .url)
        }
    }

    struct Checked: Decodable, Hashable {
        let app: String?
        let store: String?
        let version: String?
        let date: String?
        let changed: Bool?
        let test: String?

        enum CodingKeys: String, CodingKey { case app, store, version, date, changed, test }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            func text(_ k: CodingKeys) -> String? {
                (try? c.decode(String.self, forKey: k)) ?? (try? c.decode(Double.self, forKey: k)).map { String($0) }
            }
            app = text(.app); store = text(.store); version = text(.version); date = text(.date); test = text(.test)
            changed = try? c.decode(Bool.self, forKey: .changed)
        }
    }

    struct Active: Decodable, Identifiable {
        let id: String
        let time: String?
        let trigger: String?
        let state: String?
        let url: String?
    }

    enum CodingKeys: String, CodingKey { case ok, error, runs, active }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        error = try? c.decode(String.self, forKey: .error)
        runs = (try? c.decode([Run].self, forKey: .runs)) ?? []
        active = (try? c.decode([Active].self, forKey: .active)) ?? []
    }
}
