import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(Session.self) private var session
    @State private var data: Overview?
    @State private var error: String?
    @State private var loading = false

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { ErrorBanner(text: error) }
                    if let d = data {
                        kpis(d)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            statusCard(d.status)
                            appleLoginCard(d.app)
                            visitorsCard(d.website)
                            activeCard(d.app)
                            platformCard(d.app)
                            if let a = d.android { androidCard(a) }
                            versionsCard(d.app)
                            meldingenCard(d.meldingen)
                            websiteDetailCard(d.website)
                            topCard(d.topBekeken)
                            if let a = d.aAlerts { AAlertsDashboardCards(a: a) }
                        }
                        Text("Bijgewerkt \(Fmt.relative(d.generated))")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    } else if loading {
                        ProgressView("Laden…").frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding()
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.pageBackground)
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem {
                    Button { Task { await load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") }
                        .keyboardShortcut("r")
                }
            }
            .refreshable { await load() }
            .task {
                await load()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    await load()
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            data = try await session.call { try await BeheerAPI.shared.overview(token: $0) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: KPI row

    private func kpis(_ d: Overview) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            KPI(title: "Actieve app-gebruikers", value: d.app.actief, sub: "laatste 30 dagen · \(d.app.totaal) totaal", icon: "iphone", color: Theme.red)
            KPI(title: "Ingelogd met Apple", value: d.app.appleLogin.ja, sub: "\(d.app.appleLogin.nee) zonder login", icon: "apple.logo", color: .primary)
            KPI(title: "Pushmeldingen aan", value: d.app.push.toestellen, sub: "toestellen geregistreerd", icon: "bell.badge.fill", color: .orange)
            KPI(title: "Websitebezoekers", value: d.website.vandaag, sub: "vandaag · gisteren \(d.website.gisteren)", icon: "globe", color: .blue)
            KPI(title: "Meldingen vandaag", value: d.meldingen.vandaag, sub: "gisteren \(d.meldingen.gisteren)", icon: "light.beacon.max.fill", color: Theme.red)
        }
    }

    // MARK: Cards

    private func statusCard(_ s: Overview.Status) -> some View {
        Card(title: "Status", icon: "waveform.path.ecg") {
            let feedOK = (Fmt.parse(s.feed.lastOk).map { Date.now.timeIntervalSince($0) < 5 * 60 }) ?? false
            StatusRow(ok: feedOK, title: "P2000-feed", detail: s.feed.lastError ?? "laatst gelezen \(Fmt.relative(s.feed.lastOk))")
            StatusRow(ok: (Fmt.parse(s.cron).map { Date.now.timeIntervalSince($0) < 5 * 60 }) ?? false, title: "Cron (elke minuut)", detail: Fmt.relative(s.cron))
            StatusRow(ok: s.apns, title: "Pushmeldingen (APNs)", detail: s.apns ? "sleutel actief" : "sleutel ontbreekt")
            if let fcm = s.fcm {
                StatusRow(ok: fcm, title: "Android-push (Firebase)", detail: fcm ? "serviceaccount actief" : "FCM_SERVICE_ACCOUNT ontbreekt")
            }
            StatusRow(ok: s.weatherkit, title: "WeatherKit", detail: s.weatherkit ? "actief" : "niet ingesteld")
            StatusRow(ok: s.mapkit && s.mapsServer, title: "Apple Maps", detail: "MapKit JS \(s.mapkit ? "✓" : "✗") · Server API \(s.mapsServer ? "✓" : "✗")")
            Divider()
            HStack {
                Text("\(s.meldingenInDatabase) meldingen in de database")
                Spacer()
                if s.outbox > 0 { Text("\(s.outbox) pushes in de wachtrij").foregroundStyle(.orange) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func appleLoginCard(_ a: Overview.App) -> some View {
        Card(title: "Inloggen met Apple", icon: "apple.logo") {
            let items = [("Met Apple", a.appleLogin.ja, Color.primary), ("Zonder login", a.appleLogin.nee, Color.gray.opacity(0.4))]
            if a.actief == 0 {
                EmptyChart(text: "Nog geen app-gebruikers. De telling begint vanaf build 6.")
            } else {
                HStack(spacing: 20) {
                    Chart(items, id: \.0) { item in
                        SectorMark(angle: .value("Aantal", item.1), innerRadius: .ratio(0.62), angularInset: 2)
                            .foregroundStyle(item.2)
                            .cornerRadius(4)
                    }
                    .frame(width: 130, height: 130)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(Int((Double(a.appleLogin.ja) / Double(max(a.actief, 1)) * 100).rounded()))%").font(.title2.bold())
                            Text("met Apple").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items, id: \.0) { item in
                            LegendRow(color: item.2, title: item.0, value: item.1)
                        }
                        LegendRow(color: .orange, title: "Push aan", value: a.push.aan)
                    }
                }
            }
        }
    }

    private func visitorsCard(_ w: Overview.Website) -> some View {
        Card(title: "Websitebezoekers · 30 dagen", icon: "globe") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(w.bezoeken30)").font(.system(size: 30, weight: .black, design: .rounded))
                Text("bezoeken").foregroundStyle(.secondary)
                Spacer()
                Text("7 dagen: \(w.bezoeken7)").font(.caption).foregroundStyle(.secondary)
            }
            Chart(w.perDag) { v in
                BarMark(x: .value("Dag", Fmt.dayDate(v.day), unit: .day), y: .value("Bezoekers", v.bezoekers))
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(3)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .frame(height: 170)
            Text("Zonder cookies geteld: een bezoeker is één apparaat per dag.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func activeCard(_ a: Overview.App) -> some View {
        Card(title: "App-gebruikers per dag", icon: "chart.line.uptrend.xyaxis") {
            Chart {
                ForEach(a.actiefPerDag) { d in
                    AreaMark(x: .value("Dag", Fmt.dayDate(d.day), unit: .day), y: .value("Actief", d.n))
                        .foregroundStyle(Theme.red.opacity(0.18).gradient)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Dag", Fmt.dayDate(d.day), unit: .day), y: .value("Actief", d.n))
                        .foregroundStyle(Theme.red)
                        .interpolationMethod(.monotone)
                }
                ForEach(a.nieuwPerDag) { d in
                    BarMark(x: .value("Dag", Fmt.dayDate(d.day), unit: .day), y: .value("Nieuw", d.n))
                        .foregroundStyle(Color.green.opacity(0.7))
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .frame(height: 170)
            HStack(spacing: 14) {
                LegendDot(color: Theme.red, title: "Actief")
                LegendDot(color: .green, title: "Nieuw geïnstalleerd")
            }
        }
    }

    private func platformCard(_ a: Overview.App) -> some View {
        Card(title: "Apparaten", icon: "macbook.and.iphone") {
            if a.platforms.isEmpty {
                EmptyChart(text: "Nog geen gegevens")
            } else {
                Chart(a.platforms) { p in
                    BarMark(x: .value("Aantal", p.n), y: .value("Platform", PlatformName.label(p.platform)))
                        .foregroundStyle(PlatformName.color(p.platform))
                        .annotation(position: .trailing) { Text("\(p.n)").font(.caption.bold()).foregroundStyle(.secondary) }
                        .cornerRadius(5)
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(max(a.platforms.count, 2)) * 36)
            }
        }
    }

    /// A-Alerts voor Android: downloads van de APK op a-alerts.nl (zoals de PressKit-kaart van Tunr).
    private func androidCard(_ a: AndroidStats) -> some View {
        Card(title: "Android-app · downloads", icon: "arrow.down.circle") {
            HStack(spacing: 10) {
                miniKPI("Totaal", a.totaal)
                miniKPI("30 dagen", a.dagen30)
                miniKPI("Vandaag", a.vandaag)
            }
            if a.perDag.allSatisfy({ $0.n == 0 }) {
                EmptyChart(text: "Nog geen downloads in de laatste 30 dagen")
            } else {
                Chart(a.perDag) { d in
                    BarMark(x: .value("Dag", Fmt.dayDate(d.day), unit: .day), y: .value("Downloads", d.n))
                        .foregroundStyle(Color.teal.gradient)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 150)
            }
            if !a.perVersie.isEmpty {
                Divider()
                ForEach(a.perVersie) { v in
                    HStack {
                        Text(v.version).font(.callout.monospacedDigit())
                        Spacer()
                        Text("\(v.n)×").font(.callout.bold().monospacedDigit())
                    }
                }
            }
            Divider()
            LegendRow(color: .teal, title: "Android-installaties (actief 30 dagen)", value: a.actief)
            LegendRow(color: .green, title: "Android-toestellen met push", value: a.pushToestellen)
            Text("Een download telt één keer per apparaat per dag, zonder cookies.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func miniKPI(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.system(size: 24, weight: .black, design: .rounded)).contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func versionsCard(_ a: Overview.App) -> some View {
        Card(title: "Versies in gebruik", icon: "number") {
            if a.versies.isEmpty {
                EmptyChart(text: "Nog geen gegevens")
            } else {
                ForEach(a.versies) { v in
                    HStack {
                        Text(v.label).font(.callout.monospacedDigit())
                        Spacer()
                        Text("\(v.n)").font(.callout.bold())
                    }
                    ProgressView(value: Double(v.n), total: Double(max(a.actief, 1))).tint(Theme.red)
                }
            }
        }
    }

    private func meldingenCard(_ m: Overview.Meldingen) -> some View {
        Card(title: "Meldingen vandaag vs. gisteren", icon: "light.beacon.max") {
            ForEach(Dienst.all, id: \.self) { d in
                HStack(spacing: 10) {
                    DienstIcoon(dienst: d, size: 24)
                    Text(Dienst.label(d))
                    Spacer()
                    Text("\(m.perDienst[d] ?? 0)").font(.headline.monospacedDigit())
                    Text("/ \(m.perDienstGisteren[d] ?? 0)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func websiteDetailCard(_ w: Overview.Website) -> some View {
        Card(title: "Website", icon: "safari") {
            HStack {
                Text("Pagina's vandaag")
                Spacer()
                Text("\(w.paginasVandaag)").bold()
            }
            Divider()
            ForEach(w.topPaginas) { p in
                HStack {
                    Text(pageName(p.path))
                    Spacer()
                    Text("\(p.n)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if !w.apparaten.isEmpty {
                Divider()
                HStack(spacing: 14) {
                    ForEach(w.apparaten) { d in
                        Label("\(d.n)", systemImage: d.device == "mobiel" ? "iphone" : d.device == "tablet" ? "ipad" : "desktopcomputer")
                            .font(.callout)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func pageName(_ path: String) -> String {
        switch path {
        case "/": return "Homepage"
        case "/pager/": return "Live pager"
        case "/android/": return "Android-download"
        case "/info/": return "Privacy / voorwaarden"
        case "/melding/": return "Oude meldinglinks"
        default: return path
        }
    }

    private func topCard(_ list: [Overview.Top]) -> some View {
        Card(title: "Meest bekeken meldingen", icon: "eye") {
            if list.isEmpty {
                EmptyChart(text: "Nog geen views")
            } else {
                ForEach(list) { t in
                    HStack(spacing: 10) {
                        DienstIcoon(dienst: t.dienst, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.callout).lineLimit(1)
                            Text(Fmt.relative(t.datum_tijd)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("\(t.views)", systemImage: "eye").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct KPI: View {
    let title: String
    let value: Int
    let sub: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text("\(value)").font(.system(size: 30, weight: .black, design: .rounded)).contentTransition(.numericText())
            Text(title).font(.caption.weight(.semibold))
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatusRow: View {
    let ok: Bool
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Theme.green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

struct LegendRow: View {
    let color: Color
    let title: String
    let value: Int
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.callout)
            Spacer(minLength: 8)
            Text("\(value)").font(.callout.bold().monospacedDigit())
        }
    }
}

struct LegendDot: View {
    let color: Color
    let title: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct EmptyChart: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
