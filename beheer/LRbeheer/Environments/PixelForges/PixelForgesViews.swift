import PhotosUI
import SwiftUI

/// Beheeromgeving PixelForges: alles van site/beheer.html op pixelforges.nl, native.
/// Tabs Algemeen, Pakketten, Werkwijze, Portfolio (met "Nieuw project van een website"), Reviews, Waarden en Vragen;
/// toevoegen, dupliceren, volgorde, verwijderen, afbeeldingen, Publiceren, Download content.json en Server-versie laden.
struct PixelForgesRoot: View {
    @State private var store = PixelForgesStore.shared

    var body: some View {
        Group {
            if store.account.isSignedIn {
                PixelForgesMain(store: store)
            } else {
                SiteLoginView(title: "PixelForges beheer", site: "pixelforges.nl/beheer", account: store.account,
                              onSignedIn: { Task { await store.load() } }) { EnvironmentIcon(env: .pixelforges, size: 84) }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct PixelForgesMain: View {
    @Bindable var store: PixelForgesStore
    @State private var publishMessage = "Bijgewerkt via beheer"
    @State private var askMessage = false
    @State private var errors: [String] = []
    @State private var confirmReset = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if store.otherDraft != nil {
                    Section {
                        Text("De site is intussen ergens anders bijgewerkt. Je eerdere concept staat apart.").font(.subheadline)
                        Button("Toch mijn concept gebruiken") { store.useOtherDraft() }
                        Button("Concept weggooien", role: .destructive) { store.otherDraft = nil }
                    }
                }
                if let r = store.result {
                    ResultBanner(kind: r.kind, text: r.text) { store.result = nil }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                if !errors.isEmpty {
                    ResultBanner(kind: .bad, text: errors.joined(separator: "\n")) { errors = [] }
                        .listRowBackground(Color.clear)
                }
                Section {
                    PublishRow(dirty: store.dirty, publishing: store.publishing) { startPublish() }
                }
                Section("Inhoud") {
                    NavigationLink { PFGeneralView(store: store) } label: {
                        Label("Algemeen", systemImage: "slider.horizontal.3")
                    }
                    ForEach(PixelForgesStore.lists, id: \.key) { s in
                        NavigationLink { PFListView(store: store, schema: s) } label: {
                            HStack {
                                Label(s.label, systemImage: icon(s.key))
                                Spacer()
                                Text(verbatim: "\(store.items(s).count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    ShareLink(item: JSONFile(name: "content.json", text: store.data.prettyPrinted), preview: SharePreview("content.json")) {
                        Label("Download content.json", systemImage: "square.and.arrow.down")
                    }
                    Button { confirmReset = true } label: { Label("Server-versie laden", systemImage: "arrow.uturn.backward") }
                    Link(destination: URL(string: "https://pixelforges.nl")!) { Label("Bekijk de site", systemImage: "safari") }
                    Link(destination: URL(string: "https://pixelforges.nl/beheer.html")!) { Label("Beheer op het web", systemImage: "globe") }
                    Button(role: .destructive) { confirmSignOut = true } label: { Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right") }
                }
            }
            .navigationTitle("PixelForges")
            .refreshable { if !store.dirty { await store.load() } }
            .overlay { if !store.loaded && store.loading { ProgressView() } }
        }
        .task { if !store.loaded { await store.load() } }
        .toast($store.toast)
        .alert("Korte omschrijving van de wijziging (komt in GitHub)", isPresented: $askMessage) {
            TextField("Bijgewerkt via beheer", text: $publishMessage)
            Button("Annuleren", role: .cancel) {}
            Button("Publiceren") { Task { await store.publish(message: publishMessage) } }
        }
        .confirmationDialog("Alle niet-gepubliceerde wijzigingen weggooien?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Server-versie laden", role: .destructive) { store.discard() }
        }
        .confirmationDialog("Uitloggen bij pixelforges.nl?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Uitloggen", role: .destructive) { store.account.signOut() }
        }
    }

    private func startPublish() {
        errors = store.validate()
        guard errors.isEmpty else { return }
        publishMessage = String(localized: "Bijgewerkt via beheer")
        askMessage = true
    }

    private func icon(_ key: String) -> String {
        switch key {
        case "packages": "shippingbox"
        case "steps": "list.number"
        case "projects": "square.grid.2x2"
        case "reviews": "quote.bubble"
        case "values": "heart"
        default: "questionmark.circle"
        }
    }
}

/// Tab Algemeen: contact, cijfers, hero, over ons en cookies.
struct PFGeneralView: View {
    @Bindable var store: PixelForgesStore

    var body: some View {
        Form {
            ForEach(PixelForgesStore.general) { g in
                Section {
                    ForEach(g.fields) { f in
                        PFFieldEditor(field: f, value: store.data.value(path: g.path)?[f.key]) { v in
                            store.updateGroup(g.path) { $0[f.key] = v }
                        }
                    }
                } header: { Text(g.title) } footer: { if let s = g.sub { Text(s) } }
            }
        }
        .navigationTitle("Algemeen")
        .navigationBarTitleDisplayMode(.inline)
        .toast($store.toast)
    }
}

/// Een lijst (pakketten, portfolio, ...): items, toevoegen en per item de editor.
struct PFListView: View {
    @Bindable var store: PixelForgesStore
    let schema: PixelForgesStore.ListSchema
    @State private var fetchURL = ""
    @State private var openIndex: Int?
    @State private var search = ""

    var body: some View {
        List {
            if schema.key == "projects" {
                Section {
                    HStack {
                        TextField("https://klantwebsite.nl", text: $fetchURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit(fetch)
                        Button(action: fetch) { if store.fetching { ProgressView() } else { Text("Ophalen").bold() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.fetching || fetchURL.isEmpty)
                    }
                } header: { Text("Nieuw project van een website") } footer: {
                    Text("Vult naam, omschrijving en afbeelding automatisch in.")
                }
            }
            if let r = store.result, schema.key == "projects" {
                ResultBanner(kind: r.kind, text: r.text) { store.result = nil }.listRowBackground(Color.clear)
            }
            Section {
                let items = store.items(schema)
                if items.isEmpty {
                    Text("Nog niets toegevoegd").foregroundStyle(.secondary)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { i, x in
                    if matches(x) {
                        NavigationLink(value: i) { PFItemRow(schema: schema, item: x, index: i, pending: store.pending) }
                    }
                }
                .onMove { from, to in
                    var list = store.items(schema)
                    list.move(fromOffsets: from, toOffset: to)
                    store.setItems(schema, list)
                }
            } header: { Text(verbatim: "\(schema.label) · \(store.items(schema).count)") }
        }
        .navigationTitle(schema.label)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .navigationDestination(for: Int.self) { i in PFItemEditor(store: store, schema: schema, index: i) }
        .navigationDestination(item: $openIndex) { i in PFItemEditor(store: store, schema: schema, index: i) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { openIndex = store.add(schema) } label: { Label("Nieuw", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) { EditButton() }
        }
        .toast($store.toast)
    }

    private func matches(_ x: JSON) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || schema.title(x).lowercased().contains(q) || schema.subtitle(x).lowercased().contains(q)
    }

    private func fetch() {
        let raw = fetchURL
        Task {
            if let i = await store.addProject(from: raw) {
                fetchURL = ""
                openIndex = i
            }
        }
    }
}

struct PFItemRow: View {
    let schema: PixelForgesStore.ListSchema
    let item: JSON
    let index: Int
    let pending: [String: Data]

    var body: some View {
        HStack(spacing: 12) {
            if let k = schema.image {
                SiteImage(path: item[k]?.str ?? "", base: PixelForgesStore.site, pending: pending)
                    .frame(width: 44, height: 44)
                    .clipShape(schema.round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
            } else {
                Text(verbatim: "\(index + 1)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(schema.title(item).isEmpty ? String(localized: "(zonder naam)") : schema.title(item)).font(.body.weight(.semibold)).lineLimit(1)
                Text(schema.subtitle(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let star = schema.star, item[star]?.boolValue == true {
                Image(systemName: "star.fill").foregroundStyle(Theme.star).font(.caption)
            }
        }
    }
}

struct PFItemEditor: View {
    @Bindable var store: PixelForgesStore
    let schema: PixelForgesStore.ListSchema
    @State var index: Int
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = store.items(schema)
        if items.indices.contains(index) {
            let item = items[index]
            Form {
                Section {
                    ForEach(schema.fields) { f in
                        if case let .image(max, round) = f.type {
                            PFImageField(store: store, schema: schema, index: index, field: f, max: max, round: round, value: item[f.key]?.str ?? "")
                        } else {
                            PFFieldEditor(field: f, value: item[f.key]) { v in store.update(schema, index) { $0[f.key] = v } }
                        }
                    }
                } header: {
                    Text(schema.needsID ? "ID: \(item["id"]?.str ?? "")" : String(format: String(localized: "Positie %lld van %lld"), index + 1, items.count))
                        .textCase(nil)
                }
                Section {
                    if schema.key == "projects" {
                        Button { Task { await store.refetch(index) } } label: {
                            Label(store.fetching ? "Ophalen…" : "Opnieuw ophalen", systemImage: "arrow.clockwise")
                        }
                        .disabled(store.fetching)
                    }
                    Button { index = store.move(schema, index, by: -1) } label: { Label("Omhoog", systemImage: "arrow.up") }
                        .disabled(index == 0)
                    Button { index = store.move(schema, index, by: 1) } label: { Label("Omlaag", systemImage: "arrow.down") }
                        .disabled(index == items.count - 1)
                    Button { index = store.duplicate(schema, index) } label: { Label("Dupliceren", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Verwijderen", systemImage: "trash") }
                }
            }
            .navigationTitle(schema.title(item).isEmpty ? String(localized: "(zonder naam)") : schema.title(item))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(String(format: String(localized: "\"%@\" verwijderen?"), schema.title(item)), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Verwijderen", role: .destructive) { store.remove(schema, index); dismiss() }
            }
            .toast($store.toast)
        } else {
            ContentUnavailableView("Kies een item", systemImage: "square.dashed", description: Text("Kies een item of voeg er een toe."))
        }
    }
}

/// Eén veld volgens het schema van beheer.html (text, textarea, bool, lines, tags, url, paras).
struct PFFieldEditor: View {
    let field: PixelForgesStore.Field
    let value: JSON?
    let set: (JSON) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch field.type {
            case .bool:
                Toggle(field.label, isOn: Binding(get: { value?.boolValue == true }, set: { set(.bool($0)) }))
            case .textarea:
                caption
                TextField(field.label, text: Binding(get: { value?.str ?? "" }, set: { set(.string($0.trimmingCharacters(in: .whitespaces))) }), axis: .vertical)
                    .lineLimit(3...12)
            case .lines:
                caption
                TextField(field.label, text: Binding(get: { (value?.items ?? []).compactMap(\.str).joined(separator: "\n") },
                                                     set: { set(.array($0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(JSON.string))) }),
                          axis: .vertical)
                    .lineLimit(3...12)
            case .paras:
                caption
                TextField(field.label, text: Binding(get: { (value?.items ?? []).compactMap(\.str).joined(separator: "\n\n") },
                                                     set: { raw in
                                                         let paras = raw.components(separatedBy: "\n\n").map {
                                                             $0.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
                                                                 .trimmingCharacters(in: .whitespacesAndNewlines)
                                                         }.filter { !$0.isEmpty }
                                                         set(.array(paras.map(JSON.string)))
                                                     }), axis: .vertical)
                    .lineLimit(4...20)
            case .tags:
                caption
                TextField(field.label, text: Binding(get: { (value?.items ?? []).compactMap(\.str).joined(separator: ", ") },
                                                     set: { set(.array($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(JSON.string))) }))
            case .url:
                caption
                TextField("https://", text: Binding(get: { value?.str ?? "" }, set: { set(.string($0.trimmingCharacters(in: .whitespaces))) }))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            case .text, .image:
                caption
                TextField(field.label, text: Binding(get: { value?.str ?? "" }, set: { set(.string($0.trimmingCharacters(in: .whitespaces))) }))
            }
        }
    }

    @ViewBuilder private var caption: some View {
        HStack(spacing: 4) {
            Text(field.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let h = field.hint { Text(verbatim: "· \(h)").font(.caption).foregroundStyle(.tertiary) }
        }
    }
}

struct PFImageField: View {
    @Bindable var store: PixelForgesStore
    let schema: PixelForgesStore.ListSchema
    let index: Int
    let field: PixelForgesStore.Field
    let max: CGFloat
    let round: Bool
    let value: String
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(field.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                SiteImage(path: value, base: PixelForgesStore.site, pending: store.pending)
                    .frame(width: round ? 72 : 120, height: 72)
                    .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                VStack(alignment: .leading, spacing: 8) {
                    TextField("img/naam.webp of https://…", text: Binding(get: { value }, set: { v in
                        store.update(schema, index) { $0[field.key] = .string(v.trimmingCharacters(in: .whitespaces)) }
                    }))
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        PhotosPicker(selection: $item, matching: .images) { Label("Upload afbeelding", systemImage: "photo") }
                        if !value.isEmpty {
                            Button("Verwijder", role: .destructive) { store.clearImage(schema, index, key: field.key) }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text("Wordt automatisch verkleind. Een https-link wordt bij de volgende deploy naar de eigen server gekopieerd.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    store.setImage(schema, index, key: field.key, image: img, max: max)
                } else {
                    store.toast = String(localized: "Kon afbeelding niet lezen")
                }
                item = nil
            }
        }
    }
}
