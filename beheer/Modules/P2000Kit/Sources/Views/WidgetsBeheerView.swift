import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Widgets (live kaart, Verkeer nu) for other websites: GET /v1/beheer/widgets, POST /v1/beheer/widgets/blok

struct WidgetSite: Decodable, Identifiable, Hashable {
    let site: String
    let widgets: String
    let eerst: String
    let laatst: String
    let views7: Int
    let totaal: Int
    let blok: Bool
    let actief: Bool
    var id: String { site }
}

private struct WidgetSites: Decodable { let sites: [WidgetSite] }
private struct BlokBody: Encodable { let site: String; let blok: Bool }

struct WidgetsBeheerView: View {
    @Environment(Session.self) private var session
    @State private var soort = "kaart,verkeer"
    @State private var thema = "auto"
    @State private var sites: [WidgetSite] = []
    @State private var error: String?
    @State private var gekopieerd: String?
    @State private var teBlokkeren: WidgetSite?

    private var script: String {
        "<div data-a-alerts-widget=\"\(soort)\" data-thema=\"\(thema)\"></div>\n<script src=\"https://a-alerts.nl/widget/embed.js\" async></script>"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Picker("Widget", selection: $soort) {
                        Text("Kaart + verkeer").tag("kaart,verkeer")
                        Text("Alleen kaart").tag("kaart")
                        Text("Alleen verkeer").tag("verkeer")
                    }
                    Picker("Thema", selection: $thema) {
                        Text("Automatisch").tag("auto")
                        Text("Licht").tag("licht")
                        Text("Donker").tag("donker")
                    }
                    code("Script", script)
                    if let url = URL(string: "https://a-alerts.nl/widget/?w=\(soort)&thema=\(thema)") {
                        Link(destination: url) { Label("Bekijk voorbeeld", systemImage: "safari") }
                    }
                } header: {
                    Text("Code om te delen")
                } footer: {
                    Text("We bieden alleen de script-code aan: de widget komt van a-alerts.nl, past zijn hoogte vanzelf aan en kan door de website niet worden aangepast. In de widget staat altijd \"A-Alerts\" in de kop en een link naar a-alerts.nl.")
                }
                Section {
                    if sites.isEmpty {
                        Text("Nog op geen enkele andere website ingesloten.").foregroundStyle(.secondary)
                    }
                    ForEach(sites) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.site).font(.headline)
                                Spacer()
                                Text(s.blok ? "geblokkeerd" : s.actief ? "actief" : "geen bezoek >3 dagen")
                                    .font(.caption.bold())
                                    .foregroundStyle(s.blok ? Color.red : s.actief ? Color.green : Color.secondary)
                            }
                            Text("\(s.widgets.replacingOccurrences(of: ",", with: " + ")) · \(s.views7) weergaven in 7 dagen · \(s.totaal) totaal")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Eerst gezien \(Self.datum(s.eerst)) · laatst \(Self.datum(s.laatst))").font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(s.blok ? "Deblokkeer" : "Blokkeer") { if s.blok { Task { await zetBlok(s, false) } } else { teBlokkeren = s } }
                                .tint(s.blok ? .green : .red)
                        }
                        .contextMenu {
                            Button(s.blok ? "Deblokkeer" : "Blokkeer", systemImage: s.blok ? "checkmark.circle" : "nosign") {
                                if s.blok { Task { await zetBlok(s, false) } } else { teBlokkeren = s }
                            }
                            if let url = URL(string: "https://\(s.site)") { Link("Open website", destination: url) }
                        }
                    }
                } header: {
                    Text("Ingesloten op")
                } footer: {
                    Text("De widget meldt alleen de domeinnaam van de site, geen gegevens van bezoekers. Een geblokkeerde site toont alleen een link naar a-alerts.nl. Veeg naar links om te blokkeren.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Widgets")
            .refreshable { await load() }
            .task { await load() }
            .confirmationDialog("\(teBlokkeren?.site ?? "") blokkeren?", isPresented: Binding(get: { teBlokkeren != nil }, set: { if !$0 { teBlokkeren = nil } }), titleVisibility: .visible) {
                Button("Blokkeer", role: .destructive) { if let s = teBlokkeren { Task { await zetBlok(s, true) } } }
            } message: {
                Text("De site toont dan alleen een link naar a-alerts.nl.")
            }
        }
    }

    private func code(_ titel: String, _ tekst: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titel).font(.subheadline.bold())
            Text(tekst).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Button(gekopieerd == titel ? "Gekopieerd" : "Kopieer", systemImage: gekopieerd == titel ? "checkmark" : "doc.on.doc") {
                kopieer(tekst); gekopieerd = titel
            }
        }
        .padding(.vertical, 4)
    }

    private func kopieer(_ s: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = s
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #endif
    }

    private func load() async {
        do {
            let r: WidgetSites = try await session.call { try await BeheerAPI.shared.getJSON("v1/beheer/widgets", token: $0) }
            sites = r.sites; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func zetBlok(_ s: WidgetSite, _ blok: Bool) async {
        do {
            let r: WidgetSites = try await session.call { try await BeheerAPI.shared.sendJSON("POST", "v1/beheer/widgets/blok", body: BlokBody(site: s.site, blok: blok), token: $0) }
            sites = r.sites; error = nil
        } catch { self.error = error.localizedDescription }
        teBlokkeren = nil
    }

    private static func datum(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}
