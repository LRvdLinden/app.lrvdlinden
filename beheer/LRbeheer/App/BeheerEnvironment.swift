import BingrKit
import P2000Kit
import PasrKit
import SwiftUI
import TunrKit

/// De beheeromgevingen, in de vaste volgorde van het overzicht (nieuwe omgevingen achteraan).
enum BeheerEnvironment: String, CaseIterable, Identifiable, Codable {
    case lrvdlinden, pixelforges, bingr, tunr, pasr, p2000, bekendr

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lrvdlinden: "LRvdLinden"
        case .pixelforges: "PixelForges"
        case .bingr: "Bingr"
        case .tunr: "Tunr"
        case .pasr: "Pasr"
        case .p2000: "A-Alerts"
        case .bekendr: "Bekendr"
        }
    }

    /// Korte omschrijving op de kaart in het overzicht.
    var subtitle: LocalizedStringKey {
        switch self {
        case .lrvdlinden: "Apps op lrvdlinden.app, store-check en logboek"
        case .pixelforges: "Website, pakketten, portfolio en reviews"
        case .bingr: "Gebruikers, support, push, nieuwsbrief en omzet"
        case .tunr: "Installaties, statistieken en downloads"
        case .pasr: "Accounts, insights en pushmeldingen"
        case .p2000: "Meldingen, waarschuwingen, push en statistieken"
        case .bekendr: "Downloads op iPhone, iPad, Mac en Android"
        }
    }

    var site: String {
        switch self {
        case .lrvdlinden: "lrvdlinden.app"
        case .pixelforges: "pixelforges.nl"
        case .bingr: "beheer.bingr.online"
        case .tunr: "beheer.tunr.online"
        case .pasr: "beheer.pasr.nl"
        case .p2000: "a-alerts.nl"
        case .bekendr: "bekendr.lrvdlinden.app"
        }
    }

    /// Accentkleur van de omgeving (uit de eigen huisstijl van elke app).
    var color: Color {
        switch self {
        case .lrvdlinden: Brand.accent
        case .pixelforges: Color(rgb: 0xD0FB65)
        case .bingr: Color(rgb: 0xE50914)
        case .tunr: Color(rgb: 0xFF5A1F)
        case .pasr: Color(rgb: 0x6A5CFF)
        case .p2000: Color(rgb: 0xDC2626)
        case .bekendr: Color(rgb: 0x2747E8)
        }
    }

    /// Icoon in de asset-catalogus (Env/<naam>): het app-icoon of logo van de omgeving.
    var iconAsset: String { "Env/\(rawValue)" }

    /// URL-schema's/hosts die bij deze omgeving horen (deeplinks en pushmeldingen).
    @MainActor func owns(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "lrbeheer" { return url.host?.lowercased() == rawValue }
        switch self {
        case .lrvdlinden: return url.host?.lowercased() == "lrvdlinden.app"
        case .pixelforges: return url.host?.lowercased() == "pixelforges.nl"
        case .bingr: return BingrEnvironment.owns(url)
        case .tunr: return TunrEnvironment.owns(url)
        case .pasr: return PasrEnvironment.owns(url)
        case .p2000: return P2000Environment.owns(url)
        case .bekendr: return url.host?.lowercased() == "bekendr.lrvdlinden.app"
        }
    }

    @MainActor var isSignedIn: Bool {
        switch self {
        case .lrvdlinden: LRvdLindenStore.shared.account.isSignedIn
        case .pixelforges: PixelForgesStore.shared.account.isSignedIn
        case .bingr: BingrEnvironment.isSignedIn
        case .tunr: TunrEnvironment.isSignedIn
        case .pasr: PasrEnvironment.isSignedIn
        case .p2000: P2000Environment.isSignedIn
        case .bekendr: BekendrStore.shared.isSignedIn
        }
    }

    /// Weergave die de oorspronkelijke app afdwong (Bingr, Tunr en Pasr waren altijd donker).
    @MainActor var forcedScheme: ColorScheme? {
        switch self {
        case .lrvdlinden, .pixelforges, .bekendr: nil
        case .bingr: BingrEnvironment.colorScheme
        case .tunr: TunrEnvironment.colorScheme
        case .pasr: PasrEnvironment.colorScheme
        case .p2000: P2000Environment.colorScheme
        }
    }

    /// De volledige interface van de omgeving.
    @MainActor @ViewBuilder var rootView: some View {
        switch self {
        case .lrvdlinden: LRvdLindenRoot()
        case .pixelforges: PixelForgesRoot()
        case .bingr: BingrEnvironment.rootView()
        case .tunr: TunrEnvironment.rootView()
        case .pasr: PasrEnvironment.rootView()
        case .p2000: P2000Environment.rootView()
        case .bekendr: BekendrRoot()
        }
    }

    /// Deeplink openen binnen de omgeving (nadat LRbeheer naar de omgeving is gewisseld).
    @MainActor func open(_ url: URL) {
        switch self {
        case .lrvdlinden, .pixelforges, .bekendr: break
        case .bingr: BingrEnvironment.open(url)
        case .tunr: TunrEnvironment.open(url)
        case .pasr: PasrEnvironment.open(url)
        case .p2000: P2000Environment.open(url)
        }
    }
}

/// Logo of app-icoon van een omgeving (afgeronde tegel).
struct EnvironmentIcon: View {
    let env: BeheerEnvironment
    var size: CGFloat = 44

    var body: some View {
        Group {
            if env == .lrvdlinden {
                LRLogo(size: size)
            } else {
                Image(env.iconAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
