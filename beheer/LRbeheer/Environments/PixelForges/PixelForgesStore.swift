import Foundation
import Observation
import UIKit

/// Toestand van het beheer van pixelforges.nl: content.json, concept, afbeeldingen, ophalen van websites en publiceren.
/// Zelfde endpoints, schema en regels als site/beheer.html (publish.php, fetch-meta.php).
@MainActor
@Observable
final class PixelForgesStore {
    static let shared = PixelForgesStore()
    static let site = URL(string: "https://pixelforges.nl/")!

    let account = SiteAccount(id: "pixelforges", base: site, headerName: "X-PF-Beheer")

    private(set) var original: JSON = .object([])
    var data: JSON = .object([]) { didSet { save() } }
    var pending: [String: Data] = [:] { didSet { save() } }

    private(set) var loading = false
    private(set) var loaded = false
    private(set) var publishing = false
    var fetching = false
    var result: LRvdLindenStore.Banner?
    var toast: String?
    /// Concept van vóór een wijziging elders ("De site is intussen ergens anders bijgewerkt").
    var otherDraft: JSON?

    var dirty: Bool { data != original || !pending.isEmpty }

    // MARK: schema (SCHEMA in beheer.html)

    enum FieldType: Equatable {
        case text, textarea, bool, lines, tags, url, paras
        case image(max: CGFloat, round: Bool)
    }

    struct Field: Identifiable {
        let key: String
        let label: String
        let type: FieldType
        var hint: String? = nil
        var id: String { key }
    }

    struct Group: Identifiable {
        let title: String
        let path: String
        let fields: [Field]
        var sub: String? = nil
        var id: String { title }
    }

    struct ListSchema {
        let key: String
        let label: String
        let path: String
        let fields: [Field]
        let needsID: Bool
        var image: String? = nil
        var round = false
        var star: String? = nil
        let title: (JSON) -> String
        let subtitle: (JSON) -> String
        let create: () -> JSON
    }

    static let general: [Group] = [
        Group(title: String(localized: "Contact & bedrijf"), path: "settings", fields: [
            Field(key: "email", label: String(localized: "E-mailadres"), type: .text, hint: String(localized: "Contactformulier wordt naar dit adres gestuurd")),
            Field(key: "phone", label: String(localized: "Telefoon"), type: .text, hint: String(localized: "Leeg = niet tonen")),
            Field(key: "city", label: String(localized: "Plaats"), type: .text),
            Field(key: "kvk", label: String(localized: "KvK-nummer"), type: .text, hint: String(localized: "Leeg = niet tonen")),
            Field(key: "facebook", label: "Facebook", type: .url),
            Field(key: "instagram", label: "Instagram", type: .url),
            Field(key: "linkedin", label: "LinkedIn", type: .url),
            Field(key: "termsUrl", label: String(localized: "Algemene voorwaarden (link)"), type: .url, hint: String(localized: "Bijv. een PDF. Leeg = niet tonen")),
        ]),
        Group(title: String(localized: "Cijfers"), path: "settings", fields: [
            Field(key: "rating", label: String(localized: "Beoordeling"), type: .text),
            Field(key: "satisfaction", label: String(localized: "Tevreden klanten"), type: .text),
            Field(key: "deliveryTime", label: String(localized: "Gemiddelde levertijd"), type: .text),
            Field(key: "responseTime", label: String(localized: "Responstijd"), type: .text),
        ], sub: String(localized: "Het aantal projecten wordt automatisch geteld uit je portfolio.")),
        Group(title: String(localized: "Hero (bovenaan de site)"), path: "hero", fields: [
            Field(key: "eyebrow", label: String(localized: "Label boven de kop"), type: .text),
            Field(key: "title1", label: String(localized: "Kop regel 1 (wit)"), type: .text),
            Field(key: "title2", label: String(localized: "Kop regel 2 (lime)"), type: .text),
            Field(key: "text", label: String(localized: "Introtekst"), type: .textarea),
            Field(key: "ctaPrimary", label: String(localized: "Knop 1"), type: .text),
            Field(key: "ctaSecondary", label: String(localized: "Knop 2"), type: .text),
        ]),
        Group(title: String(localized: "Over ons"), path: "about", fields: [
            Field(key: "title", label: String(localized: "Kop"), type: .text),
            Field(key: "paragraphs", label: String(localized: "Tekst"), type: .paras, hint: String(localized: "Witregel = nieuwe alinea")),
        ]),
        Group(title: String(localized: "Cookies"), path: "settings", fields: [
            Field(key: "cookieyesId", label: String(localized: "CookieYes-ID"), type: .text,
                  hint: String(localized: "Alleen het ID uit je CookieYes-script (…/client_data/ID/script.js). Leeg = de eigen cookiemelding van de site.")),
        ]),
    ]

    static let lists: [ListSchema] = [
        ListSchema(key: "packages", label: String(localized: "Pakketten"), path: "packages", fields: [
            Field(key: "name", label: String(localized: "Naam"), type: .text),
            Field(key: "badge", label: String(localized: "Label"), type: .text, hint: String(localized: "Bijv. Populair of Verplicht")),
            Field(key: "prefix", label: String(localized: "Voor de prijs"), type: .text, hint: String(localized: "Bijv. va")),
            Field(key: "price", label: String(localized: "Prijs"), type: .text),
            Field(key: "suffix", label: String(localized: "Na de prijs"), type: .text, hint: String(localized: "Bijv. /maand")),
            Field(key: "note", label: String(localized: "Kleine tekst"), type: .text, hint: String(localized: "Bijv. excl. btw")),
            Field(key: "highlight", label: String(localized: "Uitlichten (lime rand en knop)"), type: .bool),
            Field(key: "description", label: String(localized: "Omschrijving"), type: .textarea),
            Field(key: "features", label: String(localized: "Wat zit erin"), type: .lines, hint: String(localized: "Eén per regel")),
        ], needsID: true,
        title: { $0["name"]?.str ?? "" },
        subtitle: { [$0["prefix"]?.str, $0["price"]?.str, $0["suffix"]?.str].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") },
        create: { .object([("id", .string("")), ("name", .string(String(localized: "Nieuw pakket"))), ("prefix", .string("va")),
                           ("price", .string("€")), ("suffix", .string("")), ("note", .string("excl. btw")), ("description", .string("")),
                           ("features", .array([])), ("badge", .string("")), ("highlight", .bool(false))]) }),
        ListSchema(key: "steps", label: String(localized: "Werkwijze"), path: "steps", fields: [
            Field(key: "title", label: String(localized: "Titel"), type: .text),
            Field(key: "text", label: String(localized: "Tekst"), type: .textarea),
        ], needsID: false,
        title: { $0["title"]?.str ?? "" }, subtitle: { $0["text"]?.str ?? "" },
        create: { .object([("title", .string(String(localized: "Nieuwe stap"))), ("text", .string(""))]) }),
        ListSchema(key: "projects", label: String(localized: "Portfolio"), path: "projects", fields: [
            Field(key: "name", label: String(localized: "Naam"), type: .text),
            Field(key: "url", label: String(localized: "Website"), type: .url),
            Field(key: "tags", label: String(localized: "Labels"), type: .tags, hint: String(localized: "Komma's ertussen, bijv. Website Pro, CRM. Labels worden filters op de site.")),
            Field(key: "featured", label: String(localized: "Uitgelicht (eerst getoond)"), type: .bool),
            Field(key: "description", label: String(localized: "Omschrijving"), type: .textarea),
            Field(key: "image", label: String(localized: "Afbeelding"), type: .image(max: 1200, round: false)),
        ], needsID: true, image: "image", star: "featured",
        title: { $0["name"]?.str ?? "" },
        subtitle: { ($0["tags"]?.items ?? []).compactMap(\.str).joined(separator: " · ") },
        create: { .object([("id", .string("")), ("name", .string(String(localized: "Nieuw project"))), ("url", .string("https://")),
                           ("image", .string("")), ("tags", .array([.string("Website")])), ("description", .string("")), ("featured", .bool(true))]) }),
        ListSchema(key: "reviews", label: String(localized: "Reviews"), path: "reviews", fields: [
            Field(key: "name", label: String(localized: "Naam"), type: .text),
            Field(key: "company", label: String(localized: "Bedrijf"), type: .text),
            Field(key: "url", label: String(localized: "Website"), type: .url),
            Field(key: "quote", label: String(localized: "Review"), type: .textarea),
            Field(key: "photo", label: String(localized: "Foto"), type: .image(max: 320, round: true)),
        ], needsID: true, image: "photo", round: true,
        title: { $0["name"]?.str ?? "" }, subtitle: { $0["company"]?.str ?? "" },
        create: { .object([("id", .string("")), ("quote", .string("")), ("name", .string(String(localized: "Nieuwe review"))),
                           ("company", .string("")), ("url", .string("")), ("photo", .string(""))]) }),
        ListSchema(key: "values", label: String(localized: "Waarden"), path: "about.values", fields: [
            Field(key: "title", label: String(localized: "Titel"), type: .text),
            Field(key: "text", label: String(localized: "Tekst"), type: .textarea),
        ], needsID: false,
        title: { $0["title"]?.str ?? "" }, subtitle: { $0["text"]?.str ?? "" },
        create: { .object([("title", .string(String(localized: "Nieuw"))), ("text", .string(""))]) }),
        ListSchema(key: "faq", label: String(localized: "Vragen"), path: "faq", fields: [
            Field(key: "q", label: String(localized: "Vraag"), type: .text),
            Field(key: "a", label: String(localized: "Antwoord"), type: .textarea),
        ], needsID: false,
        title: { $0["q"]?.str ?? "" }, subtitle: { $0["a"]?.str ?? "" },
        create: { .object([("q", .string(String(localized: "Nieuwe vraag?"))), ("a", .string(""))]) }),
    ]

    // MARK: laden

    func load() async {
        guard let client = account.client, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let server = try JSON.parse(try await client.request("GET", "content.json", beheerHeader: false))
            original = server
            data = server
            if let draft = DraftStore.load("pixelforges") {
                if draft.base == server, draft.data != server {
                    data = draft.data
                    pending = draft.files
                    toast = String(localized: "Je concept is teruggezet")
                } else if draft.base != server, draft.data != draft.base {
                    otherDraft = draft.data
                }
            }
            loaded = true
        } catch SiteClient.Failure.unauthorized {
            account.signOut()
        } catch {
            result = LRvdLindenStore.Banner(kind: .bad, text: String(localized: "content.json kon niet geladen worden.") + " " + error.localizedDescription)
        }
    }

    func useOtherDraft() {
        if let d = otherDraft { data = d }
        otherDraft = nil
    }

    private func save() {
        guard loaded else { return }
        if dirty { DraftStore.save("pixelforges", Draft(base: original, data: data, files: pending)) } else { DraftStore.clear("pixelforges") }
    }

    func discard() {
        data = original
        pending = [:]
        otherDraft = nil
        DraftStore.clear("pixelforges")
        toast = String(localized: "Server-versie geladen")
    }

    // MARK: lijsten

    func items(_ s: ListSchema) -> [JSON] { data.value(path: s.path)?.items ?? [] }

    func setItems(_ s: ListSchema, _ items: [JSON]) { data.set(path: s.path, .array(items)) }

    func update(_ s: ListSchema, _ index: Int, _ change: (inout JSON) -> Void) {
        var list = items(s)
        guard list.indices.contains(index) else { return }
        change(&list[index])
        setItems(s, list)
    }

    func updateGroup(_ path: String, _ change: (inout JSON) -> Void) {
        var obj = data.value(path: path) ?? .object([])
        change(&obj)
        data.set(path: path, obj)
    }

    static func slug(_ s: String) -> String {
        let folded = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let r = folded.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return r.isEmpty ? "item" : String(r.prefix(40))
    }

    static func uniqueID(_ items: [JSON], _ name: String) -> String {
        let b = slug(name)
        var id = b, n = 2
        while items.contains(where: { $0["id"]?.str == id }) { id = "\(b)-\(n)"; n += 1 }
        return id
    }

    @discardableResult
    func add(_ s: ListSchema) -> Int {
        var list = items(s)
        var n = s.create()
        if s.needsID { n["id"] = .string(Self.uniqueID(list, n["name"]?.str ?? "")) }
        list.append(n)
        setItems(s, list)
        return list.count - 1
    }

    func duplicate(_ s: ListSchema, _ i: Int) -> Int {
        var list = items(s)
        guard list.indices.contains(i) else { return i }
        var c = list[i]
        if s.needsID { c["id"] = .string(Self.uniqueID(list, (list[i]["name"]?.str ?? list[i]["id"]?.str ?? "") + "-kopie")) }
        list.insert(c, at: i + 1)
        setItems(s, list)
        return i + 1
    }

    func move(_ s: ListSchema, _ i: Int, by d: Int) -> Int {
        var list = items(s)
        let j = i + d
        guard list.indices.contains(i), list.indices.contains(j) else { return i }
        list.swapAt(i, j)
        setItems(s, list)
        return j
    }

    func remove(_ s: ListSchema, _ i: Int) {
        var list = items(s)
        guard list.indices.contains(i) else { return }
        for k in ["image", "photo"] { if let p = list[i][k]?.str { pending[p] = nil } }
        list.remove(at: i)
        setItems(s, list)
    }

    // MARK: afbeeldingen

    private static var stamp: String { String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) }

    func setImage(_ s: ListSchema, _ i: Int, key: String, image: UIImage, max: CGFloat) {
        guard let bin = ImageTools.fit(image, maxWidth: max) else { return }
        let item = items(s)[i]
        let path = "img/\(Self.slug(item["id"]?.str ?? item["name"]?.str ?? "afbeelding"))-\(Self.stamp).jpg"
        update(s, i) { obj in
            if let old = obj[key]?.str { pending[old] = nil }
            obj[key] = .string(path)
        }
        pending[path] = bin
        toast = String(localized: "Afbeelding klaargezet. Vergeet niet te publiceren.")
    }

    func clearImage(_ s: ListSchema, _ i: Int, key: String) {
        update(s, i) { obj in
            if let old = obj[key]?.str { pending[old] = nil }
            obj[key] = .string("")
        }
    }

    // MARK: website ophalen (fetch-meta.php)

    struct Meta {
        let url: String
        let name: String
        let description: String
        let image: UIImage?
        let imageError: String?
    }

    func fetchMeta(_ url: String) async throws -> Meta {
        guard let client = account.client else { throw SiteClient.Failure.unauthorized }
        let r = try await client.call("POST", "fetch-meta.php", body: ["url": url])
        var img: UIImage?
        var err = r["imageError"] as? String
        if let im = r["image"] as? [String: Any], let b64 = im["data"] as? String, let d = Data(base64Encoded: b64) {
            img = UIImage(data: d)
            if img == nil { err = String(format: String(localized: "Afbeeldingsformaat (%@) wordt niet ondersteund; upload er zelf een."), im["mime"] as? String ?? "?") }
        }
        return Meta(url: r["url"] as? String ?? url, name: r["name"] as? String ?? "", description: r["description"] as? String ?? "",
                    image: img, imageError: err)
    }

    static func host(_ u: String) -> String {
        let s = u.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil ? u : "https://" + u
        return URL(string: s)?.host?.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) ?? ""
    }

    /// "Nieuw project van een website": naam, omschrijving en afbeelding automatisch, bovenaan het portfolio.
    func addProject(from raw: String) async -> Int? {
        let s = Self.lists.first { $0.key == "projects" }!
        let host = Self.host(raw.trimmingCharacters(in: .whitespaces))
        guard host.contains(".") else { toast = String(localized: "Vul een website-adres in, bijv. klantwebsite.nl"); return nil }
        if let dupe = items(s).firstIndex(where: { Self.host($0["url"]?.str ?? "") == host }) {
            toast = String(format: String(localized: "%@ staat al in je portfolio"), host)
            return dupe
        }
        fetching = true
        defer { fetching = false }
        do {
            let m = try await fetchMeta(raw)
            let name = m.name.isEmpty ? host : m.name
            let item: JSON = .object([("id", .string(Self.uniqueID(items(s), name))), ("name", .string(name)), ("url", .string(m.url)),
                                      ("image", .string("")), ("tags", .array([.string("Website")])),
                                      ("description", .string(m.description)), ("featured", .bool(true))])
            setItems(s, [item] + items(s))
            if let img = m.image { setImage(s, 0, key: "image", image: img, max: 1200) }
            var notes: [String] = []
            if m.image == nil { notes.append(m.imageError ?? String(localized: "Geen afbeelding gevonden; upload er zelf een.")) }
            if m.description.isEmpty { notes.append(String(localized: "Geen omschrijving gevonden; vul die zelf in.")) }
            result = LRvdLindenStore.Banner(kind: notes.isEmpty ? .good : .warn,
                           text: String(format: String(localized: "%@ is toegevoegd bovenaan je portfolio. Controleer de labels en tekst en publiceer daarna."), name)
                               + (notes.isEmpty ? "" : "\n" + notes.joined(separator: "\n")))
            return 0
        } catch {
            result = LRvdLindenStore.Banner(kind: .bad, text: String(localized: "Ophalen mislukt.") + " " + error.localizedDescription)
            return nil
        }
    }

    /// "↻ Opnieuw ophalen" bij een project.
    func refetch(_ i: Int) async {
        let s = Self.lists.first { $0.key == "projects" }!
        let url = items(s)[i]["url"]?.str ?? ""
        guard url.range(of: #"^https?://[^/]+\.[a-z]{2,}"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            toast = String(localized: "Vul eerst een geldig website-adres in."); return
        }
        fetching = true
        defer { fetching = false }
        do {
            let m = try await fetchMeta(url)
            update(s, i) { p in
                if !m.description.isEmpty { p["description"] = .string(m.description) }
                let n = p["name"]?.str ?? ""
                if n.isEmpty || n == String(localized: "Nieuw project") { p["name"] = .string(m.name) }
            }
            if let img = m.image { setImage(s, i, key: "image", image: img, max: 1200) }
            toast = m.image != nil ? String(localized: "Omschrijving en afbeelding bijgewerkt")
                : String(localized: "Omschrijving bijgewerkt.") + " " + (m.imageError ?? "")
        } catch {
            toast = String(localized: "Ophalen mislukt.") + " " + error.localizedDescription
        }
    }

    // MARK: publiceren

    /// validate() in beheer.html: ontbrekende of dubbele id's herstellen, namen verplicht, e-mailadres geldig.
    func validate() -> [String] {
        var errs: [String] = []
        for s in Self.lists where s.needsID {
            var list = items(s)
            var seen = Set<String>()
            for i in list.indices {
                var id = list[i]["id"]?.str ?? ""
                if id.isEmpty { id = Self.uniqueID(list, list[i]["name"]?.str ?? "") }
                if seen.contains(id) { id = Self.uniqueID(list, id) }
                list[i]["id"] = .string(id)
                seen.insert(id)
                if (list[i]["name"]?.str ?? "").isEmpty { errs.append(String(format: String(localized: "%@ %lld heeft geen naam."), s.label, i + 1)) }
            }
            if list != items(s) { setItems(s, list) }
        }
        let email = data.text("settings.email")
        if !email.isEmpty, email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil {
            errs.append(String(localized: "Het e-mailadres onder Algemeen klopt niet."))
        }
        return errs
    }

    func publish(message: String) async {
        guard let client = account.client, dirty, !publishing else { return }
        publishing = true
        result = nil
        defer { publishing = false }
        let text = data.serialized()
        let used = pending.filter { text.contains("\"" + $0.key + "\"") }
        do {
            let res = try await client.publish(data: data, files: used.map { ($0.key, $0.value.base64EncodedString()) }, message: message)
            original = data
            pending = [:]
            DraftStore.clear("pixelforges")
            if (res["github"] as? Bool) == true {
                let c = res["commit"] as? String
                result = LRvdLindenStore.Banner(kind: .good, text: String(localized: "Live gezet") + (c.map { " " + String(format: String(localized: "en opgeslagen in GitHub (commit %@)"), $0) } ?? "") + ".")
            } else {
                result = LRvdLindenStore.Banner(kind: .warn, text: String(localized: "Live gezet.") + " " + (res["warning"] as? String ?? ""))
            }
            toast = String(localized: "Gepubliceerd")
        } catch {
            result = LRvdLindenStore.Banner(kind: .bad, text: String(localized: "Publiceren mislukt.") + " " + error.localizedDescription + "\n" + String(localized: "Je wijzigingen staan nog als concept op dit apparaat."))
        }
    }
}
