# LRbeheer

Eén iOS-/iPadOS-app waarmee je al je platformen beheert: **LRvdLinden, PixelForges, Bingr, Tunr, Pasr en P2000 Apeldoorn**.
Elke omgeving is de volledige beheerapp of het volledige webbeheer, niet een vereenvoudigde versie.

| | |
| --- | --- |
| Appnaam | LRbeheer |
| Bundle-id | `app.lrvdlinden.lrbeheer` (widgets: `app.lrvdlinden.lrbeheer.widget`) |
| Versie / build | 1.0.0 (1) |
| Platform | iPhone en iPad, iOS/iPadOS 18+ (P2000Beheer vroeg al iOS 18; Bingr, Tunr en Pasr 17); op een Mac met Apple silicon als "Designed for iPad" |
| Team | EU3UY476T6, automatisch ondertekenen |
| URL-schema | `lrbeheer://<omgeving>/…` |

## Openen en bouwen

1. Open `LRbeheer.xcodeproj` in **Xcode 16 of nieuwer** (het project gebruikt gesynchroniseerde mappen).
2. Kies het scheme **LRbeheer** en een iPhone, iPad of simulator. Team en signing staan al ingevuld.
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
│   ├── App/                     @main, AppModel (actieve omgeving, deeplinks, push-routing), de zes omgevingen
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
`Modules/<App>Kit/Sources/`. De `beheer`-mappen in de oude repo's (bingr-beheer/ios, tunr-beheer/apple,
app.lrvdlinden.pasr/beheer/apple, p2000-apeldoorn/beheer) staan stil. De serverkant (API's, Edge Functions, worker)
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
  **overzicht** met de zes omgevingen in vaste volgorde: LRvdLinden, PixelForges, Bingr, Tunr, Pasr, P2000 Apeldoorn,
  elk met eigen logo, of je ingelogd bent en welke het laatst gebruikt is.
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
| Mac (Catalyst) met menubalk | Mac met Apple silicon als iPad-app; de losse BingrBeheer voor Mac blijft bestaan |

### BeheerTunr → Tunr

| Onderdeel | In LRbeheer |
| --- | --- |
| "Nog niet ingericht", inloggen, Overal uitloggen, vergrendeling na 5 min | ✓ originele code |
| Overzicht (statistieken per periode, Insights-grafiek, perskit) | ✓ |
| Downloads (builds, kortgeldige links) | ✓ |
| Instellingen (nl/en-teksten) | ✓ (`Tunr.strings`) |
| Pushmeldingen | **nieuw**: installaties en perskit via de centrale functie |
| Mac (native) met menubalk | Mac met Apple silicon als iPad-app; de losse BeheerTunr voor Mac blijft bestaan |

### PasrBeheer → Pasr

| Onderdeel | In LRbeheer |
| --- | --- |
| Inloggen, Overal uitloggen, vergrendeling | ✓ originele code |
| Overzicht, Insights (bronnen, periode), Accounts | ✓ |
| Beheer-pushmeldingen (soorten, testmelding, uitleg na inloggen) | ✓ originele registratie; ontvangen na `server/patches` |
| Instellingen met MoreAppsCard | ✓ |
| Deeplinks `pasrbeheer://…` | ✓ |
| Mac (native) | Mac met Apple silicon als iPad-app |

### P2000Beheer → P2000 Apeldoorn

| Onderdeel | In LRbeheer |
| --- | --- |
| Inloggen, Face ID-vergrendeling | ✓ originele code |
| Dashboard (status, Apple-login, bezoekers, actief, platforms, versies, meldingen, top) | ✓ |
| Meldingen, Push (versturen per plaats, geschiedenis), Teksten (app- en webteksten, changelog) | ✓ |
| Instellingen, pushmeldingen van de feed (storing/hersteld, test) | ✓ originele registratie; ontvangen na `server/patches` |
| Mac (native) | Mac met Apple silicon als iPad-app |

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
| Alle zes omgevingen toegankelijk | overzicht + kiezer; elke omgeving heeft een root-view (`BeheerEnvironment.rootView`) |
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
