import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Beheeromgeving LRvdLinden: alles van site/beheer.html op lrvdlinden.app, native.
/// Apps (iOS & andere platformen / Homey), bewerken, iconen en banners, vertalen NL → EN, volgorde, verwijderen,
/// versiegeschiedenis, Publiceren, Nieuwe apps ophalen, Apps bijwerken, Logboek, Bestand openen, Kopieer/Download JSON
/// en Wijzigingen weggooien.
struct LRvdLindenRoot: View {
    @State private var store = LRvdLindenStore.shared

    var body: some View {
        Group {
            if store.account.isSignedIn {
                LRvdLindenMain(store: store)
            } else {
                SiteLoginView(title: "LRvdLinden beheer", site: "lrvdlinden.app/beheer", account: store.account,
                              onSignedIn: { Task { await store.load() } }) { LRLogo(size: 84) }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

enum LRCatalog {
    static let platforms = ["iPhone", "iPad", "Mac", "Apple TV", "Apple Watch", "Vision Pro", "Android", "Android TV",
                            "Samsung TV", "Windows", "Web"]
    static let categories: [(String, LocalizedStringKey)] = [
        ("utilities", "Hulpmiddelen"), ("entertainment", "Amusement"), ("news", "Nieuws"), ("business", "Zakelijk"),
        ("lifestyle", "Lifestyle"), ("games", "Games"), ("music", "Muziek"), ("productivity", "Productiviteit"),
        ("health", "Gezondheid"), ("education", "Onderwijs"), ("travel", "Reizen"), ("weather", "Weer"),
        ("sports", "Sport"), ("photo", "Foto en video"), ("navigation", "Navigatie"), ("finance", "Financiën"),
        ("reference", "Naslag"), ("social", "Sociaal"), ("food", "Eten en drinken"), ("books", "Boeken"),
        ("developer", "Ontwikkelaarstools"), ("design", "Grafisch en ontwerp"), ("shopping", "Winkelen"), ("kids", "Kinderen"),
    ]
    static let statuses: [(String, LocalizedStringKey)] = [("live", "Live"), ("beta", "Beta / TestFlight"), ("dev", "In ontwikkeling")]

    static func pill(_ status: String) -> StatusPill {
        switch status {
        case "live": StatusPill(text: "live", fg: Theme.good, bg: Theme.betaSoft)
        case "beta": StatusPill(text: "beta", fg: Theme.accent, bg: Brand.accentSoft)
        default: StatusPill(text: "dev", fg: Theme.build, bg: Theme.buildSoft)
        }
    }
}

struct LRvdLindenMain: View {
    @Bindable var store: LRvdLindenStore
    @State private var search = ""
    @State private var showLog = false
    @State private var showNew = false
    @State private var importing = false
    @State private var confirmDiscard = false
    @State private var confirmSignOut = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationSplitView {
            list
                .navigationTitle("Apps beheren")
                .toolbar { toolbar }
        } detail: {
            if let id = store.selection, store.app(id) != nil {
                LRAppEditor(store: store, id: id)
            } else {
                ContentUnavailableView("Kies een app", systemImage: "app.dashed",
                                       description: Text("Kies links een app om te bewerken, of maak een nieuwe aan."))
            }
        }
        .task { if !store.loaded { await store.load() } }
        .toast($store.toast)
        .sheet(isPresented: $showLog) { NavigationStack { LRLogView(store: store) } }
        .sheet(isPresented: $showNew) { NavigationStack { LRNewAppSheet(store: store) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            guard case let .success(url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do { try store.importFile(try Data(contentsOf: url)); store.toast = url.lastPathComponent + " " + String(localized: "geladen") }
            catch { store.toast = String(localized: "Dit bestand is geen geldige apps.json") }
        }
        .confirmationDialog("Alle niet-gepubliceerde wijzigingen weggooien?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Wijzigingen weggooien", role: .destructive) { store.discard() }
        }
        .confirmationDialog("Uitloggen bij lrvdlinden.app?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Uitloggen", role: .destructive) { store.account.signOut() }
        }
    }

    private var list: some View {
        List(selection: $store.selection) {
            if let r = store.result {
                ResultBanner(kind: r.kind, text: r.text) { store.result = nil }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                if r.runID != nil {
                    Button("Bekijk in logboek") { showLog = true }
                }
            }
            Section {
                PublishRow(dirty: store.dirty, publishing: store.publishing) { Task { await store.publish() } }
            }
            ForEach([("ios", LocalizedStringKey("iOS & andere platformen")), ("homey", LocalizedStringKey("Homey"))], id: \.0) { sec, label in
                let items = filtered.filter { ($0["section"]?.str ?? "ios") == sec }
                Section {
                    ForEach(items, id: \.idKey) { a in
                        LRAppRow(app: a, base: LRvdLindenStore.site, pending: store.pending)
                            .tag(a.idKey)
                    }
                } header: {
                    Text(label) + Text(verbatim: " · \(items.count)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Zoek een app")
        .refreshable { if !store.dirty { await store.load() } }
        .overlay {
            if !store.loaded && store.loading { ProgressView() }
        }
    }

    private var filtered: [JSON] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.apps }
        return store.apps.filter { ($0["name"]?.str ?? "").lowercased().contains(q) || $0.idKey.contains(q) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showNew = true } label: { Label("Nieuwe app", systemImage: "plus") }
                .disabled(store.fetchingMode != nil)
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Section("Stores") {
                    Button { Task { await store.fetchStores(mode: "nieuw") } } label: {
                        Label(store.fetchingMode == "nieuw" ? "Bezig…" : "Nieuwe apps ophalen", systemImage: "sparkle.magnifyingglass")
                    }
                    Button { Task { await store.fetchStores(mode: "bijwerken") } } label: {
                        Label(store.fetchingMode == "bijwerken" ? "Bezig…" : "Apps bijwerken", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { showLog = true } label: { Label("Logboek", systemImage: "list.bullet.rectangle") }
                }
                .disabled(store.fetchingMode != nil)
                Section("Bestand") {
                    Button { importing = true } label: { Label("Bestand openen", systemImage: "folder") }
                    Button {
                        UIPasteboard.general.string = store.data.prettyPrinted
                        store.toast = String(localized: "JSON gekopieerd")
                    } label: { Label("Kopieer JSON", systemImage: "doc.on.doc") }
                    ShareLink(item: JSONFile(name: "apps.json", text: store.data.prettyPrinted),
                              preview: SharePreview("apps.json")) { Label("Download apps.json", systemImage: "square.and.arrow.down") }
                }
                Section {
                    Button(role: .destructive) { confirmDiscard = true } label: { Label("Wijzigingen weggooien", systemImage: "trash") }
                    Link(destination: URL(string: "https://lrvdlinden.app/beheer")!) { Label("Beheer op het web", systemImage: "safari") }
                    Link(destination: URL(string: "https://github.com/LRvdLinden/app.lrvdlinden/actions")!) { Label("GitHub Actions", systemImage: "gearshape.2") }
                    Button(role: .destructive) { confirmSignOut = true } label: { Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right") }
                }
            } label: { Label("Meer", systemImage: "ellipsis.circle") }
        }
    }
}

/// Publiceren-knop met status ("Alles gepubliceerd" / "Niet-gepubliceerde wijzigingen" / "Bezig met publiceren…").
struct PublishRow: View {
    let dirty: Bool
    let publishing: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(publishing ? "Bezig met publiceren…" : dirty ? "Niet-gepubliceerde wijzigingen" : "Alles gepubliceerd")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(dirty && !publishing ? Theme.build : .secondary)
                Text("Direct live en opgeslagen in GitHub").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: action) {
                if publishing { ProgressView() } else { Text("Publiceren").bold() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!dirty || publishing)
        }
        .sensoryFeedback(.success, trigger: publishing == false && !dirty)
    }
}

struct LRAppRow: View {
    let app: JSON
    let base: URL
    let pending: [String: Data]

    var body: some View {
        HStack(spacing: 12) {
            SiteImage(path: app["icon"]?.str ?? "", base: base, pending: pending)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app["name"]?.str ?? String(localized: "(naamloos)")).font(.body.weight(.semibold)).lineLimit(1)
                    if app["featured"]?.boolValue == true && (app["section"]?.str ?? "ios") == "ios" {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.star)
                            .accessibilityLabel("Staat in Nieuw en onderweg")
                    }
                    if app["nlOnly"]?.boolValue == true {
                        Text(verbatim: "NL").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            .accessibilityLabel("Alleen op de Nederlandse versie")
                    }
                }
                Text(app["category"]?.str ?? app["bundleId"]?.str ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            LRCatalog.pill(app["status"]?.str ?? "dev")
        }
    }
}

extension JSON {
    var idKey: String { self["id"]?.str ?? "" }

    /// Leesbaar (2 spaties), zoals JSON.stringify(DATA, null, 2) in beheer.html.
    var prettyPrinted: String {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(serialized().utf8), options: [.fragmentsAllowed]),
              let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes]) else {
            return serialized()
        }
        return String(decoding: d, as: UTF8.self) + "\n"
    }
}

/// Bestand voor ShareLink (Download apps.json / content.json).
struct JSONFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { f in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
            try Data(f.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - editor

struct LRAppEditor: View {
    @Bindable var store: LRvdLindenStore
    let id: String

    @State private var iconItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var bannerLang = "nl"
    @State private var overwrite = false
    @State private var confirmDelete = false
    @State private var newPlatform = ""

    private var app: JSON { store.app(id) ?? .object([]) }

    private func text(_ path: String) -> Binding<String> {
        Binding(get: { app.text(path) }, set: { v in store.update(id) { $0.setText(path, v) } })
    }

    private func number(_ path: String) -> Binding<String> {
        Binding(get: { app.text(path) }, set: { v in
            let t = v.replacingOccurrences(of: ",", with: ".")
            store.update(id) { $0.set(path: path, t.isEmpty ? nil : (Double(t) != nil ? .number(t) : .string(v))) }
        })
    }

    var body: some View {
        Form {
            basics
            texts
            promo
            links
            storeData
            history
            order
            Section {
                DisclosureGroup("Bekijk JSON van deze app") {
                    Text(app.prettyPrinted).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(app["name"]?.str ?? String(localized: "Nieuwe app"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await store.publish() } } label: {
                    if store.publishing { ProgressView() } else { Text("Publiceren").bold() }
                }
                .disabled(!store.dirty || store.publishing)
            }
        }
        .onChange(of: iconItem) { _, item in load(item) { store.setIcon(id, image: $0) } }
        .onChange(of: bannerItem) { _, item in load(item) { store.setBanner(id, lang: bannerLang, image: $0) } }
        .toast($store.toast)
    }

    private func load(_ item: PhotosPickerItem?, then: @escaping (UIImage) -> Void) {
        guard let item else { return }
        Task {
            if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { then(img) }
            else { store.toast = String(localized: "Dit bestand is geen afbeelding") }
            iconItem = nil
            bannerItem = nil
        }
    }

    // MARK: secties

    @ViewBuilder private var basics: some View {
        Section {
            TextField("Naam", text: text("name"))
            LabeledContent("ID (uniek, zonder spaties)") {
                TextField("id", text: Binding(get: { id }, set: { store.rename(id, to: $0) }))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            }
            Picker("Sectie", selection: Binding(get: { app["section"]?.str ?? "ios" },
                                                set: { v in store.update(id) { $0["section"] = .string(v) } })) {
                Text("iOS & andere platformen").tag("ios")
                Text("Homey").tag("homey")
            }
            Picker("Categorie", selection: Binding(get: { app["category"]?.str ?? "" },
                                                   set: { v in store.update(id) { $0["category"] = .string(v) } })) {
                if !LRCatalog.categories.contains(where: { $0.0 == app["category"]?.str ?? "" }) {
                    Text(verbatim: app["category"]?.str ?? "–").tag(app["category"]?.str ?? "")
                }
                ForEach(LRCatalog.categories, id: \.0) { Text($0.1).tag($0.0) }
            }
            Picker("Status", selection: Binding(get: { app["status"]?.str ?? "dev" },
                                                set: { v in store.update(id) { $0["status"] = .string(v) } })) {
                ForEach(LRCatalog.statuses, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            Toggle("Tonen in Nieuw en onderweg", isOn: Binding(get: { app["featured"]?.boolValue == true },
                                                               set: { v in store.update(id) { $0["featured"] = v ? .bool(true) : nil } }))
            Toggle(isOn: Binding(get: { app["nlOnly"]?.boolValue == true },
                                 set: { v in store.update(id) { $0["nlOnly"] = v ? .bool(true) : nil } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alleen Nederlands")
                    Text("Niet tonen op de Engelse versie van de site").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                SiteImage(path: app["icon"]?.str ?? "", base: LRvdLindenStore.site, pending: store.pending)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading) {
                    TextField("Icoon (pad)", text: text("icon"), prompt: Text(verbatim: "img/mijnapp.webp"))
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))
                    PhotosPicker(selection: $iconItem, matching: .images) { Label("Icoon uploaden", systemImage: "photo") }
                }
            }
        } header: { Text(app["name"]?.str ?? "") }
        Section("Platformen / apparaten") { platforms }
    }

    @ViewBuilder private var platforms: some View {
        let current = app["platforms"]?.items.compactMap(\.str) ?? []
        let all = LRCatalog.platforms + current.filter { !LRCatalog.platforms.contains($0) }
        VStack(alignment: .leading, spacing: 10) {
            FlowChips(items: all, selected: Set(current)) { p in
                store.update(id) { a in
                    var list = a["platforms"]?.items.compactMap(\.str) ?? []
                    if let i = list.firstIndex(of: p) { list.remove(at: i) } else { list.append(p) }
                    a["platforms"] = .array(list.map(JSON.string))
                }
            }
            HStack {
                TextField("Ander apparaat, bijv. LG TV", text: $newPlatform).textFieldStyle(.roundedBorder)
                Button("Toevoegen") {
                    let v = newPlatform.trimmingCharacters(in: .whitespaces)
                    guard !v.isEmpty else { return }
                    store.update(id) { a in
                        var list = a["platforms"]?.items.compactMap(\.str) ?? []
                        if !list.contains(v) { list.append(v) }
                        a["platforms"] = .array(list.map(JSON.string))
                    }
                    newPlatform = ""
                }
            }
        }
    }

    private var texts: some View {
        Section {
            Toggle("Ook bestaande Engelse teksten overschrijven", isOn: $overwrite)
            Button { Task { await store.translate(id, overwrite: overwrite) } } label: {
                Label(store.translating ? "Bezig met vertalen…" : "Vertaal NL → EN", systemImage: "character.bubble")
            }
            .disabled(store.translating)
            TextField("Ondertitel NL", text: text("subtitle.nl"))
            TextField("Subtitle EN", text: text("subtitle.en"))
            TextField("Omschrijving NL", text: text("description.nl"), axis: .vertical).lineLimit(3...10)
            TextField("Description EN", text: text("description.en"), axis: .vertical).lineLimit(3...10)
            TextField("Label NL (optioneel)", text: text("badge.nl"), prompt: Text(verbatim: "Nr. 26 in Nieuws"))
            TextField("Badge EN (optional)", text: text("badge.en"), prompt: Text(verbatim: "No. 26 in News"))
        } header: { Text("Teksten") } footer: {
            Text("Vertaalt ondertitel, omschrijving, label, banner en versie-notities van deze app. Lege Nederlandse velden worden vanuit het Engels ingevuld.")
        }
    }

    private var promo: some View {
        Section {
            Toggle("Toon een grote banner voor deze app, zoals in de App Store",
                   isOn: Binding(get: { app.value(path: "promo.show")?.boolValue == true },
                                 set: { v in store.update(id) { $0.set(path: "promo.show", v ? .bool(true) : nil) } }))
            ForEach(["nl", "en"], id: \.self) { lg in
                let im = LRvdLindenStore.banner(app, lg)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: lg.uppercased()).font(.caption.bold())
                    if !im.isEmpty {
                        SiteImage(path: im, base: LRvdLindenStore.site, pending: store.pending)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Text(lg == "en" && !LRvdLindenStore.banner(app, "nl").isEmpty ? "Geen Engelse banner: de Nederlandse wordt gebruikt"
                             : lg == "nl" && !LRvdLindenStore.banner(app, "en").isEmpty ? "Geen Nederlandse banner: de Engelse wordt gebruikt"
                             : "Geen afbeelding: de banner gebruikt het icoon als achtergrond")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        PhotosPicker(selection: Binding(get: { bannerItem }, set: { bannerLang = lg; bannerItem = $0 }), matching: .images) {
                            Label(String(format: String(localized: "Banner %@ uploaden"), lg.uppercased()), systemImage: "photo.on.rectangle")
                        }
                        Spacer()
                        if !im.isEmpty {
                            Button("Verwijderen", role: .destructive) { store.removeBanner(id, lang: lg) }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            TextField("Bovenregel NL", text: text("promo.eyebrow.nl"), prompt: Text(verbatim: "NIEUWE APP"))
            TextField("Eyebrow EN", text: text("promo.eyebrow.en"), prompt: Text(verbatim: "NEW APP"))
            TextField("Titel NL", text: text("promo.title.nl"), prompt: Text(verbatim: "Al je tv op één plek"))
            TextField("Title EN", text: text("promo.title.en"), prompt: Text(verbatim: "All your TV in one place"))
            TextField("Tekst NL", text: text("promo.text.nl"), axis: .vertical)
            TextField("Text EN", text: text("promo.text.en"), axis: .vertical)
        } header: { Text("Promo-banner (Nieuw en onderweg)") } footer: {
            Text("Liggend beeld, ideaal 1600 × 900 pixels. Upload per taal een eigen banner, of één voor beide. Laat de titel leeg om de appnaam te tonen.")
        }
    }

    private var links: some View {
        Section("Links") {
            urlField("App Store", "links.appstore", "https://apps.apple.com/…")
            urlField("TestFlight", "links.testflight", "https://testflight.apple.com/join/…")
            urlField("Website", "links.website", "https://…")
            urlField("Homey App Store", "links.homey", "https://homey.app/nl-nl/app/…")
            TextField("Bundle ID (Homey)", text: text("bundleId"), prompt: Text(verbatim: "nl.lrvdlinden.…"))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private func urlField(_ label: LocalizedStringKey, _ path: String, _ ph: String) -> some View {
        LabeledContent(label) {
            TextField(label, text: text(path), prompt: Text(verbatim: ph))
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        }
    }

    private var storeData: some View {
        Section("App Store-gegevens") {
            LabeledContent("Beoordeling") { TextField("4.8", text: number("rating")).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            LabeledContent("Aantal reviews") { TextField("0", text: number("reviews")).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            LabeledContent("Grootte") { TextField("14,8 MB", text: text("size")).multilineTextAlignment(.trailing) }
            LabeledContent("Talen") { TextField("NL + 10", text: text("languages")).multilineTextAlignment(.trailing) }
        }
    }

    private var history: some View {
        Section("Versiegeschiedenis") {
            Button {
                store.update(id) { a in
                    let item: JSON = .object([("version", .string("")), ("date", .string(Self.today)),
                                              ("notes", .object([("nl", .string("")), ("en", .string(""))]))])
                    a["history"] = .array([item] + (a["history"]?.items ?? []))
                }
            } label: { Label("Nieuwe versie bovenaan", systemImage: "plus") }
            ForEach(Array((app["history"]?.items ?? []).enumerated()), id: \.offset) { i, _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Versie", text: historyText(i, "version"), prompt: Text(verbatim: "1.0.0")).frame(maxWidth: 110)
                        TextField("Datum", text: historyText(i, "date"), prompt: Text(verbatim: "2026-01-31"))
                        Button(role: .destructive) {
                            store.update(id) { a in
                                var h = a["history"]?.items ?? []
                                if h.indices.contains(i) { h.remove(at: i) }
                                a["history"] = .array(h)
                            }
                        } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Versie verwijderen")
                    }
                    TextField("Wat is nieuw (NL)", text: historyText(i, "notes.nl"), axis: .vertical)
                    TextField("What's new (EN)", text: historyText(i, "notes.en"), axis: .vertical)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func historyText(_ i: Int, _ path: String) -> Binding<String> {
        Binding(get: { LRvdLindenStore.historyAware(app, "history.\(i).\(path)")?.str ?? "" },
                set: { v in store.update(id) { a in
                    var h = a["history"]?.items ?? []
                    guard h.indices.contains(i) else { return }
                    h[i].set(path: path, .string(v))
                    a["history"] = .array(h)
                } })
    }

    private var order: some View {
        Section {
            Button { store.move(id, by: -1) } label: { Label("Hoger", systemImage: "arrow.up") }
            Button { store.move(id, by: 1) } label: { Label("Lager", systemImage: "arrow.down") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Verwijder app", systemImage: "trash") }
                .confirmationDialog(String(format: String(localized: "%@ echt verwijderen?"), app["name"]?.str ?? ""),
                                    isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Verwijderen", role: .destructive) { store.delete(id) }
                }
        }
    }

    static var today: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}

/// Aan/uit-knopjes die doorlopen over meerdere regels (platformen, zoals de vinkjes in beheer.html).
struct FlowChips: View {
    let items: [String]
    let selected: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { p in
                let on = selected.contains(p)
                Button { toggle(p) } label: {
                    // HStack i.p.v. Label: in een Form-rij krijgt een Label de lijst-opmaak en valt de tekst weg.
                    // fixedSize: de pil breekt nooit af, FlowLayout zet hem op een nieuwe regel als hij niet past.
                    HStack(spacing: 5) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .imageScale(.small)
                        Text(verbatim: p)
                            .lineLimit(1)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(on ? Theme.accent : Theme.ink)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(on ? Brand.accentSoft : Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? Theme.accent.opacity(0.5) : Theme.line))
                    .fixedSize()
                    .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(verbatim: p))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing
            row = max(row, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            row = max(row, sz.height)
        }
    }
}

// MARK: - logboek

struct LRLogView: View {
    @Bindable var store: LRvdLindenStore
    @State private var filter = "all"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Picker("Filter", selection: $filter) {
                Text("Alles").tag("all")
                Text("Met wijzigingen").tag("changed")
                Text("Apps bijwerken").tag("bijwerken")
                Text("Nieuwe apps").tag("nieuw")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            if let e = store.logError {
                ResultBanner(kind: .bad, text: String(localized: "Logboek laden mislukt.") + " " + e) { store.logError = nil }
            }
            ForEach(groupedDays, id: \.0) { day, runs in
                Section(day) {
                    ForEach(runs) { r in RunRow(run: r) }
                }
            }
            if store.log != nil && rows.isEmpty {
                ContentUnavailableView("Nog geen runs", systemImage: "tray",
                                       description: Text("De volgende check (automatisch rond 07:00 en 17:00, of via Nieuwe apps ophalen / Apps bijwerken) verschijnt hier."))
            }
        }
        .navigationTitle("Logboek")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if store.log == nil && store.logError == nil { ProgressView() } }
        .refreshable { await store.loadLog() }
        .task { await store.loadLog() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Sluiten") { dismiss() } }
        }
    }

    struct Row: Identifiable {
        let id: String
        let date: Date?
        let title: LocalizedStringKey
        let who: LocalizedStringKey
        let pending: Bool
        let running: Bool
        let changed: Bool
        let lines: [String]
        let checked: [StoreLog.Checked]
        let url: URL?
    }

    private var rows: [Row] {
        guard let log = store.log else { return [] }
        let iso = ISO8601DateFormatter()
        func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) } }
        let modeLabel: [String: LocalizedStringKey] = ["bijwerken": "Apps bijwerken", "nieuw": "Nieuwe apps ophalen", "alles": "Automatische check",
                                                       "toevoegen": "App toevoegen"]
        var all: [Row] = log.active.map { a in
            Row(id: a.id, date: date(a.time), title: a.trigger == "schedule" ? "Automatische check" : "Store-check",
                who: a.trigger == "schedule" ? "automatisch" : "handmatig", pending: true, running: a.state == "running",
                changed: false, lines: [], checked: [], url: a.url.flatMap(URL.init(string:)))
        }
        all += log.runs.map { r in
            Row(id: r.id, date: date(r.time), title: modeLabel[r.mode ?? ""] ?? "Store-check",
                who: r.trigger == "schedule" ? "automatisch" : "handmatig", pending: false, running: false,
                changed: r.changed == true, lines: r.lines ?? [], checked: r.checked ?? [], url: r.url.flatMap(URL.init(string:)))
        }
        let modes = Dictionary(log.runs.map { ($0.id, $0.mode ?? "") }, uniquingKeysWith: { x, _ in x })
        return all.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.filter { r in
            switch filter {
            case "changed": return r.changed
            case "nieuw": return modes[r.id] == "nieuw"
            case "bijwerken": return ["bijwerken", "alles"].contains(modes[r.id] ?? "")
            default: return true
            }
        }
    }

    private var groupedDays: [(String, [Row])] {
        var out: [(String, [Row])] = []
        for r in rows {
            let day = r.date?.formatted(.dateTime.weekday(.wide).day().month(.wide).year()) ?? ""
            if out.last?.0 == day { out[out.count - 1].1.append(r) } else { out.append((day, [r])) }
        }
        return out
    }

    struct RunRow: View {
        let run: Row

        var body: some View {
            DisclosureGroup {
                if run.pending {
                    Text(run.running ? "Deze run is nog bezig. Vernieuw straks." : "Deze run is mislukt; er is niets gewijzigd.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if run.lines.isEmpty && run.checked.isEmpty {
                    Text("Niets gevonden om te controleren.").font(.footnote).foregroundStyle(.secondary)
                }
                if !run.lines.isEmpty {
                    Text("Wat er veranderde").font(.footnote.bold())
                    ForEach(run.lines, id: \.self) { Text("• " + $0).font(.footnote) }
                }
                if !run.checked.isEmpty {
                    Text(String(format: String(localized: "Gecontroleerd (%lld)"), run.checked.count)).font(.footnote.bold())
                    ForEach(run.checked, id: \.self) { c in
                        HStack {
                            Text(c.app ?? "").font(.footnote.weight(c.changed == true ? .semibold : .regular))
                            Spacer()
                            Text(c.store ?? "").font(.caption).foregroundStyle(.secondary)
                            Text(c.version ?? "–").font(.caption.monospaced())
                            if let t = c.test { Text(verbatim: "test \(t)").font(.caption2).foregroundStyle(Theme.build) }
                            if c.changed == true { Image(systemName: "arrow.up.circle.fill").foregroundStyle(Theme.good).font(.caption) }
                        }
                    }
                }
                if let u = run.url { Link("Bekijk op GitHub", destination: u).font(.footnote) }
            } label: {
                HStack {
                    Text(run.date?.formatted(date: .omitted, time: .shortened) ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(run.title).font(.subheadline.weight(.semibold))
                        Text(run.who).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if run.pending {
                        StatusPill(text: run.running ? "Bezig" : "Mislukt", fg: run.running ? Theme.build : Theme.bad,
                                   bg: run.running ? Theme.buildSoft : Theme.bad.opacity(0.12))
                    } else if run.changed {
                        let n = max(run.lines.count, run.checked.filter { $0.changed == true }.count)
                        StatusPill(text: "\(n) \(n == 1 ? String(localized: "wijziging") : String(localized: "wijzigingen"))", fg: Theme.good, bg: Theme.betaSoft)
                    } else {
                        StatusPill(text: "Geen wijzigingen", fg: .secondary, bg: Theme.line.opacity(0.5))
                    }
                }
            }
        }
    }
}

/// Nieuwe app: handmatig (leeg formulier) of automatisch vanaf een App Store-, Homey-, TestFlight- of website-link.
/// Zelfde werking als de knop "+ Nieuwe app" in site/beheer.html (store-refresh.php?mode=toevoegen&url=…).
struct LRNewAppSheet: View {
    @Bindable var store: LRvdLindenStore
    @Environment(\.dismiss) private var dismiss
    @State private var how = "appstore"
    @State private var url = ""
    @State private var problem: LocalizedStringKey?

    private var placeholder: String {
        switch how {
        case "appstore": "https://apps.apple.com/nl/app/…/id123456789"
        case "homey": "https://homey.app/nl-nl/app/nl.lrvdlinden.…/"
        default: "https://… of https://testflight.apple.com/join/…"
        }
    }
    private var hint: LocalizedStringKey {
        switch how {
        case "appstore": "Naam, icoon, categorie, platformen, versies, beoordelingen en teksten in NL en EN worden automatisch opgehaald. Dit duurt 1 tot 2 minuten."
        case "homey": "Naam, icoon, apparaten, widgets, Flow-kaarten, versies en teksten in NL en EN worden automatisch opgehaald. Dit duurt 1 tot 2 minuten."
        case "web": "Naam, icoon en omschrijving komen van de pagina. Staat er een App Store- of Homey-link op, dan wordt die app volledig opgehaald. Een TestFlight-link wordt een beta-app. Dit duurt 1 tot 2 minuten."
        default: "Je krijgt een leeg formulier en vult alles zelf in."
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Hoe wil je de app toevoegen?", selection: $how) {
                    Label("App Store", systemImage: "app.badge").tag("appstore")
                    Label("Homey App Store", systemImage: "house").tag("homey")
                    Label("Website of TestFlight", systemImage: "safari").tag("web")
                    Label("Handmatig", systemImage: "square.and.pencil").tag("manual")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text("Hoe wil je de app toevoegen?") }
            if how != "manual" {
                Section {
                    TextField("Link", text: $url, prompt: Text(verbatim: placeholder))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(go)
                    if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.bad) }
                } header: { Text("Link") } footer: { Text(hint) }
            } else {
                Section { } footer: { Text(hint) }
            }
        }
        .navigationTitle("Nieuwe app toevoegen")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: how) { problem = nil }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(how == "manual" ? "Leeg formulier" : "Ophalen en toevoegen", action: go)
                    .disabled(how != "manual" && url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func go() {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        switch how {
        case "manual":
            store.newApp()
            dismiss()
            return
        case "appstore" where u.range(of: #"apps\.apple\.com/.*id\d+|^(id)?\d{6,12}$"#, options: .regularExpression) == nil:
            problem = "Dit lijkt geen App Store-link."
            return
        case "homey" where u.range(of: #"homey\.app/[a-z-]+/app/|^[a-z0-9]+(\.[a-z0-9_-]+){2,}$"#, options: .regularExpression) == nil:
            problem = "Dit lijkt geen Homey App Store-link."
            return
        default:
            guard !u.isEmpty, u.count <= 500, u.rangeOfCharacter(from: CharacterSet(charactersIn: " <>\"'")) == nil else {
                problem = "Vul een geldige link in."
                return
            }
        }
        dismiss()
        Task { await store.fetchStores(mode: "toevoegen", url: u) }
    }
}
