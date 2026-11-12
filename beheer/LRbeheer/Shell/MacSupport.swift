#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

// Alleen de Mac-app (Mac Catalyst): minimale venstergrootte en de menubalk. Niet gecompileerd op iPhone/iPad.

/// Minimale venstergrootte; als achtergrond achter de root-view, zodra die in een venster hangt.
struct MacWindowSetup: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe {
        let v = Probe()
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.windowScene?.sizeRestrictions?.minimumSize = CGSize(width: 980, height: 640)
        }
    }
}

/// Menubalk: menu Omgeving met alle omgevingen (⌘1 … ⌘9) en Overzicht (⌘0), Instellingen (⌘,) in het app-menu,
/// geen Nieuw venster, en in Help de websites.
struct LRbeheerCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .appSettings) {
            Button("Instellingen…") { model.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("Omgeving") {
            Button("Overzicht") { model.switchTo(nil) }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            ForEach(Array(BeheerEnvironment.allCases.enumerated()), id: \.element) { i, env in
                Button(env.name) { model.switchTo(env) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
            Button("Eén inlog voor alle omgevingen…") { SharedLogin.shared.showSheet = true; model.switchTo(nil) }
        }
        CommandGroup(replacing: .help) {
            Link("lrvdlinden.app", destination: URL(string: "https://lrvdlinden.app")!)
            Link("pixelforges.nl", destination: URL(string: "https://pixelforges.nl")!)
            Link("beheer.bingr.online", destination: URL(string: "https://beheer.bingr.online")!)
            Link("beheer.tunr.online", destination: URL(string: "https://beheer.tunr.online")!)
            Link("beheer.pasr.nl", destination: URL(string: "https://beheer.pasr.nl")!)
            Link("bekendr.lrvdlinden.app/beheer", destination: URL(string: "https://bekendr.lrvdlinden.app/beheer/")!)
            Link("noodpakket.lrvdlinden.app/beheer", destination: URL(string: "https://noodpakket.lrvdlinden.app/beheer/")!)
            Link("pairr.lrvdlinden.app/beheer", destination: URL(string: "https://pairr.lrvdlinden.app/beheer/")!)
        }
    }
}
#endif
