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
| `PUBLISH_GITHUB_TOKEN` | Fine-grained token, alleen voor deze repo, met *Contents: Read and write* |

Wachtwoord en token komen alleen op de server terecht, nooit in de repo of in de (publieke) zip-releases.

## Een update doen

1. Open `https://lrvdlinden.app/beheer.html` en log in.
2. Pas apps aan, upload eventueel een icoon en klik **Publiceren**.
3. De wijziging staat direct live en wordt als commit in deze repo opgeslagen.
4. De workflow zet daarna de hele site via FTP opnieuw neer en maakt een zip-release als back-up.

Wijzigingen aan de code (bijv. `index.html`) gaan via een commit in `site/`; ook die worden automatisch live gezet.
Handmatig opnieuw uitrollen: **Actions → Release site → Run workflow**.
