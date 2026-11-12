# LRbeheer

Eén iOS-/iPadOS-app waarmee je al je platformen beheert: **LRvdLinden, PixelForges, Bingr, Tunr, Pasr en P2000 Apeldoorn**.
Elke omgeving is de volledige beheerapp of het volledige webbeheer, niet een vereenvoudigde versie.

| | |
| --- | --- |
| Appnaam | LRbeheer |
| Bundle-id | `app.lrvdlinden.lrbeheer` (widgets: `app.lrvdlinden.lrbeheer.widget`) |
| Versie / build | 1.0.0 (1) |
| Platform | iPhone en iPad (iOS/iPadOS 18+; P2000Beheer vroeg al iOS 18) en een echte Mac-app via Mac Catalyst (macOS 15+), met menubalk, zelfde bundle-id (universal purchase) |
| Team | EU3UY476T6, automatisch ondertekenen |
| URL-schema | `lrbeheer://<omgeving>/…` |

## Openen en bouwen

1. Open `LRbeheer.xcodeproj` in **Xcode 16 of nieuwer** (het project gebruikt gesynchroniseerde mappen).
2. Kies het scheme **LRbeheer** en een iPhone, iPad, simulator of **My Mac (Mac Catalyst)**. Team en signing staan al ingevuld.
3. Eerste keer op een echt toestel: Xcode maakt de App ID `app.lrvdlinden.lrbeheer` met de capabilities
   *Push Notifications* en *Keychain Sharing* (staat in `Config/LRbeheer.entitlements`). Bij *Signing & Capabilities*
   staat dan niets rood.
4. Build & run.

> **Niet gebouwd in deze omgeving.** Het project is gemaakt op een Linux-machine zonder Xcode. De Swift-bestanden zijn
> wel op syntaxis gecontroleerd, het Xcode-project op geldige verwijzingen en de serverlogica met tests, maar de eerste
> echte compilatie gebeurt bij jou. Krijg je compileerfouten, stuur ze door; het zijn dan kleine, lokale correcties.

## Opbouw

```
beheer/
├── LRbeheer.xcodeproj           gegenereerd door tools/make_project.py
├── LRbeheer/                    de app zelf
│   ├── App/                     @main, AppModel (actieve omgeving, deeplinks, push-routing), alle omgevingen
│   ├── Shell/                   splash, overzicht, omgevingskiezer, vergrendeling, instellingen, meldingen
│   ├── Push/                    één AppDelegate voor alle omgevingen + centraal pushsysteem
│   ├── Environments/
│   │   ├── LRvdLinden/          native beheer van lrvdlinden.app (alles van site/beheer.html)
│   │   ├── PixelForges/         native beheer van pixelforges.nl (alles van site/beheer.html)
│   │   └── Shared/              site-client, geordende JSON, concepten, inloggen, afbeeldingen
│   ├── Core/                    huisstijl, MoreAppsCard, AppInfoFooter, review-prompt, Keychain
│   └── Resources/               Assets (icoon, omgevingen), Bingr/Tunr/Pasr/P2000.xcassets, teksten nl+en, privacy
├── Modules/                     de vier bestaande beheerapps, elk als framework
│   ├── BingrKit/   Sources/ = ios/BingrBeheer + ios/Shared van bingr-beheer     Bridge/ = koppeling met LRbeheer
│   ├── TunrKit/    Sources/ = apple/Shared van tunr-beheer
│   ├── PasrKit/    Sources/ = beheer/apple/PasrBeheer van app.lrvdlinden.pasr
│   └── P2000Kit/   Sources/ = beheer/P2000Beheer van p2000-apeldoorn
├── Widgets/BingrWidgets/        de widgets van BingrBeheer (status, support, overzicht)
├── Config/                      Info.plist, entitlements
├── server/                      centrale pushfunctie + patches voor de bestaande backends (zie server/README.md)
├── Design/                      app-icoon (SVG/PNG)
└── tools/                       import_modules.py, make_project.py, make_icon.py, make_strings.py
```

### Waarom frameworks

Elke bestaande beheerapp heeft typen met dezelfde naam (`Session`, `AdminAPI`, `RootView`, `LoginView`, `Keychain`, …).
Door elke app een eigen framework (eigen Swift-module) te geven, blijft hun code **vrijwel letterlijk** hetzelfde en
botst er niets. Alleen een klein, openbaar `…Environment`-type per module (`Modules/*/Bridge`) doet wat vroeger de
`@main`-app deed: één sessie, de root-view, pushregistratie en deeplinks.

**Bron van waarheid.** Sinds 6 november 2026 wordt het beheer van alle apps **hier** bijgewerkt, in
`Modules/<App>Kit/Sources/`. Zolang de losse beheerapps (bingr-beheer/ios, tunr-beheer/apple,
app.lrvdlinden.pasr/beheer/apple, p2000-apeldoorn/beheer) nog in gebruik zijn, krijgen die dezelfde wijziging met de
hand. Het web-beheer van elke omgeving blijft bestaan en wordt bij elke nieuwe functie ook bijgewerkt; alleen de
app is verhuisd. Werkafspraken: `CLAUDE.md` en de skill `/beheer`. De serverkant (API's, Edge Functions, worker)
blijft in die repo's; LRbeheer gebruikt die direct.

`tools/import_modules.py` was voor de eerste overname en staat nu op slot: het zou wijzigingen hier overschrijven. Alleen
met `--overwrite` draait het nog. `Modules/IMPORT.json` toont welke bestanden oorspronkelijk zijn overgenomen.

### Wat er aan de bestaande code is aangepast (en waarom)

Alleen wat nodig is om vier apps in één app te laten draaien; het script doet het automatisch en stopt als een
vervanging niet meer past.

| Aanpassing | Waar | Waarom |
| --- | --- | --- |
| `@main` weg | de vier App-structs | een app heeft één ingang; de structs blijven als code staan |
| `UserDefaults.standard` → `UserDefaults.module`, `@AppStorage(…, store: .module)` | alle vier | eigen suite per omgeving; anders botsen sleutels als `push.device_id`, `push.registration` en `lockEnabled` tussen Bingr en Pasr |
| widget-sleutelhangergroep `…bingr.beheer.shared` → `app.lrvdlinden.lrbeheer.shared` | `Shared/WidgetShared.swift` | de groep hoort bij de app-id |
| `L()` leest tabel `Tunr` | Tunr `Core/Localization.swift` | LRbeheer heeft zelf `Localizable.xcstrings`; Tunr houdt zijn nl/en-teksten (`Tunr.strings`) |
| P2000 zet de delegate van het meldingencentrum niet meer zelf | `PushRegistrar.start()` | LRbeheer verdeelt tikken op meldingen over alle omgevingen |

Al het andere (schermen, API-koppelingen, inloggen, sessies, vergrendeling, pushregistratie, instellingen) is de
originele code.

## Gebruik

- **Splash** (±1 s, geen netwerk) → **vergrendeling** met Face ID (Instellingen → *Vergrendelen met Face ID*) →
  **overzicht** met de omgevingen in vaste volgorde: LRvdLinden, PixelForges, Bingr, Tunr, Pasr, P2000 Apeldoorn, Bekendr,
  Noodpakket, Pairr, elk met eigen logo, of je ingelogd bent en welke het laatst gebruikt is.
- **Wisselen**: bovenin elke omgeving staat de omgevingskiezer (logo + naam + ⌄, en op brede schermen de andere logo's).
  Eén tik wisselt direct, zonder terug naar het overzicht. De actieve omgeving is altijd zichtbaar (naam, logo en een
  lijn in de kleur van de omgeving).
- **Laatst gebruikt**: standaard opent LRbeheer de laatstgebruikte omgeving (uit te zetten in Instellingen).
- **Eén inlog**: overzicht → sleutel-icoon, of Instellingen → *Eén inlog voor alle omgevingen*. Eén keer gebruikersnaam
  en wachtwoord (`BEHEER_APP_USER` / `BEHEER_APP_PASSWORD` uit app.lrvdlinden.secrets, op de servers gezet met de workflow
  *Beheer-inlog verdelen*, zie `server/README.md`). LRbeheer logt daarmee in bij alle zes en logt stil opnieuw in als een
  sessie verloopt. De inlog staat alleen in de sleutelhanger van het toestel.
- **Inloggen per omgeving** blijft ook kunnen, met de bestaande inlogschermen: Bingr/Tunr/Pasr/P2000 met hun eigen beheer-inlog (zelfde
  functies en tokens als de losse apps), LRvdLinden en PixelForges met dezelfde gebruikersnaam en hetzelfde wachtwoord als
  hun `beheer.html` (opgeslagen in de sleutelhanger). Wisselen logt nergens uit.
- **Vergrendeling**: Bingr, Tunr, Pasr en P2000 houden hun eigen Face ID-vergrendeling en schakelaar; LRbeheer zelf
  vergrendelt het overzicht, LRvdLinden en PixelForges.

## Pushmeldingen

- Eén keer toestemming (Instellingen → Meldingen, of de eigen vraag van Bingr/Pasr/P2000 na het inloggen).
- LRbeheer geeft het APNs-token aan **elke** omgeving met een eigen pushsysteem (Bingr, Pasr, P2000; elk registreert alleen
  als je daar bent ingelogd, met de bestaande registratie-acties) en aan het **centrale** systeem (LRvdLinden,
  PixelForges, Tunr).
- Meldingen komen binnen van alle omgevingen, ook als een andere omgeving open is of de app op de achtergrond draait
  (`remote-notification`), en worden ook getoond als de app open is.
- Een tik opent de juiste omgeving en het juiste onderdeel: Bingr en Pasr via hun eigen links (`bingrbeheer://support/1001`,
  `pasrbeheer://overview`), de rest via `lrenv`/`lrbeheer://…`.
- Instellingen per omgeving: Bingr en Pasr per soort in hun eigen Instellingen (ongewijzigd), P2000 aan/uit in zijn
  Instellingen, LRvdLinden/PixelForges/Tunr per soort in LRbeheer → Instellingen → Meldingen.
- **Nodig op de server** (zie `server/README.md`): de centrale functie `lrbeheer` deployen in het Tunr-project en de vier
  kleine patches toepassen, zodat Bingr, Pasr en P2000 ook naar de bundle-id van LRbeheer kunnen sturen. Zonder die stap
  werkt alles behalve het ontvangen van meldingen.

## Functievergelijking per oorspronkelijke app

### BingrBeheer → Bingr

| Onderdeel | In LRbeheer |
| --- | --- |
| Inloggen, token 12 uur, Overal uitloggen, Face ID-vergrendeling | ✓ originele code |
| Overzicht: instelbaar widget-dashboard (S/M/L, slepen, galerij), Nu kijken | ✓ |
| Insights (grafieken, crosshair, CSV) | ✓ |
| Omzet (Stripe, btw, kosten, CSV, live/test) | ✓ |
| Gebruikers: zoeken, naam wijzigen, e-mail tonen, blokkeren/opheffen, verwijderen, nieuwsbrief per account | ✓ |
| Support: tickets, gesprek, antwoorden, diagnose, badge | ✓ |
| Pushmeldingen versturen, pushabonnees, geschiedenis, releasemelding per build | ✓ |
| Nieuwsbrief, welkomstmail, eigen mailing (opstellen, voorbeeld, test, versturen, annuleren) | ✓ |
| Server, Status (monitors, meldingen, onderhoud), Downloads (builds, notities, releases) | ✓ |
| Beheer-pushmeldingen (tickets, antwoorden, builds, status) + schakelaars + testmelding | ✓ originele registratie; ontvangen na `server/patches` |
| Widgets: servicestatus, support, overzicht | ✓ widget-extensie van LRbeheer |
| Deeplinks `bingrbeheer://…` uit widgets en meldingen | ✓ |
| Mac (Catalyst) met menubalk | ✓ Mac-app van LRbeheer (Catalyst), menu Omgeving met ⌘1…⌘7 |
| **Lifetime-only** (build 167 van de server, ook in BingrBeheer build 47 en het web-beheer): instellingen met bevestiging, kortingscodes (genereren, totalen), mail en herinnering, niet geclaimde aankopen en Aankoop koppelen, code per account, omzet per aanbieder (Stripe en Apple) | ✓ (Instellingen → Lifetime-only) |
| **Omzet: Apple (App Store Connect)** (ook in BingrBeheer build 49 en het web-beheer): Website (Stripe) en Apple (App Store) apart met bruto, inhouding, netto opbrengst, aantal en terugbetaald, en het totaal; Apple bijgewerkt t/m, gekoppelde Apple-aankopen, reeksen Website en Apple, Apple-omzet bijwerken (bereik) en commissie en vaste koersen | ✓ (Omzet) |
| **Nieuwe accounts eerst kopen** (build 168 van de server, ook in BingrBeheer build 48 en het web-beheer): twee datums in Lifetime-only, web en Android (`new_paid_from`) en Apple-apps (`new_paid_from_apple`), met bevestiging en een waarschuwing als de Apple-koopknop uit staat | ✓ (Instellingen → Lifetime-only) |

### BeheerTunr → Tunr

| Onderdeel | In LRbeheer |
| --- | --- |
| "Nog niet ingericht", inloggen, Overal uitloggen, vergrendeling na 5 min | ✓ originele code |
| Overzicht (statistieken per periode, Insights-grafiek, perskit) | ✓ |
| Downloads (builds, kortgeldige links) | ✓ |
| Instellingen (nl/en-teksten) | ✓ (`Tunr.strings`) |
| Pushmeldingen | **nieuw**: installaties en perskit via de centrale functie |
| Mac (native) met menubalk | Mac-app van LRbeheer (Catalyst) met eigen menubalk; de Tunr-specifieke menu-items (⌘R) niet |

### PasrBeheer → Pasr

| Onderdeel | In LRbeheer |
| --- | --- |
| Inloggen, Overal uitloggen, vergrendeling | ✓ originele code |
| Overzicht, Insights (bronnen, periode), Accounts | ✓ |
| Delen: Gedeelde Pasrs en Tijdelijk gedeeld (kerncijfers, kaart Delen, Insights-reeksen, per account) | ✓ (ook in web-beheer en PasrBeheer build 4) |
| Winkels: aanvragen, website opzoeken, kaart maken, publiceren zonder update met push, afwijzen, offline halen | ✓ (ook in web-beheer en PasrBeheer build 5) |
| Review-account voor Apple App Review maken (voorbeeldkaarten en gedeelde Pasr, wachtwoord niet bewaard) | ✓ (ook in web-beheer en PasrBeheer build 6) |
| Saldo-pagina's per winkel voor de knop Saldo checken (ook winkels in de app) | ✓ (ook in web-beheer en PasrBeheer build 7) |
| Beheer-pushmeldingen (soorten, testmelding, uitleg na inloggen) | ✓ originele registratie; ontvangen na `server/patches` |
| Instellingen met MoreAppsCard | ✓ |
| Deeplinks `pasrbeheer://…` | ✓ |
| Mac (native) | Mac-app van LRbeheer (Catalyst) |

### P2000Beheer → A-Alerts (P2000 Apeldoorn)

| Onderdeel | In LRbeheer |
| --- | --- |
| Inloggen, Face ID-vergrendeling | ✓ originele code |
| Dashboard (status, Apple-login, bezoekers, actief, platforms, versies, meldingen, top) | ✓ |
| Meldingen, Push (versturen per plaats, geschiedenis), Teksten (app- en webteksten, changelog) | ✓ |
| Instellingen, pushmeldingen van de feed (storing/hersteld, test) | ✓ originele registratie; ontvangen na `server/patches` |
| **A-Alerts** (nieuw, ook in P2000Beheer en het web-beheer): omgeving heet A-Alerts met het nieuwe icoon | ✓ |
| Waarschuwingen: NL-Alert, Burgernet en KNMI zoeken/filteren, verbergen, handmatig beëindigen | ✓ (`/v1/beheer/waarschuwingen`) |
| Dashboard: status van NL-Alert, Burgernet, KNMI en adsb.lol; helikopters in de lucht | ✓ |
| Dashboard: notificatieprofielen (toestellen, verdeling, tijden, waarschuwingen, populairste plaatsen) | ✓ |
| Pushmelding bij afwijkingen (schakelaar *Storingen en afwijkingen*): elk onderdeel van de statuspagina dat 3 minuten afwijkt, push-wachtrij die achterloopt, lange stilte zonder meldingen, en weer als het normaal is (vervangt de feed- en bronmeldingen) | ✓ (ook P2000Beheer; na deploy van de worker) |
| **Status** (nieuw tabblad): onderdelen van a-alerts.nl/status met uptime en ruwe fout, afwijkingen, storingen en gepland onderhoud plaatsen/bijwerken/afronden/verwijderen | ✓ (ook P2000Beheer en web-beheer; `/v1/beheer/status`) |
| Teksten: cookieverklaring (nieuw, naast privacy, voorwaarden, disclaimer en changelog); links naar a-alerts.nl | ✓ (ook P2000Beheer en web-beheer) |
| Teksten: **Hulp en veelgestelde vragen** (nieuw): hulppagina in de apps (Instellingen) | ✓ (ook P2000Beheer en web-beheer; `/v1/content/hulp`) |
| **Gemelde fouten** (nieuw): meldingen die gebruikers via "Klopt deze melding niet?" als onjuist aangeven (reden, toelichting, juiste plek); afhandelen, heropenen, verwijderen of de melding bewerken; beheer-push bij een nieuwe melding | ✓ (ook P2000Beheer en web-beheer; `/v1/beheer/feedback`) |
| **Toestel zoeken** (nieuw): een gebruiker opzoeken met het toestel-ID uit de app (Instellingen, onder Disclaimer): toestel, appversie, pushregistratie en -instellingen; testmelding naar dat toestel | ✓ (ook P2000Beheer en web-beheer; `/v1/beheer/toestel/:code`) |
| A-Alerts: **AMBER Alert en Vermist Kind Alert** (nieuw): eigen bronnen in de waarschuwingenlijst, filter en cijfers per bron; status van de Burgernet-bron; aantal toestellen dat ze wil ontvangen | ✓ (ook P2000Beheer en web-beheer) |
| A-Alerts: **Nieuws** (nieuw): politieberichten, weerartikelen en liveblogs; verbergen, eigen afbeelding, liveblog aanvullen met tekst, foto en link (met pushmelding), eigen berichten wijzigen of verwijderen, standaardafbeeldingen per onderwerp voor politieberichten; bij de bronnen ook **Verkeer (NDW, Koyeb)** met storingsmelding; **Widgets**: iframe- en scriptcode van de live kaart en Verkeer nu kopiëren, ingesloten sites met weergaven, site blokkeren; per weerartikel, Burgernet, AMBER Alert, NL-Alert en Vermist Kind de schakelaar **Liveblog** (standaard uit: label en LIVEBLOG op de afbeelding) | ✓ (ook P2000Beheer en web-beheer; `/v1/beheer/nieuws`) |
| Dashboard: **Android-app** – APK-downloads van a-alerts.nl (totaal, 30 dagen, vandaag, per dag, per versie), Android-installaties en push-toestellen; status Firebase-push | ✓ (ook P2000Beheer en web-beheer; `/v1/beheer/downloads`) |
| Mac (native) | Mac-app van LRbeheer (Catalyst) |

### lrvdlinden.app/beheer → LRvdLinden (nieuw, native)

Alles van `site/beheer.html`, met dezelfde endpoints (`apps.json`, `publish.php`, `store-refresh.php`, `store-log.php`,
`translate.php`) en dezelfde inlog:

- lijst per sectie (iOS & andere platformen / Homey) met icoon, ★ voor *Nieuw en onderweg* en status; zoeken;
- bewerken: naam, ID, sectie, categorie (24), status, *Tonen in Nieuw en onderweg*, platformen (+ eigen apparaat), icoon
  (pad of uploaden), ondertitel/omschrijving/label NL+EN, promo-banner per taal (uploaden/verwijderen, bovenregel, titel,
  tekst), links (App Store, TestFlight, website, Homey), bundle-id, beoordeling, reviews, grootte, talen,
  versiegeschiedenis (toevoegen bovenaan, bewerken, verwijderen), hoger/lager, verwijderen, JSON van de app;
- **Vertaal NL → EN** (met *overschrijven*), **Publiceren** (direct live + commit, zelfde commitbericht),
  **Nieuwe apps ophalen** / **Apps bijwerken** (workflow starten, voortgang, daarna samenvoegen met je concept),
  **Logboek** (filters, runs per dag, wijzigingen, gecontroleerde apps, lopende/mislukte runs),
  **Bestand openen**, **Kopieer JSON**, **Download apps.json**, **Wijzigingen weggooien**;
- concept blijft bewaard tot je publiceert, en wordt net als in de browser samengevoegd als de site intussen wijzigde.

De volgorde van velden en onbekende velden in `apps.json` blijven precies staan.

### pixelforges.nl/beheer → PixelForges (nieuw, native)

Alles van `site/beheer.html`, met dezelfde endpoints (`content.json`, `publish.php`, `fetch-meta.php`):

- **Algemeen**: contact & bedrijf, cijfers, hero, over ons (alinea's), cookies;
- **Pakketten, Werkwijze, Portfolio, Reviews, Waarden, Vragen**: toevoegen, bewerken (alle velden van het schema, ook
  lijsten, labels, aan/uit en afbeeldingen), omhoog/omlaag/slepen, dupliceren, verwijderen;
- **Nieuw project van een website** en **Opnieuw ophalen** (naam, omschrijving en afbeelding automatisch);
- **Publiceren** met commitbericht en controle (id's, namen, e-mailadres), **Download content.json**,
  **Server-versie laden**, concept dat bewaard blijft (*Toch mijn concept gebruiken* als de site intussen wijzigde).

Afbeeldingen worden op het toestel verkleind en als JPEG geüpload (iOS kan geen WebP schrijven; `publish.php` accepteert
webp, png en jpg).

### bekendr.lrvdlinden.app/beheer → Bekendr (nieuw, native)

Bekendr heeft geen eigen server. App en web-beheer (`website/beheer/` in LRvdLinden/app.lrvdlinden.bekendr) praten met
de centrale functie `lrbeheer` (acties `bekendr_login` en `bekendr_stats`; zie `server/README.md`).

| Onderdeel | In LRbeheer | Web-beheer |
| --- | --- | --- |
| Inloggen met de gedeelde beheer-inlog (token 12 uur), doet mee met *Eén inlog* | ✓ (sleutelhanger) | ✓ (alleen dit tabblad) |
| Downloads totaal en per apparaat: iPhone, iPad, Mac (App Store Connect, verkoopoverzichten) | ✓ | ✓ |
| Apple: eerste downloads, opnieuw gedownload, updates, laatste dag | ✓ | ✓ |
| Android: APK-downloads totaal en per release (GitHub Releases) | ✓ | ✓ |
| Grafiek downloads per dag (30 dagen), per platform gestapeld | ✓ (Swift Charts) | ✓ (SVG) |
| Feedback uit de app (reden: locatie, categorie, gemeente, link of anders, met toelichting): lijst, alleen nieuwe, afhandelen, heropenen, verwijderen, publicatie openen | ✓ (Downloads / Feedback) | ✓ |
| Pushmelding | nog niet (voorstel: melding bij nieuwe feedback en dagelijks overzicht van nieuwe downloads) | – |

### noodpakket.lrvdlinden.app/beheer → Noodpakket (nieuw, native)

Noodpakket heeft geen eigen server. App en web-beheer (`web/beheer/` in LRvdLinden/app.lrvdlinden.noodkoffer, door Léon
zelf geüpload naar zijn hosting) praten met de centrale functie `lrbeheer` (acties `noodpakket_*`; zie
`server/README.md`). De Noodpakket-apps zelf melden zich alleen aan voor berichten.

| Onderdeel | In LRbeheer | Web-beheer |
| --- | --- | --- |
| Inloggen met de gedeelde beheer-inlog (token 12 uur), doet mee met *Eén inlog* | ✓ (sleutelhanger) | ✓ (alleen dit tabblad) |
| Downloads totaal en per apparaat: iPhone, iPad (App Store Connect) en Android (APK in GitHub Releases, tags `vX.Y.Z`) | ✓ | ✓ |
| Grafiek downloads per dag (30 dagen), per platform gestapeld | ✓ (Swift Charts) | ✓ (SVG) |
| Android: releases met downloads, nieuwste release gemarkeerd | ✓ | ✓ |
| Android-builds: status van de laatste runs van `android.yml` (wachtrij, bezig, gelukt, mislukt), met link | ✓ | ✓ |
| Ontvangers van berichten: iPhone/iPad, Android (actief 30 dagen), per taal | ✓ | ✓ |
| Bericht aan gebruikers: titel, tekst, link, apparaten (alle, iPhone/iPad, Android) en taal, met voorbeeld | ✓ | ✓ |
| Testbericht naar de eigen LRbeheer-apparaten | ✓ | ✓ |
| Verstuurde berichten met bereik (afgeleverd, mislukt, opgehaald door Android), intrekken, opnieuw gebruiken | ✓ | ✓ (intrekken) |
| Pushmelding naar LRbeheer | nog niet (voorstel: melding bij een mislukte Android-build en bij een nieuwe release) | – |

### pairr.lrvdlinden.app/beheer → Pairr (nieuw, native)

Pairr heeft geen eigen server en geen Android-versie. App en web-beheer (`web/beheer/` in LRvdLinden/app.lrvdlinden.pairr,
door Léon zelf geüpload naar zijn hosting) praten met de centrale functie `lrbeheer` (acties `pairr_login` en
`pairr_stats`; zie `server/README.md`).

| Onderdeel | In LRbeheer | Web-beheer |
| --- | --- | --- |
| Inloggen met de gedeelde beheer-inlog (token 12 uur), doet mee met *Eén inlog* | ✓ (sleutelhanger) | ✓ (alleen dit tabblad) |
| Downloads totaal en per apparaat: iPhone, iPad, Mac (App Store Connect, verkoopoverzichten) | ✓ | ✓ |
| Apple: eerste downloads, opnieuw gedownload, updates, laatste dag | ✓ | ✓ |
| Grafiek downloads per dag (30 dagen), per apparaat gestapeld | ✓ (Swift Charts) | ✓ (SVG) |
| Omzet: opbrengst na Apple (totaal, deze maand, verkochte exemplaren, per valuta) en grafiek per dag, omgerekend naar euro met de ECB-koers | ✓ | ✓ |
| Open meldingen van gebruikers (GitHub Issues): aantal, titel, datum, reacties, labels, openen op GitHub | ✓ | ✓ |
| Pushmelding naar LRbeheer | nog niet (voorstel: melding bij een nieuwe melding op GitHub en dagelijks overzicht van nieuwe downloads) | – |

## Standaarden van LRvdLinden-apps

- Huisstijl van lrvdlinden.app: accent #2747E8 / #8A9DFF, ink #121726, LR-logo, kaarten met radius 22.
- Instellingen: LRbeheer-instellingen → Omgevingen → Weergave (Automatisch/Licht/Donker; Bingr, Tunr en Pasr blijven
  donker zoals hun originelen) → links (privacy, lrvdlinden.app, wat is nieuw, doneer) → **Ontdekken** met `MoreAppsCard`
  → `AppInfoFooter` (icoon, versie + build, © jaar).
- Review-prompt: eerst 4 uur na het eerste gebruik, daarna hoogstens eens per week, 4 seconden na openen, nooit tijdens de
  splash, vergrendeld of in een blad.
- Teksten in `Localizable.xcstrings` en `InfoPlist.xcstrings` (nl + en); `PrivacyInfo.xcprivacy` in app en widgets.
- Geheimen alleen in de sleutelhanger (inlog van de sites) of op de server; geen sleutels in de app of in deze repo.

## Controle

| Punt | Hoe gecontroleerd |
| --- | --- |
| Alle omgevingen toegankelijk | overzicht + kiezer; elke omgeving heeft een root-view (`BeheerEnvironment.rootView`) |
| Wisselen | `AppModel.switchTo`; sessies leven zo lang als de app, wisselen logt niet uit |
| Alle bestaande functies overgenomen | 102 Swift-bestanden van de vier apps letterlijk overgenomen (`Modules/IMPORT.json`); vergelijking hierboven |
| API-koppelingen en inlog | ongewijzigde code; LRvdLinden/PixelForges via dezelfde PHP-endpoints als beheer.html |
| Push van alle omgevingen | token naar alle vier systemen; centrale functie getest (`logic_test.ts`, 9 tests); patches met `git apply --check` |
| Push naar juiste omgeving | `AppModel.handleNotification` (`lrenv` of URL-schema) |
| Geen webbeheer aangepast | er is buiten `/beheer` niets gewijzigd in deze repo, en niets in de andere repo's |
| Zelfstandig te bouwen | Xcode-project zonder externe pakketten; syntaxis van alle Swift-bestanden gecontroleerd; **eerste build in Xcode nog te doen** |

## Nog te doen door jou

1. Openen en bouwen in Xcode (zie boven); compileerfouten doorsturen als die er zijn.
2. Pushmeldingen aan de serverkant: `server/README.md` (centrale functie deployen, patches toepassen).
3. Optioneel: privacy- en support-URL in Instellingen controleren (nu https://lrvdlinden.app/privacy.html en https://lrvdlinden.app).
