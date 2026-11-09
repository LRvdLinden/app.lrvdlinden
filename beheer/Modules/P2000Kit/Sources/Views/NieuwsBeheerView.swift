import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// Tab Nieuws of A-Alerts: police news, weather articles and liveblogs. Here the beheer hides items, sets an own image,
// adds messages (text, photo, link) to the timeline and chooses the stock images for police news.
// Same functions as the web-beheer (#nieuws). Photos of politie.nl may never be used.

struct AdminNieuws: Decodable, Identifiable, Hashable {
    let id: String
    let soort: String
    let bron: String
    let titel: String
    let plaats: String?
    let at: String
    let status: String?
    let afbeelding: String?
    let link: String?
    let aantal: Int?
    let hidden: Bool?

    var soortNaam: String { NieuwsStijl.soort(soort) }
    var isKindAfgerond: Bool { (bron == "amber" || bron == "vermistkind") && status == "afgerond" }
}

struct AdminNieuwsDetail: Decodable {
    struct Bericht: Decodable, Identifiable, Hashable {
        let serverId: Int?
        let at: String
        let door: String
        let titel: String?
        let tekst: String
        let foto: String?
        let url: String?
        var id: String { "\(serverId.map(String.init) ?? "b")-\(at)-\(tekst.hashValue)" }
        var isEigen: Bool { door == "a-alerts" }
        enum CodingKeys: String, CodingKey { case serverId = "id", at, door, titel, tekst, foto, url }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            serverId = try? c.decodeIfPresent(Int.self, forKey: .serverId)
            at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? ""
            door = (try? c.decodeIfPresent(String.self, forKey: .door)) ?? ""
            titel = try? c.decodeIfPresent(String.self, forKey: .titel)
            tekst = (try? c.decodeIfPresent(String.self, forKey: .tekst)) ?? ""
            foto = try? c.decodeIfPresent(String.self, forKey: .foto)
            url = try? c.decodeIfPresent(String.self, forKey: .url)
        }
    }
    let item: AdminNieuws
    let tijdlijn: [Bericht]
    let ontvangers: Int?

    enum CodingKeys: String, CodingKey { case tijdlijn, ontvangers }
    init(from d: Decoder) throws {
        item = try AdminNieuws(from: d)
        let c = try d.container(keyedBy: CodingKeys.self)
        tijdlijn = (try? c.decodeIfPresent([Bericht].self, forKey: .tijdlijn)) ?? []
        ontvangers = try? c.decodeIfPresent(Int.self, forKey: .ontvangers)
    }
}

struct AdminStock: Decodable, Identifiable {
    let categorie: String
    let eigen: Bool
    let afbeelding: String
    var id: String { categorie }
}

enum NieuwsStijl {
    static func soort(_ s: String) -> String {
        switch s { case "liveblog": "Liveblog"; case "weer": "Weer"; case "regionaal": "112 Nieuws"; default: "Politie" }
    }
    static func bron(_ b: String) -> String {
        switch b {
        case "burgernet": "Burgernet"
        case "amber": "AMBER Alert"
        case "vermistkind": "Vermist Kind"
        case "knmi": "KNMI"
        case "112nieuws": "112 Nieuws"
        default: "Politie"
        }
    }
    static func categorie(_ c: String) -> String {
        ["algemeen": "Algemeen", "verkeer": "Verkeer", "inbraak": "Inbraak", "getuigen": "Getuigen gezocht", "drugs": "Drugs", "brand": "Brand", "vermist": "Vermist"][c] ?? c
    }

    /// Photo → JPEG data URL of at most 1600 px (the server takes up to 1.8 MB).
    static func dataURL(_ data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 1600]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        for q in [0.82, 0.7, 0.55, 0.4] {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            if out.length < 1_700_000 { return "data:image/jpeg;base64," + (out as Data).base64EncodedString() }
        }
        return nil
    }
}

/// JSON body where a missing value is left out and `.some(nil)` is sent as null (remove the photo).
private struct NieuwsBody: Encodable {
    var waarden: [String: Encodable?] = [:]
    struct Key: CodingKey { var stringValue: String; var intValue: Int? { nil }; init(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { nil } }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (k, v) in waarden {
            if let v { try c.encode(NieuwsAnyEncodable(v), forKey: Key(stringValue: k)) } else { try c.encodeNil(forKey: Key(stringValue: k)) }
        }
    }
}

private struct NieuwsAnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

extension BeheerAPI {
    func nieuws(soort: String?, token: String) async throws -> [AdminNieuws] {
        var q = ["limit": "100"]
        if let soort { q["soort"] = soort }
        return try await getJSON("v1/beheer/nieuws", query: q, token: token)
    }
    func nieuwsItem(_ id: String, token: String) async throws -> AdminNieuwsDetail {
        try await getJSON("v1/beheer/nieuws/\(id)", token: token)
    }
    func wijzigNieuws(_ id: String, hidden: Bool? = nil, foto: String?? = .none, token: String) async throws -> AdminNieuwsDetail {
        var b = NieuwsBody()
        if let hidden { b.waarden["hidden"] = hidden }
        if case .some(let f) = foto { b.waarden.updateValue(f.map { $0 as Encodable }, forKey: "foto") }
        return try await sendJSON("PATCH", "v1/beheer/nieuws/\(id)", body: b, token: token)
    }
    func voegToe(_ id: String, titel: String, tekst: String, url: String, foto: String?, push: Bool, token: String) async throws -> AdminNieuwsDetail {
        var b = NieuwsBody()
        b.waarden = ["titel": titel, "tekst": tekst, "url": url, "push": push]
        if let foto { b.waarden["foto"] = foto }
        return try await sendJSON("POST", "v1/beheer/nieuws/\(id)/updates", body: b, token: token)
    }
    func wijzigBericht(_ id: String, _ uid: Int, tekst: String, url: String, token: String) async throws -> AdminNieuwsDetail {
        try await sendJSON("PATCH", "v1/beheer/nieuws/\(id)/updates/\(uid)", body: ["tekst": tekst, "url": url], token: token)
    }
    func verwijderBericht(_ id: String, _ uid: Int, token: String) async throws -> AdminNieuwsDetail {
        try await sendJSON("DELETE", "v1/beheer/nieuws/\(id)/updates/\(uid)", body: [String: String](), token: token)
    }
    func stock(token: String) async throws -> [AdminStock] { try await getJSON("v1/beheer/nieuws/stock", token: token) }
    func zetStock(_ categorie: String, foto: String?, token: String) async throws -> [AdminStock] {
        var b = NieuwsBody()
        b.waarden.updateValue(foto.map { $0 as Encodable }, forKey: categorie)
        return try await sendJSON("PUT", "v1/beheer/nieuws/stock", body: b, token: token)
    }
}

// MARK: - List

struct NieuwsBeheerView: View {
    @Environment(Session.self) private var session
    @State private var items: [AdminNieuws] = []
    @State private var soort: String?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(text: error).listRowBackground(Color.clear) }
                Section {
                    Picker("Soort", selection: $soort) {
                        Text("Alles").tag(String?.none)
                        ForEach(["liveblog", "politie", "regionaal", "weer"], id: \.self) { Text(NieuwsStijl.soort($0)).tag(Optional($0)) }
                    }
                    NavigationLink { StockBeheerView() } label: { Label("Standaardafbeeldingen politie", systemImage: "photo.on.rectangle") }
                }
                Section {
                    if items.isEmpty && !loading { Text("Nog geen nieuws.").foregroundStyle(.secondary) }
                    ForEach(items) { x in
                        NavigationLink { NieuwsBeheerDetail(id: x.id) } label: { rij(x) }
                    }
                } footer: {
                    Text("Politieberichten komen van politie.nl (tekst met bronvermelding, nooit hun foto's). Liveblogs volgen Burgernet, AMBER Alert en Vermist Kind Alert; vul ze aan met tekst, foto en link. Na afloop van een kind-alert worden foto's en teksten van het kind automatisch weggehaald.")
                }
            }
            .navigationTitle("Nieuws")
            .toolbar { ToolbarItem { Button { Task { await load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") } } }
            .refreshable { await load() }
            .task(id: soort ?? "") { await load() }
        }
    }

    private func rij(_ x: AdminNieuws) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: x.afbeelding.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                .frame(width: 84, height: 54).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(x.soortNaam) · \(x.soort == "politie" || x.soort == "regionaal" ? (x.plaats ?? "") : NieuwsStijl.bron(x.bron))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(x.titel).font(.callout.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(Fmt.relative(x.at))
                    if x.soort == "liveblog" { Text(x.status == "afgerond" ? "· afgerond" : "· loopt") }
                    if let n = x.aantal, n > 0 { Text("· \(n) berichten") }
                    if x.hidden == true { Label("Verborgen", systemImage: "eye.slash").foregroundStyle(.orange) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .opacity(x.hidden == true ? 0.55 : 1)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await session.call { try await BeheerAPI.shared.nieuws(soort: soort, token: $0) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Item

struct NieuwsBeheerDetail: View {
    @Environment(Session.self) private var session
    let id: String
    @State private var detail: AdminNieuwsDetail?
    @State private var error: String?
    @State private var melding: String?
    @State private var busy = false
    @State private var eigenFoto: PhotosPickerItem?
    // New message
    @State private var kop = ""
    @State private var tekst = ""
    @State private var link = ""
    @State private var fotoItem: PhotosPickerItem?
    @State private var fotoData: String?
    @State private var push = true
    @State private var bewerk: AdminNieuwsDetail.Bericht?

    var body: some View {
        Form {
            if let error { ErrorBanner(text: error) }
            if let melding { Text(melding).foregroundStyle(.green) }
            if let d = detail {
                let x = d.item
                Section {
                    AsyncImage(url: x.afbeelding.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                        .frame(height: 170).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(x.titel).font(.headline)
                    LabeledContent("Soort", value: "\(x.soortNaam) · \(NieuwsStijl.bron(x.bron))")
                    if let p = x.plaats { LabeledContent("Plaats", value: p) }
                    LabeledContent("Datum", value: Fmt.parse(x.at).map(Fmt.dateTime) ?? x.at)
                    if let l = x.link, let url = URL(string: l) { Link("Bekijk op a-alerts.nl", destination: url) }
                }
                Section {
                    Toggle("Verbergen in de apps en op de website", isOn: Binding(get: { x.hidden == true }, set: { v in Task { await wijzig(hidden: v) } }))
                    if !x.isKindAfgerond {
                        PhotosPicker(selection: $eigenFoto, matching: .images) { Label("Eigen afbeelding kiezen", systemImage: "photo") }
                    }
                    Button("Eigen afbeelding weghalen", role: .destructive) { Task { await wijzig(foto: .some(nil)) } }
                } footer: {
                    Text(x.isKindAfgerond ? "Deze kind-alert is afgelopen: er kan geen foto meer bij." : "Een eigen afbeelding vervangt de standaardafbeelding van A-Alerts.")
                }
                Section {
                    TextField("Kop (optioneel)", text: $kop)
                    TextField("Tekst", text: $tekst, axis: .vertical).lineLimit(3...10)
                    TextField("Link (https://, optioneel)", text: $link)
                        #if os(iOS)
                        .keyboardType(.URL).textInputAutocapitalization(.never)
                        #endif
                    if !x.isKindAfgerond {
                        PhotosPicker(selection: $fotoItem, matching: .images) {
                            Label(fotoData == nil ? "Foto toevoegen (optioneel)" : "Foto gekozen", systemImage: fotoData == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                        }
                    }
                    Toggle(x.soort == "regionaal" ? "Pushmelding (wie 112 Nieuws aan heeft)" : x.soort == "politie" ? "Pushmelding (wie Politienieuws aan heeft)" : "Pushmelding (wie Liveblogs aan heeft en deze bron volgt)", isOn: $push)
                    Button { Task { await voegToe() } } label: { Label("Toevoegen aan tijdlijn", systemImage: "plus.circle.fill") }
                        .disabled(busy || (tekst.trimmingCharacters(in: .whitespaces).isEmpty && fotoData == nil && link.isEmpty))
                } header: { Text("Bericht toevoegen") }
                Section {
                    if d.tijdlijn.isEmpty { Text("Nog geen berichten.").foregroundStyle(.secondary) }
                    ForEach(d.tijdlijn) { b in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Fmt.parse(b.at).map(Fmt.dateTime) ?? b.at).font(.caption).foregroundStyle(.secondary)
                                Text(b.isEigen ? "A-Alerts" : NieuwsStijl.bron(b.door)).font(.caption.bold()).foregroundStyle(b.isEigen ? .red : .secondary)
                            }
                            if let t = b.titel, !t.isEmpty { Text(t).font(.callout.bold()) }
                            if !b.tekst.isEmpty { Text(b.tekst).font(.callout) }
                            if let f = b.foto, let url = URL(string: f) {
                                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.secondary.opacity(0.15).frame(height: 80) }
                                    .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            if let u = b.url, let url = URL(string: u) { Link(u, destination: url).font(.caption) }
                        }
                        .swipeActions {
                            if b.isEigen, let uid = b.serverId {
                                Button("Verwijder", role: .destructive) { Task { await verwijder(uid) } }
                                Button("Wijzig") { bewerk = b }.tint(.blue)
                            }
                        }
                        .contextMenu {
                            if b.isEigen, let uid = b.serverId {
                                Button("Wijzig") { bewerk = b }
                                Button("Verwijder", role: .destructive) { Task { await verwijder(uid) } }
                            }
                        }
                    }
                } header: { Text("Tijdlijn (nieuwste boven)") } footer: { Text("Eigen berichten wijzig of verwijder je met vegen of lang drukken.") }
            } else if error == nil {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(detail?.item.soortNaam ?? "Nieuws")
        .disabled(busy)
        .task { await laad() }
        .onChange(of: eigenFoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let url = NieuwsStijl.dataURL(data) { await wijzig(foto: .some(url)) }
                else { error = "Kan deze foto niet lezen" }
                eigenFoto = nil
            }
        }
        .onChange(of: fotoItem) { _, item in
            guard let item else { fotoData = nil; return }
            Task { fotoData = (try? await item.loadTransferable(type: Data.self)).flatMap(NieuwsStijl.dataURL) }
        }
        .sheet(item: $bewerk) { b in BerichtBewerken(bericht: b) { t, u in Task { await wijzigBericht(b, t, u) } } }
    }

    private func laad() async {
        do { detail = try await session.call { try await BeheerAPI.shared.nieuwsItem(id, token: $0) }; error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func wijzig(hidden: Bool? = nil, foto: String?? = .none) async {
        busy = true; defer { busy = false }
        do { detail = try await session.call { try await BeheerAPI.shared.wijzigNieuws(id, hidden: hidden, foto: foto, token: $0) }; error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func voegToe() async {
        busy = true; defer { busy = false }
        do {
            let (k, t, l, f, p) = (kop, tekst, link, fotoData, push)
            let r = try await session.call { try await BeheerAPI.shared.voegToe(id, titel: k, tekst: t, url: l, foto: f, push: p, token: $0) }
            detail = r
            melding = push ? "Toegevoegd · push naar \(r.ontvangers ?? 0) toestel(len)" : "Toegevoegd"
            kop = ""; tekst = ""; link = ""; fotoItem = nil; fotoData = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func verwijder(_ uid: Int) async {
        busy = true; defer { busy = false }
        do { detail = try await session.call { try await BeheerAPI.shared.verwijderBericht(id, uid, token: $0) }; error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func wijzigBericht(_ b: AdminNieuwsDetail.Bericht, _ tekst: String, _ url: String) async {
        guard let uid = b.serverId else { return }
        busy = true; defer { busy = false }
        do { detail = try await session.call { try await BeheerAPI.shared.wijzigBericht(id, uid, tekst: tekst, url: url, token: $0) }; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct BerichtBewerken: View {
    let bericht: AdminNieuwsDetail.Bericht
    var bewaar: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tekst = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tekst", text: $tekst, axis: .vertical).lineLimit(3...12)
                TextField("Link (https://)", text: $url)
            }
            .formStyle(.grouped)
            .navigationTitle("Bericht wijzigen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Bewaar") { bewaar(tekst, url); dismiss() } }
            }
            .onAppear { tekst = bericht.tekst; url = bericht.url ?? "" }
        }
    }
}

// MARK: - Stock images

struct StockBeheerView: View {
    @Environment(Session.self) private var session
    @State private var lijst: [AdminStock] = []
    @State private var error: String?
    @State private var kies: [String: PhotosPickerItem] = [:]

    var body: some View {
        List {
            if let error { ErrorBanner(text: error).listRowBackground(Color.clear) }
            Section {
                ForEach(lijst) { s in
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: s.afbeelding)) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                            .frame(width: 110, height: 62).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(NieuwsStijl.categorie(s.categorie)).font(.callout.weight(.semibold))
                            HStack {
                                PhotosPicker(selection: Binding(get: { kies[s.categorie] }, set: { kies[s.categorie] = $0; if let item = $0 { gekozen(s.categorie, item) } }), matching: .images) {
                                    Text("Kies foto")
                                }
                                if s.eigen { Button("Standaard", role: .destructive) { Task { await zet(s.categorie, nil) } } }
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            } footer: {
                Text("Elk politiebericht krijgt de afbeelding van zijn onderwerp. Foto's van politie.nl mogen niet gebruikt worden; kies eigen foto's of stockfoto's met een vrije licentie.")
            }
        }
        .navigationTitle("Standaardafbeeldingen")
        .task { await laad() }
    }

    private func gekozen(_ cat: String, _ item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let url = NieuwsStijl.dataURL(data) { await zet(cat, url) }
            else { error = "Kan deze foto niet lezen" }
            kies[cat] = nil
        }
    }

    private func laad() async {
        do { lijst = try await session.call { try await BeheerAPI.shared.stock(token: $0) }; error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func zet(_ cat: String, _ foto: String?) async {
        do { lijst = try await session.call { try await BeheerAPI.shared.zetStock(cat, foto: foto, token: $0) }; error = nil }
        catch { self.error = error.localizedDescription }
    }
}
