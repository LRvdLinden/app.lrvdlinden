import SwiftUI

/// Downloads (acties `builds` en `build_link`): per platform de nieuwste build en de oudere builds. De pakketten staan
/// alleen op de server van beheer.tunr.online; Downloaden opent een link van 10 minuten in de browser.
struct DownloadsView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.openURL) private var openURL
    @State private var builds: BuildsResponse?
    @State private var loadedAt: Date?
    @State private var loading = false
    @State private var error: String?
    /// "<platform>/<bestand>" waarvoor nu een link wordt gemaakt
    @State private var busy: String?

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Buildpakketten van Tunr en BeheerTunr. Ze staan alleen op beheer.tunr.online (niet op GitHub); elke downloadlink is 10 minuten geldig."))
                        .font(.subheadline)
                        .foregroundStyle(BeheerTheme.secondary)
                    Spacer(minLength: 8)
                    if let loadedAt {
                        Text(String(format: L("Bijgewerkt om %@"), Fmt.time(loadedAt)))
                            .font(.caption)
                            .foregroundStyle(BeheerTheme.dim)
                            .lineLimit(1)
                    }
                }
                if let error {
                    NoticeBanner(text: error)
                }
                if let builds {
                    if !builds.ready {
                        NoticeBanner(text: L("Downloads zijn nog niet ingericht (TUNR_BUILDS_KEY ontbreekt; draai de workflow Backend)."), bad: false)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(BuildPlatform.allCases) { p in
                                card(p, builds.platforms[p.rawValue] ?? [])
                            }
                        }
                    }
                } else if error == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(BeheerTheme.edge)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(L("Downloads"))
        .largeTitle()
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RefreshButton(busy: loading) { Task { await load() } }
            }
        }
        .task { if builds == nil { await load() } }
        .onChange(of: session.refreshTick) { _, _ in
            Task { await load() }
        }
    }

    @ViewBuilder private func card(_ p: BuildPlatform, _ list: [BuildInfo]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: p.icon)
                    .font(.title3)
                    .foregroundStyle(BeheerTheme.gradient)
                    .frame(width: 28)
                SectionHeader(title: p.title, subtitle: p.hint)
            }
            if let latest = list.first {
                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(label: L("Versie"), value: latest.version.isEmpty ? "—" : latest.version)
                    InfoRow(label: L("Build"), value: latest.build.isEmpty ? "—" : latest.build)
                    InfoRow(label: L("Datum"), value: latest.date.map { Fmt.date($0) } ?? "—")
                    InfoRow(label: L("Grootte"), value: latest.size.map { Fmt.bytes($0) } ?? "—")
                    InfoRow(label: L("Bestand"), value: latest.file)
                }
                if !latest.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Notities"))
                            .font(.caption)
                            .foregroundStyle(BeheerTheme.secondary)
                        Text(verbatim: latest.notes)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(BeheerTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                downloadButton(p, latest, primary: true)

                let older = Array(list.dropFirst())
                if !older.isEmpty {
                    Divider().overlay(BeheerTheme.stroke)
                    Text(L("Oudere builds"))
                        .font(.caption)
                        .foregroundStyle(BeheerTheme.secondary)
                    ForEach(older) { b in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                if !b.detail.isEmpty {
                                    Text(b.detail)
                                        .font(.caption)
                                        .foregroundStyle(BeheerTheme.dim)
                                }
                            }
                            Spacer(minLength: 8)
                            downloadButton(p, b, primary: false)
                        }
                    }
                }
            } else {
                Text(L("Nog geen build op de server."))
                    .font(.subheadline)
                    .foregroundStyle(BeheerTheme.dim)
            }
        }
        .card()
    }

    @ViewBuilder private func downloadButton(_ p: BuildPlatform, _ b: BuildInfo, primary: Bool) -> some View {
        let key = "\(p.rawValue)/\(b.file)"
        let isBusy = busy == key
        let button = Button {
            Task { await download(p, b) }
        } label: {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.down.circle")
                }
                Text(L("Downloaden"))
            }
        }
        .disabled(busy != nil)
        .accessibilityLabel(String(format: L("%@ downloaden"), b.title))
        if primary {
            button.buttonStyle(.accent)
        } else {
            button.buttonStyle(.secondary)
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            builds = try await session.call("builds", as: BuildsResponse.self)
            loadedAt = Date()
            error = nil
        } catch {
            if error is CancellationError { return }
            if let e = error as? APIError, e.isUnauthorized { return }
            self.error = (error as? APIError)?.errorDescription ?? L("Er ging iets mis.")
        }
    }

    private func download(_ p: BuildPlatform, _ b: BuildInfo) async {
        busy = "\(p.rawValue)/\(b.file)"
        defer { busy = nil }
        do {
            let r = try await session.call("build_link", ["platform": p.rawValue, "file": b.file], as: BuildLinkResponse.self)
            guard let url = URL(string: r.url), url.scheme == "https" else {
                error = L("Onverwacht antwoord van de server.")
                return
            }
            error = nil
            openURL(url)
        } catch {
            if error is CancellationError { return }
            if let e = error as? APIError, e.isUnauthorized { return }
            self.error = (error as? APIError)?.errorDescription ?? L("Er ging iets mis.")
            if (error as? APIError)?.code == "build_not_found" { await load() }
        }
    }
}
