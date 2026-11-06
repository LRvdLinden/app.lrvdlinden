import SwiftUI
import UIKit

/// Icoon, "Versie: 1.0.0 (1)" en "© <jaar> LRbeheer", helemaal onderaan Instellingen.
struct AppInfoFooter: View {
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 64

    private let info = Bundle.main.infoDictionary ?? [:]
    private var appName: String {
        info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? ""
    }
    private var version: String { info["CFBundleShortVersionString"] as? String ?? "–" }
    private var build: String { info["CFBundleVersion"] as? String ?? "–" }
    /// String(...) voorkomt "2.026" door getalopmaak.
    private var year: String { String(Calendar.current.component(.year, from: .now)) }

    var body: some View {
        VStack(spacing: 10) {
            if let icon = Self.appIcon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                    .accessibilityHidden(true)
                    .padding(.bottom, 6)
            }
            Text(verbatim: "\(AppInfoText.current.version): \(version) (\(build))")
            Text(verbatim: "© \(year) \(appName)")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    static var appIcon: Image? {
        if let img = UIImage(named: "AppIconDisplay") { return Image(uiImage: img) }
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last,
              let img = UIImage(named: name) else { return nil }
        return Image(uiImage: img)
    }
}

struct AppInfoText {
    let version: String
    static var current: AppInfoText { all[Config.uiLanguage] ?? all["en"]! }
    static let all: [String: AppInfoText] = [
        "nl": .init(version: "Versie"), "en": .init(version: "Version"),
        "de": .init(version: "Version"), "fr": .init(version: "Version"),
        "es": .init(version: "Versión"), "it": .init(version: "Versione"),
        "sv": .init(version: "Version"), "no": .init(version: "Versjon"),
        "da": .init(version: "Version"), "pl": .init(version: "Wersja"),
    ]
}
