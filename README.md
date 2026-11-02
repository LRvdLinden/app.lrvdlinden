# lrvdlinden.app

Portfolio-site met iOS- en Homey-apps van Léon van der Linden.

## Structuur

- `site/` – alles wat online komt
  - `index.html` – de site (NL/EN)
  - `apps.json` – alle apps, status, platformen en teksten
  - `beheer.html` – beheerpagina om `apps.json` te bewerken (achter wachtwoord)
  - `img/` – app-iconen
- `.github/workflows/release.yml` – maakt bij elke wijziging in `site/` een zip-release

## Secrets

Zet deze onder **Settings → Secrets and variables → Actions → New repository secret**:

| Naam | Inhoud |
|---|---|
| `BEHEER_USER` | Gebruikersnaam voor `beheer.html` |
| `BEHEER_PASSWORD` | Wachtwoord voor `beheer.html` |
| `BEHEER_HTPASSWD_PATH` | `/home/dotenter/public_html/lrvdlinden.app/.htpasswd` |
| `FTP_SERVER` | FTP-server uit cPanel (bijv. `ftp.lrvdlinden.app`) |
| `FTP_USER` | Volledige FTP-gebruikersnaam uit cPanel (bijv. `naam@domein.nl`) |
| `FTP_PASSWORD` | Wachtwoord van dat FTP-account |
| `FTP_PORT` | Meestal `21` (`22` = SFTP) |
| `FTP_DIR` | Optioneel: doelmap als die niet automatisch klopt |
| `PUBLISH_GITHUB_TOKEN` | Fine-grained token, alleen voor deze repo, met *Contents: Read and write* en *Actions: Read and write* |
| `ANTHROPIC_API_KEY` | API-sleutel voor vertalen: wat-is-nieuw in de store-check en de knop **Vertaal NL → EN** in beheer |
| `ANTHROPIC_WORKSPACE_ID` | Alleen nodig als de API-sleutel niet aan een workspace gekoppeld is (`wrkspc_…`) |

Wachtwoord en token komen alleen op de server terecht, nooit in de repo of in de (publieke) zip-releases.

## Een update doen

1. Open `https://lrvdlinden.app/beheer.html` en log in.
2. Pas apps aan, upload eventueel een icoon en klik **Publiceren**. Met **Vertaal NL → EN** vul je de
   Engelse teksten van een app automatisch in vanuit het Nederlands.
3. De wijziging staat direct live en wordt als commit in deze repo opgeslagen.
4. De workflow zet daarna de hele site via FTP opnieuw neer en maakt een zip-release als back-up.

Apps met alleen een TestFlight-link (nog geen App Store-link) staan op de site in een eigen blok **Via TestFlight**.
Zodra de store-check een App Store-link vindt, verhuist de app vanzelf naar **In de App Store**.

Wijzigingen aan de code (bijv. `index.html`) gaan via een commit in `site/`; ook die worden automatisch live gezet.
Handmatig opnieuw uitrollen: **Actions → Release site → Run workflow**.

## Dagelijkse store-check

Elke dag om 08:00 loopt **Actions → Store-check** de App Store en de Homey App Store na (alles).
In `beheer.html` kun je het ook zelf starten:

- **Nieuwe apps ophalen**: alleen nieuwe apps zoeken en beta-apps aanvullen (1 tot 3 minuten).
- **Apps bijwerken**: alle bestaande apps bijwerken (3 tot 5 minuten).

Handmatig op GitHub kan ook: **Run workflow** en kies *alles*, *nieuw* of *bijwerken*.

- **Nieuwe apps**: alle apps van de ontwikkelaarspagina in de App Store (id 607860328) en van beide
  Homey-auteurspagina's die nog niet op de site staan, worden toegevoegd met icoon, categorie, platformen
  en een korte omschrijving en ondertitel in NL en EN.
- **Beta-apps aanvullen**: staat een beta-app (zonder App Store-link) inmiddels in de store, dan krijgt hij
  de link, status Live en wat er nog ontbrak. Bestaande teksten blijven staan.

- **App Store** (apps met een App Store-link): versie, wat-is-nieuw, sterren en aantal beoordelingen
  (opgeteld over 44 landen), grootte en talen.
- **Homey**: live- of testversie (status Live/Test), de laatste 10 changelog-regels en sterren
  (Homey toont geen aantal beoordelingen), plus de apparaten, widgets en Flow-kaarten. Op de site
  klap je een Homey-app open om die te zien, net als in de Homey App Store.

Wat-is-nieuw wordt in NL en EN opgeslagen; ontbreekt een taal, dan vertaalt de Claude API hem
(alleen nieuwe teksten, dus hooguit een paar cent per maand). Bij wijzigingen wordt `site/apps.json`
bijgewerkt en de site automatisch opnieuw live gezet. Handmatig draaien: **Run workflow**.
