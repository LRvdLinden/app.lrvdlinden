import SwiftUI

struct PushView: View {
    @Environment(Session.self) private var session
    @State private var title = "P2000 Apeldoorn"
    @State private var message = ""
    @State private var plaatsen: Set<String> = []
    @State private var history: [BroadcastItem] = []
    @State private var confirm = false
    @State private var busy = false
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $title)
                    TextField("Bericht", text: $message, axis: .vertical).lineLimit(3...8)
                } header: {
                    Text("Bericht")
                } footer: {
                    Text("Wordt als echte pushmelding verstuurd naar iedereen die pushmeldingen aan heeft. Binnen een minuut verstuurd.")
                }
                Section {
                    NavigationLink {
                        PlaatsPicker(selection: $plaatsen)
                    } label: {
                        LabeledContent("Ontvangers", value: plaatsen.isEmpty ? "Iedereen" : plaatsen.sorted().joined(separator: ", "))
                    }
                } footer: {
                    Text("Kies plaatsen om alleen gebruikers te bereiken die meldingen voor die plaatsen krijgen. Gebruikers zonder plaatsfilter krijgen het bericht altijd.")
                }
                Section {
                    Button {
                        confirm = true
                    } label: {
                        HStack {
                            if busy { ProgressView() }
                            Label("Verstuur pushmelding", systemImage: "paperplane.fill").fontWeight(.semibold)
                        }
                    }
                    .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty || message.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let result { Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section("Eerder verstuurd") {
                    if history.isEmpty {
                        Text("Nog niets verstuurd").foregroundStyle(.secondary)
                    }
                    ForEach(history) { b in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(b.title).font(.callout.weight(.semibold))
                                Spacer()
                                Text(Fmt.relative(b.at)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(b.body).font(.callout).foregroundStyle(.secondary)
                            Text("\((b.plaatsen ?? []).isEmpty ? "Iedereen" : (b.plaatsen ?? []).joined(separator: ", ")) · \(b.ontvangers ?? 0) toestellen")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Push")
            .task { await loadHistory() }
            .refreshable { await loadHistory() }
            .confirmationDialog("Pushmelding versturen?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Verstuur naar \(plaatsen.isEmpty ? "iedereen" : "\(plaatsen.count) plaats(en)")") { Task { await send() } }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text("\(title)\n\(message)")
            }
        }
    }

    private func loadHistory() async {
        history = (try? await session.call { try await BeheerAPI.shared.broadcastHistory(token: $0) }) ?? history
    }

    private func send() async {
        busy = true
        defer { busy = false }
        result = nil
        error = nil
        do {
            let req = BeheerAPI.BroadcastRequest(title: title.trimmingCharacters(in: .whitespaces),
                                                 body: message.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 plaatsen: plaatsen.sorted(), guid: nil)
            let n = try await session.call { try await BeheerAPI.shared.broadcast(req, token: $0) }
            result = "In de wachtrij voor \(n) toestel\(n == 1 ? "" : "len")"
            message = ""
            await loadHistory()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PlaatsPicker: View {
    @Binding var selection: Set<String>
    var body: some View {
        List {
            Button {
                selection.removeAll()
            } label: {
                HStack {
                    Text("Iedereen")
                    Spacer()
                    if selection.isEmpty { Image(systemName: "checkmark").foregroundStyle(Theme.red) }
                }
            }
            ForEach(PLAATSEN, id: \.self) { p in
                Button {
                    if selection.contains(p) { selection.remove(p) } else { selection.insert(p) }
                } label: {
                    HStack {
                        Text(p)
                        Spacer()
                        if selection.contains(p) { Image(systemName: "checkmark").foregroundStyle(Theme.red) }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .navigationTitle("Plaatsen")
    }
}
