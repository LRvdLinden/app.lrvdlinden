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
| `BEHEER_HTPASSWD_PATH` | Absoluut pad naar `.htpasswd` op de server, bijv. `/home/gebruiker/domains/lrvdlinden.app/public_html/.htpasswd` |

Het wachtwoord komt alleen als bcrypt-hash in de release terecht.

## Een update doen

1. Open `https://lrvdlinden.app/beheer.html`, pas apps aan en klik **Download apps.json**.
2. Vervang `site/apps.json` in deze repo (op GitHub: *Add file → Upload files*).
3. De Action maakt automatisch een release `vJJJJ.MM.DD-N` met een zip.
4. Upload de inhoud van de zip naar de webroot van lrvdlinden.app.

Nieuw icoon: zet het in `site/img/` en vul het pad in via de beheerpagina.
Een release handmatig maken kan via **Actions → Release site → Run workflow**.
