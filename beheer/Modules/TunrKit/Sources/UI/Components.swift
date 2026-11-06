import SwiftUI

// MARK: - Woordmerk

/// Woordmerk van de beheer-app: `TUNR` (heavy rounded, wit) met de frequentieschaal eronder (zoals TunrLogo in de
/// Tunr-app) en een klein label "BEHEER" in het accentverloop.
struct BeheerLogo: View {
    var size: CGFloat = 24
    var showBadge = true

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.3) {
            VStack(spacing: size * 0.14) {
                Text(verbatim: "TUNR")
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .kerning(size * 0.08)
                    .foregroundStyle(.white)
                FrequencyBar(width: size * 2.75, height: size * 0.34)
            }
            if showBadge {
                Text(verbatim: L("BEHEER"))
                    .font(.system(size: max(8, size * 0.36), weight: .heavy, design: .rounded))
                    .kerning(size * 0.03)
                    .foregroundStyle(.white)
                    .padding(.horizontal, size * 0.22)
                    .padding(.vertical, size * 0.08)
                    .background(BeheerTheme.gradient, in: Capsule())
                    .padding(.top, size * 0.12)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BeheerTunr")
    }
}

/// De frequentieschaal onder het woordmerk: 9 maatstreepjes, balk in het accentverloop en een naaldje.
struct FrequencyBar: View {
    var width: CGFloat
    var height: CGFloat
    var needle: CGFloat = 0.58

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(i == 4 ? 0.85 : 0.5))
                        .frame(width: max(1, height * 0.12), height: height * (i % 2 == 0 ? 0.5 : 0.32))
                    if i < 8 { Spacer(minLength: 0) }
                }
            }
            .frame(width: width, height: height * 0.62, alignment: .bottom)
            .offset(y: -height * 0.32)

            Capsule()
                .fill(BeheerTheme.gradient)
                .frame(width: width, height: max(2, height * 0.26))

            Capsule()
                .fill(BeheerTheme.accent2)
                .frame(width: max(1.5, height * 0.16), height: height)
                .shadow(color: BeheerTheme.accent2.opacity(0.7), radius: height * 0.3)
                .offset(x: width * needle)
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
    }
}

// MARK: - Bouwstenen

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(BeheerTheme.text)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BeheerTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Kengetal-tegel
struct KPITile: View {
    let title: String
    let value: Int
    let icon: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(highlight ? BeheerTheme.accent2 : BeheerTheme.secondary)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BeheerTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(Fmt.num(value))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlight ? AnyShapeStyle(BeheerTheme.gradient) : AnyShapeStyle(Color.white))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Horizontale staafjes met label, aantal en percentage.
struct BarList: View {
    struct Row: Identifiable {
        let id: String
        let label: String
        var leading: String? = nil       // emoji (vlag)
        var icon: String? = nil          // SF Symbol
        var detail: String? = nil
        let value: Int
    }

    let rows: [Row]
    var emptyText = L("Nog geen gegevens.")

    private var total: Int { rows.reduce(0) { $0 + $1.value } }
    private var maxValue: Int { rows.map(\.value).max() ?? 0 }

    var body: some View {
        if rows.isEmpty || total == 0 {
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(BeheerTheme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { r in
                    row(r)
                }
            }
        }
    }

    private func row(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let leading = r.leading {
                    Text(verbatim: leading).font(.body)
                } else if let icon = r.icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(BeheerTheme.secondary)
                        .frame(width: 20)
                }
                Text(r.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let detail = r.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(BeheerTheme.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Fmt.num(r.value))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(Fmt.percent(r.value, of: total))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(BeheerTheme.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(BeheerTheme.barGradient)
                        .frame(width: max(4, geo.size.width * CGFloat(r.value) / CGFloat(max(1, maxValue))))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.label): \(Fmt.num(r.value)), \(Fmt.percent(r.value, of: total))")
    }
}

/// Melding in een balk (fout of info).
struct NoticeBanner: View {
    let text: String
    var bad = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: bad ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(bad ? BeheerTheme.bad : BeheerTheme.accent2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 12)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(BeheerTheme.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Knop Vernieuwen in de werkbalk (⌘R zit op de Mac in het menu, op de iPad aan deze knop).
struct RefreshButton: View {
    let busy: Bool
    let action: () -> Void

    var body: some View {
        #if os(macOS)
        button
        #else
        button.keyboardShortcut("r", modifiers: .command)
        #endif
    }

    private var button: some View {
        Button(action: action) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Label(L("Vernieuwen"), systemImage: "arrow.clockwise")
            }
        }
        .disabled(busy)
        .help(L("Vernieuwen (⌘R)"))
    }
}
