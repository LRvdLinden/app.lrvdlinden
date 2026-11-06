import SwiftUI

struct MeldingenView: View {
    @Environment(Session.self) private var session
    @State private var items: [AdminMelding] = []
    @State private var search = ""
    @State private var onlyHidden = false
    @State private var error: String?
    @State private var loading = false
    @State private var selected: AdminMelding?

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(text: error).listRowBackground(Color.clear) }
                ForEach(items) { m in
                    Button { selected = m } label: { MeldingRow(m: m) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(m.isHidden ? "Tonen" : "Verberg", systemImage: m.isHidden ? "eye" : "eye.slash") {
                                Task { await toggleHidden(m) }
                            }
                            .tint(m.isHidden ? .green : .orange)
                        }
                        .contextMenu {
                            Button(m.isHidden ? "Weer tonen" : "Verbergen", systemImage: m.isHidden ? "eye" : "eye.slash") { Task { await toggleHidden(m) } }
                            Button("Bewerken", systemImage: "pencil") { selected = m }
                        }
                }
                if items.isEmpty && !loading {
                    Text(onlyHidden ? "Geen verborgen meldingen" : "Geen meldingen gevonden")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
            .overlay { if loading && items.isEmpty { ProgressView() } }
            .navigationTitle("Meldingen")
            .searchable(text: $search, prompt: "Zoek op titel, plaats, straat of capcode")
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: search) { _, value in if value.isEmpty { Task { await load() } } }
            .toolbar {
                ToolbarItem {
                    Toggle(isOn: $onlyHidden) { Label("Alleen verborgen", systemImage: "eye.slash") }
                        .toggleStyle(.button)
                }
                ToolbarItem {
                    Button { Task { await load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") }
                }
            }
            .onChange(of: onlyHidden) { _, _ in Task { await load() } }
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $selected) { m in
                MeldingEditView(melding: m) { updated in
                    if let i = items.firstIndex(where: { $0.guid == updated.guid }) { items[i] = updated }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await session.call { try await BeheerAPI.shared.meldingen(query: search, onlyHidden: onlyHidden, token: $0) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleHidden(_ m: AdminMelding) async {
        do {
            let updated = try await session.call {
                try await BeheerAPI.shared.update(m.guid, .init(hidden: !m.isHidden), token: $0)
            }
            if let i = items.firstIndex(where: { $0.guid == m.guid }) { items[i] = updated }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MeldingRow: View {
    let m: AdminMelding
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Dienst.symbol(m.dienst))
                .font(.title3)
                .foregroundStyle(Dienst.color(m.dienst))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Fmt.dateTime(m.date)) · \(m.stad ?? "")").font(.caption).foregroundStyle(.secondary)
                Text(m.title).font(.callout.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    if let p = m.prioriteit { Text(p).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1).background(Theme.red.opacity(0.15), in: Capsule()) }
                    if let c = m.categorie { Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if m.isHidden { Label("Verborgen", systemImage: "eye.slash").font(.caption2.bold()).foregroundStyle(.orange) }
                if m.edited == true && !m.isHidden { Label("Aangepast", systemImage: "pencil").font(.caption2).foregroundStyle(.blue) }
                if let v = m.views, v > 0 { Label("\(v)", systemImage: "eye").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 4)
        .opacity(m.isHidden ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

struct MeldingEditView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let melding: AdminMelding
    var onSave: (AdminMelding) -> Void

    @State private var title = ""
    @State private var categorie = ""
    @State private var locatie = ""
    @State private var lat = ""
    @State private var lon = ""
    @State private var hidden = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Tijd", value: Fmt.dateTime(melding.date))
                    LabeledContent("Discipline", value: Dienst.label(melding.dienst))
                    if let p = melding.prioriteit { LabeledContent("Prioriteit", value: p) }
                    if let s = melding.stad { LabeledContent("Plaats", value: s) }
                    if let c = melding.capcode { LabeledContent("Capcode", value: c) }
                    if let f = melding.full_melding { Text(f).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Section("Zichtbaarheid") {
                    Toggle("Verbergen in de app en op de website", isOn: $hidden)
                }
                Section("Corrigeren") {
                    TextField("Titel", text: $title, axis: .vertical)
                    TextField("Categorie", text: $categorie)
                    TextField("Straat / locatie", text: $locatie)
                    HStack {
                        TextField("Breedtegraad", text: $lat)
                        TextField("Lengtegraad", text: $lon)
                    }
                    .font(.callout.monospacedDigit())
                }
                if melding.edited == true {
                    Section {
                        Button("Alle aanpassingen terugdraaien", role: .destructive) { Task { await save(reset: true) } }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Melding")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { Task { await save(reset: false) } }.disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                title = melding.title
                categorie = melding.categorie ?? ""
                locatie = melding.locatie ?? ""
                lat = melding.lat.map { String(format: "%.5f", $0) } ?? ""
                lon = melding.lon.map { String(format: "%.5f", $0) } ?? ""
                hidden = melding.isHidden
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private func save(reset: Bool) async {
        busy = true
        defer { busy = false }
        var change = BeheerAPI.MeldingUpdate()
        if reset {
            change.reset = true
        } else {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let c = categorie.trimmingCharacters(in: .whitespaces)
            let l = locatie.trimmingCharacters(in: .whitespaces)
            let la = Double(lat.replacingOccurrences(of: ",", with: "."))
            let lo = Double(lon.replacingOccurrences(of: ",", with: "."))
            if hidden != melding.isHidden { change.hidden = hidden }
            if t != melding.title { change.title = t }
            if c != (melding.categorie ?? "") { change.categorie = c }
            if l != (melding.locatie ?? "") { change.locatie = l }
            if let la, abs(la - (melding.lat ?? 0)) > 0.000001 { change.lat = la }
            if let lo, abs(lo - (melding.lon ?? 0)) > 0.000001 { change.lon = lo }
            if change.hidden == nil && change.title == nil && change.categorie == nil && change.locatie == nil
                && change.lat == nil && change.lon == nil {
                dismiss()
                return
            }
        }
        do {
            let updated = try await session.call { try await BeheerAPI.shared.update(melding.guid, change, token: $0) }
            onSave(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
