import SwiftUI

struct TekstenView: View {
    private let docs = [("privacy", "Privacyverklaring", "hand.raised"), ("cookies", "Cookies", "checkmark.shield"), ("terms", "Gebruiksvoorwaarden", "doc.plaintext"),
                        ("disclaimer", "Disclaimer", "exclamationmark.bubble"), ("hulp", "Hulp en veelgestelde vragen", "questionmark.circle")]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(docs, id: \.0) { d in
                        NavigationLink { TextEditView(name: d.0, label: d.1) } label: { Label(d.1, systemImage: d.2) }
                    }
                } footer: {
                    Text("Deze teksten staan in de app (Instellingen) en op de website. Wijzigingen zijn binnen 5 minuten overal zichtbaar, zonder nieuwe build.")
                }
                Section {
                    NavigationLink { ChangelogEditView() } label: { Label("Changelog", systemImage: "list.bullet.clipboard") }
                }
            }
            .navigationTitle("Teksten")
        }
    }
}

struct TextEditView: View {
    @Environment(Session.self) private var session
    let name: String
    let label: String
    @State private var doc = ContentDoc(title: nil, content: "")
    @State private var loaded = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Titel", text: Binding(get: { doc.title ?? "" }, set: { doc.title = $0 }))
                .font(.title3.bold())
                .textFieldStyle(.plain)
                .padding()
            Divider()
            TextEditor(text: $doc.content)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
        .background(Theme.cardBackground)
        .overlay { if !loaded { ProgressView() } }
        .navigationTitle(label)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Standaardtekst terugzetten", role: .destructive) { confirmReset = true }
                } label: { Label("Meer", systemImage: "ellipsis.circle") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Bewaar") { Task { await save() } }.disabled(busy || !loaded)
            }
        }
        .alert("Standaardtekst terugzetten?", isPresented: $confirmReset) {
            Button("Terugzetten", role: .destructive) { Task { await reset() } }
            Button("Annuleer", role: .cancel) {}
        }
        .task { await load() }
    }

    private func load() async {
        do {
            doc = try await session.call { try await BeheerAPI.shared.content(name, token: $0) }
            loaded = true
            message = doc.updated_at.map { "Laatst aangepast \(Fmt.relative($0)) · HTML is toegestaan" } ?? "HTML is toegestaan (<h2>, <p>, <ul>, <a> …)"
        } catch { message = error.localizedDescription }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await session.call { try await BeheerAPI.shared.saveContent(name, doc, token: $0) }
            message = "Bewaard. Binnen 5 minuten zichtbaar in de app en op de website."
        } catch { message = error.localizedDescription }
    }

    private func reset() async {
        do {
            try await session.call { try await BeheerAPI.shared.resetContent(name, token: $0) }
            await load()
            message = "Standaardtekst teruggezet."
        } catch { message = error.localizedDescription }
    }
}

struct ChangelogEditView: View {
    @Environment(Session.self) private var session
    @State private var entries: [ChangelogEntry] = []
    @State private var editing: ChangelogEntry?
    @State private var message: String?

    var body: some View {
        List {
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            ForEach(entries) { e in
                Button { editing = e } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(e.version) · \(e.title)").font(.callout.weight(.semibold))
                        Text(Fmt.parse(e.release_date)?.formatted(date: .long, time: .omitted) ?? e.release_date)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { idx in
                entries.remove(atOffsets: idx)
                Task { await save() }
            }
        }
        .navigationTitle("Changelog")
        .toolbar {
            ToolbarItem {
                Button {
                    editing = ChangelogEntry(id: UUID().uuidString, title: "", version: "1.0.0",
                                             release_date: ISO8601DateFormatter().string(from: .now), content: "<ul><li></li></ul>")
                } label: { Label("Nieuw", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { e in
            ChangelogEntryEditor(entry: e) { updated in
                if let i = entries.firstIndex(where: { $0.id == updated.id }) { entries[i] = updated } else { entries.insert(updated, at: 0) }
                Task { await save() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { entries = try await session.call { try await BeheerAPI.shared.changelog(token: $0) } }
        catch { message = error.localizedDescription }
    }

    private func save() async {
        do {
            try await session.call { try await BeheerAPI.shared.saveChangelog(entries, token: $0) }
            message = "Bewaard."
        } catch { message = error.localizedDescription }
    }
}

struct ChangelogEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: ChangelogEntry
    var onSave: (ChangelogEntry) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Versie", text: $entry.version)
                TextField("Titel", text: $entry.title)
                Section("Inhoud (HTML)") {
                    TextEditor(text: $entry.content)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Changelog")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { onSave(entry); dismiss() }.disabled(entry.title.isEmpty || entry.version.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }
}
