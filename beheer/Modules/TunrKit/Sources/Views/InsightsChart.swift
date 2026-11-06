import Charts
import SwiftUI

// Grafiekkaart "Gebruikers" in de stijl van Homey Insights (docs/CONTRACT.md, scherm Overzicht): periodekeuze
// Week · Maand · Kwartaal · Jaar, ‹ › om een periode terug/vooruit te gaan, reeksen als aan/uit-chips, kruisdraad met
// label (datum + waarden), samenvatting en vergroten. Twee panelen met elk een eigen schaal en een gedeelde tijdas.

/// Periode van de grafiek (`days` van de actie `stats`).
enum StatsRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: return L("Week")
        case .month: return L("Maand")
        case .quarter: return L("Kwartaal")
        case .year: return L("Jaar")
        }
    }

    /// Zo ver kun je terug: offset × days ≤ 400 (bewaartermijn).
    var maxOffset: Int { 400 / rawValue }
}

/// Wat er wordt opgevraagd: periode en aantal periodes terug.
struct StatsQuery: Hashable {
    var range: StatsRange
    var offset: Int

    static let defaultsKey = "statsRangeDays"

    /// Laatst gekozen periode (per apparaat), altijd de huidige.
    static var saved: StatsQuery {
        StatsQuery(range: StatsRange(rawValue: UserDefaults.module.integer(forKey: defaultsKey)) ?? .month, offset: 0)
    }
}

enum InsightsStyle {
    static let newColor = Color(hex: 0x22D3EE)
    static let activeDot = Color(hex: 0xFF8A1F)
    static let area = LinearGradient(stops: [
        .init(color: BeheerTheme.accent.opacity(0.30), location: 0),
        .init(color: BeheerTheme.accent.opacity(0.08), location: 0.55),
        .init(color: BeheerTheme.accent.opacity(0), location: 1),
    ], startPoint: .top, endPoint: .bottom)
}

struct InsightPoint: Identifiable {
    let day: String
    let date: Date
    let active: Int
    let new: Int

    var id: String { day }
}

/// Mooie schaal: ronde stap (1-2-2,5-5 × 10ⁿ, heel getal) met 2 … maxTicks stappen; de laagste top wint.
struct NiceScale {
    let top: Double
    let step: Double

    var ticks: [Double] {
        stride(from: 0.0, through: top + 0.001, by: step).map { $0 }
    }

    static func make(value: Double, maxTicks: Int) -> NiceScale {
        guard value > 0 else { return NiceScale(top: 4, step: 1) }
        var best: NiceScale?
        var e = 1.0
        while e <= value * 10 {
            for k in [1.0, 2.0, 2.5, 5.0] {
                let step = k * e
                if step.rounded() != step { continue }
                let n = Swift.max(1, Int((value / step).rounded(.up)))
                if n > maxTicks || (n < 2 && value > 1) { continue }
                let top = Double(n) * step
                if let b = best, top > b.top || (top == b.top && step <= b.step) { continue }
                best = NiceScale(top: top, step: step)
            }
            e *= 10
        }
        return best ?? NiceScale(top: value.rounded(.up), step: value.rounded(.up))
    }
}

/// Dagreeks van de periode (aangevuld met nullen) en de samenvattingen.
struct InsightsData {
    let points: [InsightPoint]
    let from: Date
    let to: Date
    let activeSummary: SeriesSummary
    let newSummary: SeriesSummary

    init(stats: Stats, query: StatsQuery) {
        let r = InsightsData.range(stats: stats, query: query)
        var byDay: [String: DayPoint] = [:]
        for p in stats.perDay { byDay[p.day] = p }
        let keyFormat = DateFormatter()
        keyFormat.locale = Locale(identifier: "en_US_POSIX")
        keyFormat.timeZone = TimeZone.current
        keyFormat.dateFormat = "yyyy-MM-dd"
        let start = Fmt.parseDay(r.from) ?? Date()
        let end = Fmt.parseDay(r.to) ?? start
        let cal = Calendar.current
        var pts: [InsightPoint] = []
        var d = start
        while d <= end && pts.count < 400 {
            let key = keyFormat.string(from: d)
            let p = byDay[key]
            pts.append(InsightPoint(day: key, date: d, active: Swift.max(0, p?.active ?? 0), new: Swift.max(0, p?.new ?? 0)))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        points = pts
        from = start
        to = end
        activeSummary = stats.summary?.active ?? SeriesSummary(values: pts.map(\.active), withTotal: false)
        newSummary = stats.summary?.new ?? SeriesSummary(values: pts.map(\.new), withTotal: true)
    }

    /// Van het eerste tot en met het laatste etmaal (de staafjes en punten staan midden op de dag).
    var xDomain: ClosedRange<Date> {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: to) ?? to.addingTimeInterval(86_400)
        return from...end
    }

    /// Periode uit het antwoord, of berekend uit de keuze (oudere server zonder `range`).
    static func range(stats: Stats, query: StatsQuery) -> StatsRangeInfo {
        if let r = stats.range, r.isValid { return r }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let today = utc.startOfDay(for: Date())
        let to = utc.date(byAdding: .day, value: -query.offset * query.range.rawValue, to: today) ?? today
        let from = utc.date(byAdding: .day, value: -(query.range.rawValue - 1), to: to) ?? to
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return StatsRangeInfo(from: f.string(from: from), to: f.string(from: to), days: query.range.rawValue, offset: query.offset)
    }
}

// MARK: - Kaart

struct InsightsCard: View {
    let stats: Stats
    @Binding var query: StatsQuery
    @Binding var showActive: Bool
    @Binding var showNew: Bool
    var loading = false
    var expanded = false
    var onExpand: (() -> Void)? = nil

    @State private var selected: Date?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(stats: Stats, query: Binding<StatsQuery>, showActive: Binding<Bool>, showNew: Binding<Bool>,
         loading: Bool = false, expanded: Bool = false, onExpand: (() -> Void)? = nil) {
        self.stats = stats
        _query = query
        _showActive = showActive
        _showNew = showNew
        self.loading = loading
        self.expanded = expanded
        self.onExpand = onExpand
    }

    private var wide: Bool {
        #if os(iOS)
        return expanded || sizeClass == .regular
        #else
        return true
        #endif
    }

    var body: some View {
        let d = InsightsData(stats: stats, query: query)
        VStack(alignment: .leading, spacing: 14) {
            header(d)
            chips
            charts(d)
                .opacity(loading ? 0.45 : 1)
                .animation(.easeInOut(duration: 0.2), value: loading)
            Rectangle()
                .fill(BeheerTheme.stroke)
                .frame(height: 1)
            summary(d)
        }
        .card(padding: 16)
        .onChange(of: query) { _, _ in selected = nil }
    }

    // MARK: kop

    private func header(_ d: InsightsData) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                titleAndNav(d, spread: false)
                Spacer(minLength: 8)
                rangePicker.fixedSize()
                expandButton
            }
            VStack(alignment: .leading, spacing: 12) {
                titleAndNav(d, spread: true)
                HStack(spacing: 10) {
                    rangePicker
                    expandButton
                }
            }
        }
    }

    private func titleAndNav(_ d: InsightsData, spread: Bool) -> some View {
        HStack(spacing: 6) {
            Text(L("Gebruikers"))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.trailing, spread ? 0 : 10)
            if spread { Spacer(minLength: 4) }
            navButton("chevron.left", label: L("Vorige periode"), disabled: query.offset >= query.range.maxOffset) {
                query.offset += 1
            }
            Text(Fmt.period(d.from, d.to))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
            navButton("chevron.right", label: L("Volgende periode"), disabled: query.offset <= 0) {
                query.offset -= 1
            }
        }
    }

    private func navButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? BeheerTheme.dim.opacity(0.5) : Color.white)
        .disabled(disabled || loading)
        .accessibilityLabel(label)
    }

    private var rangePicker: some View {
        Picker(L("Periode"), selection: Binding(get: { query.range }, set: { query = StatsQuery(range: $0, offset: 0) })) {
            ForEach(StatsRange.allCases) { r in
                Text(r.title).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder private var expandButton: some View {
        if let onExpand {
            Button(action: onExpand) {
                Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(BeheerTheme.elevated, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(BeheerTheme.stroke, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? L("Verkleinen") : L("Vergroten"))
            .help(expanded ? L("Verkleinen") : L("Vergroten"))
        }
    }

    // MARK: reeksen

    private var chips: some View {
        HStack(spacing: 8) {
            chip(L("Actieve gebruikers"), on: showActive, isNew: false) {
                if !(showActive && !showNew) { showActive.toggle() }
            }
            chip(L("Nieuwe gebruikers"), on: showNew, isNew: true) {
                if !(showNew && !showActive) { showNew.toggle() }
            }
        }
    }

    private func chip(_ title: String, on: Bool, isNew: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { action() }
        } label: {
            HStack(spacing: 7) {
                SeriesSwatch(isNew: isNew, on: on)
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? Color.white : BeheerTheme.dim)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.white.opacity(on ? 0.07 : 0.03), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(on ? 0.14 : 0.08), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: grafieken

    @ViewBuilder private func charts(_ d: InsightsData) -> some View {
        if d.points.isEmpty {
            EmptyChart()
        } else {
            let both = showActive && showNew
            let aScale = NiceScale.make(value: Double(d.points.map(\.active).max() ?? 0) * 1.05, maxTicks: 4)
            let nMax = Double(d.points.map(\.new).max() ?? 0) * 1.05
            let nScale = NiceScale.make(value: nMax, maxTicks: nMax <= 12 ? (both ? 4 : 5) : (both ? 3 : 4))
            let chars = Swift.max(Fmt.num(Int(aScale.top)).count, Fmt.num(Int(nScale.top)).count)
            let labelWidth = CGFloat(chars) * 7 + 4
            let sel = selectedPoint(d)
            let tall: CGFloat = expanded ? 380 : 210
            VStack(alignment: .leading, spacing: 6) {
                if showActive {
                    caption(L("Actieve gebruikers"))
                    activeChart(d, scale: aScale, labelWidth: labelWidth, showXAxis: !showNew, sel: sel,
                                height: both ? tall : tall + (expanded ? 160 : 70))
                }
                if showNew {
                    caption(L("Nieuwe gebruikers"))
                        .padding(.top, both ? 6 : 0)
                    newChart(d, scale: nScale, labelWidth: labelWidth, sel: sel, tooltip: !showActive,
                             height: both ? (expanded ? 200 : 110) : tall + (expanded ? 160 : 70))
                }
            }
            .id("\(d.from.timeIntervalSince1970)-\(d.points.count)")
            .transition(.opacity)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(BeheerTheme.secondary)
    }

    private func selectedPoint(_ d: InsightsData) -> InsightPoint? {
        guard let selected else { return nil }
        return d.points.first { Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    private func activeChart(_ d: InsightsData, scale: NiceScale, labelWidth: CGFloat, showXAxis: Bool,
                             sel: InsightPoint?, height: CGFloat) -> some View {
        Chart {
            ForEach(d.points) { p in
                AreaMark(x: .value(L("Dag"), p.date, unit: .day),
                         y: .value(L("Actieve gebruikers"), Double(p.active)))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(InsightsStyle.area)
                LineMark(x: .value(L("Dag"), p.date, unit: .day),
                         y: .value(L("Actieve gebruikers"), Double(p.active)))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(BeheerTheme.barGradient)
            }
            if let s = sel {
                RuleMark(x: .value(L("Dag"), s.date, unit: .day))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        InsightsTooltip(point: s, showActive: showActive, showNew: showNew)
                    }
                PointMark(x: .value(L("Dag"), s.date, unit: .day),
                          y: .value(L("Actieve gebruikers"), Double(s.active)))
                    .symbol {
                        Circle()
                            .fill(InsightsStyle.activeDot)
                            .frame(width: 11, height: 11)
                            .overlay { Circle().stroke(BeheerTheme.surface, lineWidth: 2.5) }
                    }
            }
        }
        .chartXScale(domain: d.xDomain)
        .chartYScale(domain: 0...scale.top)
        .chartXSelection(value: $selected)
        .chartXAxis(showXAxis ? .automatic : .hidden)
        .chartXAxis { xAxis(d) }
        .chartYAxis { yAxis(scale, width: labelWidth) }
        .frame(height: height)
        .accessibilityLabel(L("Actieve gebruikers"))
    }

    private func newChart(_ d: InsightsData, scale: NiceScale, labelWidth: CGFloat, sel: InsightPoint?,
                          tooltip: Bool, height: CGFloat) -> some View {
        Chart {
            ForEach(d.points) { p in
                BarMark(x: .value(L("Dag"), p.date, unit: .day),
                        y: .value(L("Nieuwe gebruikers"), Double(p.new)),
                        width: .ratio(d.points.count > 120 ? 0.85 : 0.7))
                    .cornerRadius(d.points.count > 120 ? 0 : 3)
                    .foregroundStyle(InsightsStyle.newColor.opacity(sel == nil || sel?.id == p.id ? 0.9 : 0.35))
            }
            if let s = sel {
                RuleMark(x: .value(L("Dag"), s.date, unit: .day))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        if tooltip {
                            InsightsTooltip(point: s, showActive: showActive, showNew: showNew)
                        }
                    }
            }
        }
        .chartXScale(domain: d.xDomain)
        .chartYScale(domain: 0...scale.top)
        .chartXSelection(value: $selected)
        .chartXAxis { xAxis(d) }
        .chartYAxis { yAxis(scale, width: labelWidth) }
        .frame(height: height)
        .accessibilityLabel(L("Nieuwe gebruikers"))
    }

    private func xAxis(_ d: InsightsData) -> some AxisContent {
        AxisMarks(values: xTicks(d)) { value in
            AxisTick()
                .foregroundStyle(Color.white.opacity(0.2))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(xLabel(date))
                        .font(.caption2)
                        .foregroundStyle(BeheerTheme.dim)
                }
            }
        }
    }

    private func yAxis(_ s: NiceScale, width: CGFloat) -> some AxisContent {
        AxisMarks(position: .leading, values: s.ticks) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.white.opacity(value.index == 0 ? 0.18 : 0.07))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(Fmt.num(Int(v)))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(BeheerTheme.dim)
                        .frame(width: width, alignment: .trailing)
                }
            }
        }
    }

    /// Datumlabels (midden op de dag), dunner naarmate de periode langer en het scherm smaller is.
    private func xTicks(_ d: InsightsData) -> [Date] {
        let cal = Calendar.current
        let idx: [Int]
        switch query.range {
        case .week:
            idx = Array(Array(stride(from: d.points.count - 1, through: 0, by: wide ? -1 : -2)).reversed())
        case .month:
            idx = Array(Array(stride(from: d.points.count - 1, through: 0, by: wide ? -3 : -7)).reversed())
        case .quarter:
            let mondays = d.points.indices.filter { cal.component(.weekday, from: d.points[$0].date) == 2 }
            idx = mondays.enumerated().filter { $0.offset % (wide ? 1 : 3) == 0 }.map(\.element)
        case .year:
            let starts = d.points.indices.filter { cal.component(.day, from: d.points[$0].date) == 1 }
            idx = starts.enumerated().filter { $0.offset % (wide ? 1 : 2) == 0 }.map(\.element)
        }
        return idx.map { d.points[$0].date.addingTimeInterval(12 * 3600) }
    }

    private func xLabel(_ date: Date) -> String {
        switch query.range {
        case .week: return Fmt.day(date, template: wide ? "EEE d MMM" : "EEE d")
        case .month, .quarter: return Fmt.day(date, template: "d MMM")
        case .year:
            return Calendar.current.component(.month, from: date) == 1 ? Fmt.day(date, template: "y") : Fmt.day(date, template: "MMM")
        }
    }

    // MARK: samenvatting

    private func summary(_ d: InsightsData) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 24, alignment: .top)], alignment: .leading, spacing: 14) {
            if showActive {
                summaryBlock(L("Actieve gebruikers"), d.activeSummary, isNew: false)
            }
            if showNew {
                summaryBlock(L("Nieuwe gebruikers"), d.newSummary, isNew: true)
            }
        }
    }

    private func summaryBlock(_ title: String, _ s: SeriesSummary, isNew: Bool) -> some View {
        var cells: [(String, String)] = [
            (L("Min"), Fmt.num(s.min)),
            (L("Max"), Fmt.num(s.max)),
            (L("Gem."), Fmt.decimal(s.avg)),
            (L("Laatste"), Fmt.num(s.last)),
        ]
        if isNew { cells.append((L("Totaal"), Fmt.num(s.total ?? 0))) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                SeriesSwatch(isNew: isNew, on: true)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BeheerTheme.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.element.0.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(BeheerTheme.dim)
                        Text(item.element.1)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kleurstaal van een reeks: rondje (actief, accentverloop) of blokje (nieuw, cyaan); open als de reeks uit staat.
struct SeriesSwatch: View {
    let isNew: Bool
    let on: Bool

    var body: some View {
        Group {
            if isNew {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(on ? AnyShapeStyle(InsightsStyle.newColor) : AnyShapeStyle(Color.clear))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.white.opacity(on ? 0 : 0.35), lineWidth: 1.5)
                    }
            } else {
                Circle()
                    .fill(on ? AnyShapeStyle(BeheerTheme.gradient) : AnyShapeStyle(Color.clear))
                    .overlay { Circle().strokeBorder(Color.white.opacity(on ? 0 : 0.35), lineWidth: 1.5) }
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

/// Zwevend label bij de kruisdraad: datum en de waarden van de zichtbare reeksen.
struct InsightsTooltip: View {
    let point: InsightPoint
    let showActive: Bool
    let showNew: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.day(point.date, template: "EEE d MMMM y"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BeheerTheme.secondary)
            if showActive { row(L("Actieve gebruikers"), point.active, isNew: false) }
            if showNew { row(L("Nieuwe gebruikers"), point.new, isNew: true) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(BeheerTheme.elevated.opacity(0.97), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        .fixedSize()
    }

    private func row(_ title: String, _ value: Int, isNew: Bool) -> some View {
        HStack(spacing: 7) {
            SeriesSwatch(isNew: isNew, on: true)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 12)
            Text(Fmt.num(value))
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

struct EmptyChart: View {
    var body: some View {
        Text(L("Nog geen gegevens."))
            .font(.subheadline)
            .foregroundStyle(BeheerTheme.dim)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

extension View {
    /// Vergrote grafiek: schermvullend op iPhone/iPad, als venster-sheet op de Mac.
    @ViewBuilder func insightsPresentation<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}
