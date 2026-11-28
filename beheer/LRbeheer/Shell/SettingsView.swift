import SwiftUI

/// Instellingen van LRbeheer zelf. De instellingen van elke omgeving (inloggen, pushsoorten, vergrendeling, Overal
/// uitloggen, ...) staan ongewijzigd in die omgeving, onder hun eigen Instellingen.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system
    @State private var showWhatsNew = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if AppLock.canLock {
                    Toggle(isOn: $model.lockEnabled) {
                        Label(String(format: String(localized: "Vergrendelen met %@"), AppLock.biometryName), systemImage: AppLock.biometryIcon)
                    }
                }
                NavigationLink { NotificationSettingsView() } label: {
                    Label("Meldingen", systemImage: "bell.badge")
                }
                NavigationLink { SharedLoginForm() } label: {
                    Label("Eén inlog voor alle omgevingen", systemImage: "person.badge.key")
                }
            } header: { Text("LRbeheer") } footer: {
                Text("De vergrendeling geldt voor het overzicht, LRvdLinden en PixelForges. Bingr, Tunr, Pasr en P2000 houden hun eigen vergrendeling, in hun eigen Instellingen.")
            }

            Section("Omgevingen") {
                ForEach(BeheerEnvironment.allCases) { env in
                    Button {
                        dismiss()
                        model.switchTo(env)
                    } label: {
                        HStack(spacing: 12) {
                            EnvironmentIcon(env: env, size: 30)
                            Text(verbatim: env.name).foregroundStyle(.primary)
                            Spacer()
                            Text(env.isSignedIn ? "Ingelogd" : "Niet ingelogd").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Weergave") {
                Picker("Weergave", selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Bingr, Tunr en Pasr blijven donker, zoals in de oorspronkelijke apps.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://lrvdlinden.app/privacy.html")!) {
                    Label("Privacyverklaring", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://lrvdlinden.app")!) {
                    Label("Support / contact", systemImage: "questionmark.circle")
                }
                Button { showWhatsNew = true } label: { Label("Wat is nieuw", systemImage: "sparkles") }
                Link(destination: URL(string: "https://lrvdlinden.app/donate")!) {
                    Label("Doneer", systemImage: "heart")
                }
            }

            Section {
                MoreAppsCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: { Text(MoreAppsText.current.section) }

            Section {
                AppInfoFooter()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Instellingen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
        }
        .sheet(isPresented: $showWhatsNew) { WhatsNewView() }
    }
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Bingr: abonnement per account") {
                    Label("Gebruikers: bij elk account staat precies wat het heeft: Gratis, Oude Lifetime, Lifetime (gekocht), Gratis Lifetime gegeven, Maand, Halfjaar of Jaar, met proefperiode, test, einddatum en Stripe of Apple erbij", systemImage: "creditcard")
                    Label("Gebruikers: filter Abonnement op die soorten (ook alle Premium-abonnementen samen) met aantallen", systemImage: "line.3.horizontal.decrease.circle")
                }
                Section("Bingr: sandbox-aankopen en betaaltrechter") {
                    Label("Gebruikers: filter Sandbox en een label Sandbox bij accounts met toegang via een Apple-testaankoop (niet betaald); intrekken bij Abonnement van het account", systemImage: "testtube.2")
                    Label("Omzet › Betalingen controleren: tegel met het aantal accounts met Lifetime via sandbox (tik opent die accounts), actief in 7 dagen en tijdelijke toegang", systemImage: "checkmark.shield")
                    Label("Betaaltrechter per dag voor Apple, Android en web: betaalscherm getoond, koop gestart, gelukt, mislukt en geannuleerd, met de meest voorkomende fouten", systemImage: "chart.bar.doc.horizontal")
                }
                Section("Pasr: Mail") {
                    Label("Nieuw tabblad Mail › Inbox: mails als tickets met filter, zoeken, ongelezen-stip, gesprek met antwoord, interne notitie, status en prioriteit; bijlagen openen en delen; Nu ophalen en de status van de inbox", systemImage: "envelope")
                    Label("Mail › Nieuwe mail: Aan, CC en BCC altijd zichtbaar, elk met meerdere geplakte adressen, teller en markering van ongeldige adressen; merk Pasr of Pasr Zakelijk, onderwerp, Markdown met werkbalk, bijlagen (samen 10 MB), live voorbeeld en testmail", systemImage: "square.and.pencil")
                    Label("Mail › Nieuwsbrief naar Gebruikers of Ondernemers (met aantal), merk, voorbeeld, testmail, versturen met bevestiging en het overzicht van eerdere nieuwsbrieven met voortgang en annuleren", systemImage: "newspaper")
                    Label("Ook op het web: beheer.pasr.nl, tab Mail", systemImage: "safari")
                }
                Section("Pasr: tickets en klantenkaarten") {
                    Label("Ondernemers › Details › Tickets en klantenkaarten: per zaak de gratis events met aangemeld, binnen, wachtlijst en afgemeld", systemImage: "ticket")
                    Label("De klantenkaarten met barcode van de zaak: soort barcode, aantal leden, bezoeken in 30 dagen en de doelen", systemImage: "creditcard")
                    Label("Een event afgelasten (iedereen krijgt een mail en een pushmelding) of een klantenkaart archiveren", systemImage: "xmark.circle")
                    Label("Ook op het web: beheer.pasr.nl, Ondernemers › Details", systemImage: "safari")
                }
                Section("Pasr: Voeg toe aan Pasr") {
                    Label("Ondernemers › stempelkaart en Winkels › winkel: de link pasr.nl/add/… en een voorbeeld van de knop Voeg toe aan Pasr (zwart, wit, nachtblauw), met Kopieer link en Open", systemImage: "plus.rectangle.on.rectangle")
                    Label("Met Pasr opent de link Toevoegen aan Pasr? in de app, anders pasr.nl met de downloadknoppen", systemImage: "link")
                    Label("Ook op het web: beheer.pasr.nl, bij de stempelkaart en in de winkel-editor", systemImage: "safari")
                }
                Section("Pasr: gezamenlijke acties op uitnodiging") {
                    Label("Ondernemers › Details › Acties: bij een gezamenlijke actie Uitnodigingen en deelnemers, met de status (wacht op deelnemers of actief), het minimum en of de actie open is voor de eigen plaats", systemImage: "person.2")
                    Label("Per uitgenodigde zaak de status: uitgenodigd, doet mee, geweigerd of ingetrokken; ook uitnodigingen per e-mail of link", systemImage: "envelope.badge")
                    Label("Een openstaande uitnodiging intrekken of een deelnemer verwijderen; de zaak krijgt een mail en een pushmelding in Pasr Zakelijk", systemImage: "person.crop.circle.badge.minus")
                    Label("Ook op het web: beheer.pasr.nl, Ondernemers › Details", systemImage: "safari")
                }
                Section("Bingr: Betalingen controleren") {
                    Label("Omzet › Betalingen controleren: controleert of er betalingen zijn misgelopen, Apple (verkocht tegenover gekoppelde abonnementen en Lifetime per dag, notificaties, nog niet gekoppeld) en Stripe (betaald in Stripe tegenover wat wij hebben vastgelegd)", systemImage: "checkmark.shield")
                    Label("Uitslag Alles in orde of Aandacht nodig, met de lijst van problemen en de misgelopen betalingen (soort, kort kenmerk, bedrag en tijd)", systemImage: "list.bullet.clipboard")
                    Label("Alleen aantallen en korte kenmerken, nooit e-mailadressen of account-id's", systemImage: "lock")
                    Label("Ook op het web: beheer.bingr.online, tab Omzet", systemImage: "safari")
                }
                Section("Bingr: Verzonden mails") {
                    Label("Nieuw onderdeel Verzonden: welke mails de server heeft verstuurd, met ontvanger, onderwerp, bron, tijd en of de mailserver de mail aannam", systemImage: "paperplane")
                    Label("Filter op resultaat en bron, zoeken op ontvanger of onderwerp en de totalen van 7 dagen", systemImage: "line.3.horizontal.decrease.circle")
                    Label("Alleen ontvanger en onderwerp, nooit de inhoud; nieuwsbrief en mailings staan er niet in", systemImage: "lock")
                    Label("Ook op het web: beheer.bingr.online, tab Verzonden", systemImage: "safari")
                }
                Section("Pasr: tickets als echte eventtickets") {
                    Label("Winkels › ticket: nieuw blok Evenement met titel, merk, soort ticket, toelichting, datum(s), toegangstijden, locatie, plaats, adres, infopagina en tekst-/labelkleur, zoals op beheer.pasr.nl", systemImage: "ticket")
                    Label("Pasr toont tickets daarmee als Apple Wallet-eventticket, en tickets van hetzelfde evenement en dezelfde dag als één groep om door te vegen", systemImage: "rectangle.stack")
                }
                Section("Pasr: acties per zaak en de nieuwe stempel") {
                    Label("Ondernemers › Details: nieuw blok Acties met kortingsbonnen, actiecodes, gezamenlijke acties en vestigingen van de zaak, met aantallen (geen klantgegevens)", systemImage: "tag")
                    Label("Uitzetten vanuit het beheer: kortingsbon uitzetten, actiecode pauzeren, gezamenlijke actie annuleren; de historie blijft bewaard", systemImage: "hand.raised")
                    Label("Stempelkaart-voorbeeld met de officiële Pasr-stempel in de merkkleur van de kaart, zoals in de apps en op pasr.nl", systemImage: "seal")
                }
                Section("Pasr: bericht aan iedereen, met link") {
                    Label("Bericht sturen: nieuwe doelgroep Iedereen met meldingen aan (Pasr, Pasr Zakelijk of beide), ook zonder opt-in voor nieuws; alleen voor belangrijke berichten, geen reclame", systemImage: "megaphone")
                    Label("Kies Alles, Apple of Android, voor elke doelgroep", systemImage: "iphone.gen3")
                    Label("Link (optioneel, alleen https): een tik op de melding opent de link; voorbeeld met de link eronder en de link in de geschiedenis", systemImage: "link")
                    Label("Ook op het web: beheer.pasr.nl, Berichten", systemImage: "safari")
                }
                Section("Pasr: pushmeldingen op Android") {
                    Label("Bericht sturen telt de ontvangers per platform: iOS en Android apart, ook na het versturen", systemImage: "megaphone")
                    Label("Inzichten: Push aan per platform (iOS, Android en Pasr Zakelijk) en of Android-push is ingericht", systemImage: "bell.badge")
                }
                Section("Pasr: iOS en Android") {
                    Label("Overzicht van Pasr: kaart iOS en Android met actieve toestellen per dag per platform (Pasr of Pasr Zakelijk), nieuwe installaties en de versies die in gebruik zijn", systemImage: "iphone.and.arrow.forward")
                    Label("Google Wallet-passen naast Apple Wallet-passen, per dag en totaal", systemImage: "wallet.pass")
                    Label("Accounts per platform: aangemaakt op iOS, Android of het web", systemImage: "person.2")
                    Label("Ook op het web: beheer.pasr.nl, Overzicht en Insights", systemImage: "safari")
                }
                Section("Pasr: ondernemers en stempelkaarten aanmaken") {
                    Label("Ondernemers › Nieuwe ondernemer: zaak meteen goedgekeurd; met een Pasr-account wordt dat eigenaar, anders een eigenaarslink (mailen, kopiëren of opnieuw versturen); zonder e-mail beheer jij de zaak", systemImage: "storefront")
                    Label("Per zaak Bewerken en Nieuwe stempelkaart: live voorbeeld zoals op pasr.nl/zakelijk, Huisstijl ophalen van de website, QR-code, link en flyer, publiceren of offline halen", systemImage: "rectangle.stack.badge.plus")
                    Label("Testklant maken per stempelkaart voor de App Review van Pasr Zakelijk: klantcode als tekst en grote QR-code (PNG of afdrukken), resetten of verwijderen", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Alles wat het beheer doet staat in de log van de zaak (actor beheer); ook op beheer.pasr.nl", systemImage: "list.bullet.rectangle")
                    Label("Accounts: E-mail bevestigen voor accounts zonder bevestigd e-mailadres (bijvoorbeeld review@pasr.nl); bij Nieuwe ondernemer een onbevestigd account bevestigen en eigenaar maken. Wachtwoorden blijven van de gebruiker", systemImage: "checkmark.seal")
                }
                Section("Pasr: ondernemers in detail") {
                    Label("Ondernemers › zaak: instellingen (afkoeltijd, max stempels per scan, vindbaar in Pasr, adres)", systemImage: "slider.horizontal.3")
                    Label("Stempels per dag (30 dagen), medewerkers van de zaak met intrekken, en de log met wie wanneer welke stempel gaf", systemImage: "list.bullet.rectangle")
                    Label("Een zaak uit de lijst in Pasr halen: Vindbaar in Pasr uit", systemImage: "eye.slash")
                    Label("Ook op het web: beheer.pasr.nl, Ondernemers › Details", systemImage: "safari")
                }
                Section("Pasr: berichten en ondernemers") {
                    Label("Nieuw onderdeel Berichten: pushbericht aan iedereen met Nieuws over mijn kaarten, met doelgroep (iedereen, heeft kaart van een winkel, nieuwe gebruikers, inactief 30 dagen), voorbeeld, aantal ontvangers en geschiedenis", systemImage: "megaphone")
                    Label("Nieuw onderdeel Ondernemers: zaken van pasr.nl/zakelijk goedkeuren of blokkeren, met hun stempelkaarten, leden en stempels", systemImage: "rectangle.stack.badge.person.crop")
                    Label("Pushmelding bij een nieuwe ondernemer (schakelaar Winkel aangevraagd of nieuwe ondernemer)", systemImage: "bell.badge")
                    Label("Gids: verjaardagsvoordeel per winkel", systemImage: "gift")
                    Label("Ook op het web: beheer.pasr.nl, tabs Berichten en Ondernemers", systemImage: "safari")
                }
                Section("Pasr: gids en kaartontwerp") {
                    Label("Winkels › winkel: gids bewerken, cadeaubon-gids bij cadeaukaarten en programmagids bij klantenkaarten", systemImage: "book.pages")
                    Label("Kaartontwerp van een cadeaukaart: foto of bestand kiezen, automatisch bijgesneden tot kaartverhouding", systemImage: "photo.on.rectangle")
                    Label("Winkellijst: zoeken op naam, website, categorie of alias, met telling klantenkaarten en cadeaukaarten", systemImage: "magnifyingglass")
                    Label("Vlot met honderden winkels: logo's en kaartontwerpen laden pas als ze in beeld komen", systemImage: "bolt.fill")
                }
                Section("A-Alerts: eigen server") {
                    Label("Het A-Alerts-beheer praat nu met api.a-alerts.nl; wijzigingen gaan tot de overstap ook naar de oude Worker", systemImage: "server.rack")
                    Label("Nieuw tabblad Bronnen: elke bron van de server met staat en laatste ophaalronde, de database en hoe compleet de P2000-meldingen zijn (capcodes, prioriteit, dienst, plaats, regio, straat, opschaling)", systemImage: "antenna.radiowaves.left.and.right")
                    Label("Dashboard: P2000 komt van de Koyeb-stream; de oude melding HTTP 403 van p2000.page is weg", systemImage: "checkmark.seal")
                }
                Section("Bingr: Premium") {
                    Label("Nieuw onderdeel Premium (Instellingen van Bingr): stand en overzicht met MRR, proeven, opzeggingen, Apple en Stripe apart", systemImage: "crown")
                    Label("Schakelaars met uitleg en bevestiging, prijzen, Stripe-producten aanmaken (droog en echt) en testaccounts", systemImage: "switch.2")
                    Label("Premium testen in de details van een account, en het blok Abonnementen op de omzetpagina", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Concept-mailing voor bestaande gratis accounts: in Eigen mailing zetten, niets wordt verstuurd", systemImage: "envelope")
                    Label("Ook op het web: beheer.bingr.online, tab Premium", systemImage: "safari")
                }
                Section("Bingr: Crashes") {
                    Label("Nieuw onderdeel Crashes: eigen crashrapporten van de Bingr-apps en de webspeler, gegroepeerd met aantal, platforms, builds en eerst en laatst gezien", systemImage: "exclamationmark.triangle")
                    Label("Filter op status, platform en build; details met de stacks", systemImage: "line.3.horizontal.decrease.circle")
                    Label("Markeer een crash als opgelost in build N; komt hij daarna terug, dan staat hij op Teruggekomen", systemImage: "checkmark.seal")
                    Label("Pushmelding bij een nieuwe of teruggekomen crash, aan of uit in de Instellingen van Bingr", systemImage: "bell.badge")
                    Label("Ook op het web: beheer.bingr.online, tab Crashes", systemImage: "safari")
                }
                Section("Openen") {
                    Label("LRbeheer start altijd in het overzicht: kies zelf waar je heen gaat (de laatstgebruikte omgeving is gemarkeerd)", systemImage: "square.grid.2x2")
                }
                Section("LRvdLinden") {
                    Label("Publiceren voegt nu per veld samen: wat de automatische check intussen bijwerkte (versies, beoordelingen, datum toegevoegd) blijft behouden", systemImage: "arrow.triangle.merge")
                    Label("LRvdLinden opent altijd in het overzicht van lrvdlinden.app, niet meteen in een app", systemImage: "rectangle.grid.1x2")
                    Label("Bij een nieuwe app kies je meteen of hij alleen Nederlands is: dan worden er geen Engelse teksten gemaakt", systemImage: "character.bubble")
                    Label("Promo-banners voor Nieuw en onderweg komen automatisch uit de content-repo (marketingbeeld), tenzij je zelf een banner uploadt", systemImage: "photo.on.rectangle")
                    Label("Nieuwe app toevoegen vanaf een link: App Store, Homey App Store, TestFlight of een website. Naam, icoon, teksten in NL en EN en (bij een store-app) versies en beoordelingen worden automatisch ingevuld", systemImage: "link.badge.plus")
                    Label("Nieuwe apps krijgen meteen een eigen pagina op lrvdlinden.app (/app/… en /homey/…, ook in het Engels onder /en/)", systemImage: "doc.richtext")
                    Label("Nieuw vinkje Alleen Nederlands per app: die app staat dan niet op de Engelse versie van lrvdlinden.app (NL-label in de lijst)", systemImage: "globe.europe.africa")
                }
                Section("112Heli") {
                    Label("Nieuwe omgeving 112Heli, met dezelfde beheer-inlog", systemImage: "app.badge")
                    Label("Overzicht: toestellen in de lucht, vluchten per dag, grote inzetten, apparaten, zones en de status van de server", systemImage: "gauge.with.dots.needle.67percent")
                    Label("Alle toestellen met laatst gezien en vluchten van 30 dagen, met zoeken", systemImage: "airplane")
                    Label("Meldingen uit de app (toestel klopt niet of ontbreekt): opgelost, bekeken of verwijderen", systemImage: "exclamationmark.bubble")
                    Label("Eigen pushbericht naar alle gebruikers of per soort toestel, met bereik en geschiedenis", systemImage: "paperplane")
                    Label("Pushlog: elke pushmelding van de laatste 7 dagen met het antwoord van Apple (aangenomen of geweigerd)", systemImage: "list.bullet.rectangle")
                    Label("Ook op het web: 112heli.lrvdlinden.app/beheer", systemImage: "safari")
                    Label("Mac: vanaf de tiende omgeving wissel je met ⌥⌘1, ⌥⌘2 …", systemImage: "command")
                    Label("Downloads van 112Heli uit App Store Connect: per apparaat (ook Mac en Apple TV) en per dag", systemImage: "arrow.down.circle")
                }
                Section("Pairr") {
                    Label("Nieuwe omgeving Pairr, met dezelfde beheer-inlog", systemImage: "app.badge")
                    Label("Downloads op iPhone, iPad en Mac uit App Store Connect, met grafiek per dag", systemImage: "arrow.down.circle")
                    Label("Omzet van Pairr: opbrengst na Apple per dag en per valuta, omgerekend naar euro", systemImage: "eurosign.circle")
                    Label("Open meldingen van gebruikers (GitHub Issues), tik om ze te openen", systemImage: "exclamationmark.bubble")
                    Label("Ook op het web: pairr.lrvdlinden.app/beheer", systemImage: "safari")
                }
                Section("Noodpakket") {
                    Label("Nieuwe omgeving Noodpakket, met dezelfde beheer-inlog", systemImage: "app.badge")
                    Label("Downloads: iPhone en iPad uit App Store Connect, Android uit GitHub Releases, met grafiek per dag", systemImage: "arrow.down.circle")
                    Label("Android-builds: status van de laatste builds en de nieuwste release", systemImage: "hammer")
                    Label("Berichten aan gebruikers: pushmelding op iPhone en iPad, Android haalt ze zelf op", systemImage: "paperplane")
                    Label("Kies apparaten en taal, bekijk het voorbeeld en stuur eerst een test naar LRbeheer", systemImage: "iphone.radiowaves.left.and.right")
                    Label("Verstuurde berichten met bereik; intrekken of opnieuw gebruiken", systemImage: "arrow.uturn.backward")
                    Label("Ook op het web: noodpakket.lrvdlinden.app/beheer", systemImage: "safari")
                    Label("Accounts en gezinnen van Noodpakket: aantallen, gedeelde gezinnen en uitnodigingen", systemImage: "person.2")
                }
                Section("A-Alerts: Widgets") {
                    Label("Nieuw onderdeel Widgets: kopieer de scriptcode van de live kaart en Verkeer nu voor andere websites, zie op welke sites ze staan met het aantal weergaven, en blokkeer een site", systemImage: "puzzlepiece.extension")
                    Label("Alleen nog de scriptcode: die past zich vanzelf aan en websites kunnen de widget niet aanpassen", systemImage: "chevron.left.forwardslash.chevron.right")
                    Label("Nieuwe widget Weerwaarschuwing, en elke widget een eigen script (kaart.js, verkeer.js, weer.js) met een eigen kopieerknop", systemImage: "cloud.sun.rain")
                }
                Section("A-Alerts: Verkeer") {
                    Label("Bij A-Alerts-bronnen staat nu ook Verkeer (NDW, Koyeb): je ziet of de verkeersservice werkt en krijgt een pushmelding als hij langer dan 30 minuten geen gegevens geeft", systemImage: "car.side")
                }
                Section("A-Alerts: Nieuws") {
                    Label("Zet per weerartikel, Burgernet, AMBER Alert, NL-Alert en Vermist Kind zelf aan of het een liveblog is: dan staat er \"Liveblog\" bij en LIVEBLOG op de afbeelding (standaard uit). NL-Alert krijgt nu ook een artikel", systemImage: "dot.radiowaves.left.and.right")
                    Label("Nieuw tabblad Nieuws: politieberichten over Apeldoorn en omgeving, weerartikelen en liveblogs bij Burgernet, AMBER Alert en Vermist Kind Alert", systemImage: "newspaper")
                    Label("Vul een liveblog aan met tekst, foto en link, met een pushmelding naar wie die bron volgt; wijzig of verwijder eigen berichten", systemImage: "plus.bubble")
                    Label("Verberg een bericht, kies een eigen afbeelding, en stel per onderwerp de standaardafbeelding voor politieberichten in", systemImage: "photo.on.rectangle")
                    Label("Ook artikelen van 112 Nieuws per plaats (titel en intro met link), met eigen filter", systemImage: "light.beacon.max")
                }
                Section("A-Alerts: AMBER Alert en Vermist Kind Alert") {
                    Label("Twee nieuwe soorten waarschuwingen (vermiste kinderen, van de politie via Burgernet) in de lijst, het filter en de cijfers per bron", systemImage: "figure.child")
                    Label("Status van de nieuwe bron en hoeveel toestellen ze willen ontvangen; verbergen of beëindigen werkt zoals bij de andere waarschuwingen", systemImage: "antenna.radiowaves.left.and.right")
                }
                Section("A-Alerts: toestel zoeken") {
                    Label("Zoek een gebruiker op met het toestel-ID uit de app (Instellingen, onder Disclaimer): toestel, appversie en pushinstellingen", systemImage: "magnifyingglass")
                    Label("Stuur dat toestel meteen een testmelding", systemImage: "bell.badge")
                }
                Section("A-Alerts: gemelde fouten") {
                    Label("Gemelde fouten: meldingen die gebruikers als onjuist aangeven, met reden, toelichting en de juiste plek", systemImage: "exclamationmark.bubble")
                    Label("Afhandelen, heropenen of de melding meteen bewerken; een pushmelding bij elke nieuwe melding", systemImage: "checkmark.circle")
                }
                Section("A-Alerts: hulp in de app") {
                    Label("Teksten › Hulp en veelgestelde vragen: de hulppagina van de app en a-alerts.nl/hulp aanpassen", systemImage: "questionmark.circle")
                }
                Section("Pasr: pushmeldingen") {
                    Label("Meldingen van Pasr (nieuwe accounts, winkelaanvragen) komen nu ook in LRbeheer aan", systemImage: "bell.badge.fill")
                }
                Section("Pasr: saldo-pagina's") {
                    Label("Winkels › Saldo: per winkel de pagina waar je het tegoed van een cadeaukaart nakijkt", systemImage: "eurosign.circle")
                    Label("Alle cadeaukaarten uit de app staan klaar: alleen het adres invullen, met een zoekknop", systemImage: "list.bullet.rectangle")
                    Label("Werkt ook voor winkels die al in de app zitten, zonder app-update", systemImage: "arrow.down.app")
                }
                Section("Pasr: review-account") {
                    Label("Accounts › Review-account maken: bevestigd account voor Apple App Review met voorbeeldkaarten en een gedeelde Pasr", systemImage: "person.badge.key")
                    Label("Zelf een wachtwoord kiezen of een sterk wachtwoord laten maken; de server bewaart het niet", systemImage: "key.fill")
                }
                Section("Pasr: winkels zonder update") {
                    Label("Tabblad Winkels: aanvragen uit de app, gebundeld per winkel, ook cadeaukaarten en vouchers", systemImage: "storefront")
                    Label("Website opzoeken: logo en merkkleuren automatisch, of zelf een logo kiezen", systemImage: "wand.and.stars")
                    Label("Publiceren zonder app-update; aanvragen worden gesloten en de aanvragers krijgen een pushmelding", systemImage: "paperplane")
                    Label("Pushmelding bij een nieuwe winkelaanvraag (schakelaar Winkel aangevraagd)", systemImage: "bell.badge")
                }
                Section("Pasr: delen") {
                    Label("Kerncijfers Gedeelde Pasrs (met personen en kaarten) en Tijdelijk gedeeld (nu geldig)", systemImage: "person.2.fill")
                    Label("Kaart Delen: uitnodigingen, gedeelde kaarten, keren geopend en eerder gestopt", systemImage: "clock.badge.checkmark")
                    Label("Insights: reeksen Gedeelde Pasrs en Tijdelijk gedeeld; per account het aantal gedeelde Pasrs", systemImage: "chart.bar.xaxis")
                }
                Section("Bingr: omzet van Apple") {
                    Label("Omzet: website (Stripe) en Apple (App Store) apart, met bruto, inhouding, netto opbrengst, aantal en terugbetaald", systemImage: "chart.bar.doc.horizontal")
                    Label("Apple-cijfers uit App Store Connect, met Apple bijgewerkt t/m en gekoppelde aankopen", systemImage: "apple.logo")
                    Label("Reeksen Website en Apple in de grafiek en de knop Apple-omzet bijwerken", systemImage: "arrow.clockwise")
                    Label("Apple-commissie en vaste koersen instellen", systemImage: "eurosign.circle")
                }
                Section("Bingr: nieuwe accounts eerst kopen") {
                    Label("Lifetime-only: Nieuwe accounts eerst kopen, apart voor web en Android en voor de Apple-apps, met bevestiging", systemImage: "cart.badge.plus")
                    Label("Waarschuwing als de datum voor de Apple-apps staat terwijl de Apple-koopknop uit staat", systemImage: "exclamationmark.triangle")
                }
                Section("Bekendr") {
                    Label("Nieuwe omgeving Bekendr, met dezelfde beheer-inlog", systemImage: "app.badge")
                    Label("Downloads per apparaat: iPhone, iPad en Mac uit App Store Connect", systemImage: "iphone")
                    Label("Android: downloads van de APK, totaal en per versie", systemImage: "arrow.down.circle")
                    Label("Grafiek met downloads per dag over 30 dagen", systemImage: "chart.bar.xaxis")
                    Label("Ook op het web: bekendr.lrvdlinden.app/beheer", systemImage: "safari")
                    Label("Feedback uit de app: wat er niet klopt aan een bekendmaking, met reden en toelichting", systemImage: "exclamationmark.bubble")
                    Label("Feedback afhandelen of verwijderen; ook op bekendr.lrvdlinden.app/beheer", systemImage: "checkmark.circle")
                }
                Section("Bingr: Lifetime-only") {
                    Label("Instellingen → Lifetime-only: aankondiging, overgangsdatum, korting, proefperiode, Apple-koopknop en EU-link, met bevestiging", systemImage: "star.circle")
                    Label("Kortingscodes genereren (droog en echt) met de totalen", systemImage: "ticket")
                    Label("Mail Bingr wordt Lifetime testen en versturen, en de herinnering", systemImage: "envelope")
                    Label("Niet geclaimde aankopen, en een aankoop handmatig aan een account koppelen", systemImage: "link")
                    Label("Gebruikers: kortingscode en status bij het account", systemImage: "person.text.rectangle")
                    Label("Omzet: per aanbieder (website via Stripe en Apple)", systemImage: "eurosign.circle")
                }
                Section("A-Alerts: status") {
                    Label("Nieuw tabblad Status: alle onderdelen van a-alerts.nl/status met uptime en foutmelding", systemImage: "waveform.path.ecg")
                    Label("Storing of gepland onderhoud melden, bijwerken en afronden; staat direct op de statuspagina en in de apps", systemImage: "exclamationmark.bubble")
                    Label("Pushmelding zodra iets afwijkt van normaal en weer als het hersteld is (schakelaar Storingen en afwijkingen)", systemImage: "bell.badge")
                }
                Section("A-Alerts") {
                    Label("P2000 Apeldoorn heet nu A-Alerts, met het nieuwe icoon", systemImage: "app.badge")
                    Label("Waarschuwingen: NL-Alert, Burgernet en KNMI bekijken, verbergen of handmatig beëindigen", systemImage: "exclamationmark.triangle")
                    Label("Dashboard: status van de bronnen en helikopters in de lucht", systemImage: "antenna.radiowaves.left.and.right")
                    Label("Dashboard: gebruik van de notificatieprofielen", systemImage: "person.2.badge.gearshape")
                    Label("Pushmelding bij een storing van NL-Alert, Burgernet of KNMI (met schakelaar)", systemImage: "bell.badge")
                    Label("A-Alerts gebruikt dezelfde iconen als de app", systemImage: "app.badge.checkmark")
                    Label("A-Alerts: nieuwe tekst Cookies bewerken, links naar a-alerts.nl", systemImage: "checkmark.shield")
                    Label("A-Alerts: nieuwe iconen voor NL-Alert en KNMI, net als in de app", systemImage: "photo")
                    Label("A-Alerts: downloads van de Android-app (totaal, 30 dagen, per dag en per versie)", systemImage: "arrow.down.circle")
                    Label("A-Alerts: Android-installaties, push-toestellen en status van Firebase", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
                Section(String(format: String(localized: "Versie %@"), Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")) {
                    Label("Eén app voor LRvdLinden, PixelForges, Bingr, Tunr, Pasr en P2000 Apeldoorn", systemImage: "square.grid.2x2")
                    Label("Direct wisselen tussen omgevingen bovenin het scherm", systemImage: "arrow.left.arrow.right")
                    Label("Alle functies van BingrBeheer, BeheerTunr, PasrBeheer en P2000Beheer", systemImage: "checkmark.seal")
                    Label("Native beheer van lrvdlinden.app en pixelforges.nl", systemImage: "globe")
                    Label("Echte Mac-app met menubalk (⌘1…⌘7 wisselt van omgeving)", systemImage: "macbook")
                    Label("Pushmeldingen van alle omgevingen; een tik opent de juiste omgeving", systemImage: "bell.badge")
                }
            }
            .navigationTitle("Wat is nieuw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Meldingen per omgeving: één systeemtoestemming, daarna per omgeving waar de schakelaars staan.
struct NotificationSettingsView: View {
    @State private var central = CentralPush.shared
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                switch central.permission {
                case .allowed:
                    Label("Meldingen staan aan", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                case .denied:
                    Label("Meldingen staan uit in de systeeminstellingen", systemImage: "bell.slash")
                    Button("Open Instellingen") { Task { await central.requestPermission() } }
                default:
                    Button { Task { await central.requestPermission() } } label: { Label("Meldingen aanzetten", systemImage: "bell") }
                }
            } footer: {
                Text("Meldingen komen van alle omgevingen binnen, welke omgeving er ook open is. Een tik opent de juiste omgeving en het juiste onderdeel.")
            }

            Section {
                envRow(.bingr, "Eigen pushsysteem van BingrBeheer: tickets, antwoorden, builds en status. Per soort in Bingr → Instellingen.")
                envRow(.pasr, "Eigen pushsysteem van PasrBeheer. Per soort in Pasr → Instellingen.")
                envRow(.p2000, "Eigen pushsysteem van P2000Beheer: storingen van de feed en tests. Aan/uit in P2000 → Instellingen.")
            } header: { Text("Bestaande meldingen") }

            Section {
                if !central.canRegister {
                    Label("Log in bij Tunr om deze meldingen aan te zetten (het centrale pushsysteem gebruikt de beheer-inlog van Tunr).",
                          systemImage: "info.circle")
                        .font(.footnote)
                } else {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(central.registered ? "Aangemeld" : "Niet aangemeld").foregroundStyle(.secondary)
                    }
                    if let e = central.lastError { Text(e).font(.footnote).foregroundStyle(Theme.bad) }
                }
                @Bindable var c = central
                Group {
                    Toggle(isOn: $c.prefs.lrvdlindenStore) { envLabel(.lrvdlinden, "Store-check: nieuwe apps en updates") }
                    Toggle(isOn: $c.prefs.lrvdlindenDeploy) { envLabel(.lrvdlinden, "Site gepubliceerd of deploy mislukt") }
                    Toggle(isOn: $c.prefs.pixelforgesDeploy) { envLabel(.pixelforges, "Site gepubliceerd of deploy mislukt") }
                    Toggle(isOn: $c.prefs.pixelforgesContent) { envLabel(.pixelforges, "Inhoud gewijzigd") }
                    Toggle(isOn: $c.prefs.pixelforgesContact) { envLabel(.pixelforges, "Nieuwe aanvraag via het contactformulier") }
                    Toggle(isOn: $c.prefs.tunrInstalls) { envLabel(.tunr, "Nieuwe installaties (dagelijks overzicht)") }
                    Toggle(isOn: $c.prefs.tunrPresskit) { envLabel(.tunr, "Perskit gedownload") }
                }
                .disabled(!central.canRegister || central.permission != .allowed)
                Button {
                    testing = true
                    Task {
                        defer { testing = false }
                        do { try await central.sendTest(); testResult = String(localized: "Testmelding verstuurd") }
                        catch { testResult = error.localizedDescription }
                    }
                } label: { Label(testing ? "Bezig…" : "Stuur een testmelding", systemImage: "paperplane") }
                .disabled(!central.canRegister || central.permission != .allowed || testing)
                if let t = testResult { Text(t).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Nieuwe meldingen (centraal)") } footer: {
                Text("LRvdLinden, PixelForges en Tunr via de centrale pushfunctie van LRbeheer. De schakelaars gelden voor dit apparaat.")
            }
        }
        .navigationTitle("Meldingen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await central.refresh()
            central.sync(force: false)
        }
    }

    private func envRow(_ env: BeheerEnvironment, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            EnvironmentIcon(env: env, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: env.name).font(.body.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
                if !env.isSignedIn { Text("Log in bij deze omgeving om meldingen te krijgen.").font(.caption).foregroundStyle(Theme.build) }
            }
        }
    }

    private func envLabel(_ env: BeheerEnvironment, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            EnvironmentIcon(env: env, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: env.name).font(.caption).foregroundStyle(.secondary)
                Text(text)
            }
        }
    }
}
