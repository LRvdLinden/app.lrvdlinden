# LRbeheer – serverkant van de pushmeldingen

LRbeheer is één app (bundle-id `app.lrvdlinden.lrbeheer`) voor zes beheeromgevingen. Voor pushmeldingen zijn er twee
soorten:

| Omgeving | Pushsysteem | Wat er nodig is |
| --- | --- | --- |
| Bingr | bestaand (functie `push`, cron in iptv-ios-appletv; testmelding in `admin` van bingr-beheer) | patch `patches/iptv-ios-appletv.patch` + `patches/bingr-beheer.patch` |
| Pasr | bestaand (functie `admin` van app.lrvdlinden.pasr) | patch `patches/app.lrvdlinden.pasr.patch` |
| P2000 Apeldoorn | bestaand (worker van p2000-apeldoorn) | patch `patches/p2000-apeldoorn.patch` |
| LRvdLinden | **nieuw**, centrale functie `lrbeheer` | deploy van `supabase/functions/lrbeheer` + `schema.sql` |
| PixelForges | **nieuw**, centrale functie `lrbeheer` | idem |
| Tunr | **nieuw** (TunrBeheer had nog geen push), centrale functie `lrbeheer` | idem |

## Onderzoek: het pushsysteem van TunrBeheer hergebruiken

TunrBeheer had nog **geen** pushmeldingen (geen APNs-registratie in de app, geen pushcode in `supabase/functions`).
Wat wel herbruikbaar is en hergebruikt wordt:

- het **Supabase-project van Tunr** als plek voor de centrale functie (dezelfde manier van deployen als `admin`, `ping` en
  `presskit`, met de Supabase CLI en function-secrets);
- de **beheer-inlog van TunrBeheer**: LRbeheer meldt zich bij de centrale functie aan met het Tunr-beheertoken. De functie
  controleert het met dezelfde sleutel (`TUNR_TOKEN_SECRET`) en dezelfde tokenversie (`admin_token_state`) als `admin`,
  dus *Overal uitloggen* in Tunr meldt ook de centrale meldingen af. Er komt geen nieuw wachtwoord bij en er staat
  niets geheims in de app.

Het patroon (registratie per apparaat met schakelaars per soort, testmelding, ongeldige tokens opruimen, providertoken
per 30 minuten) is overgenomen van BingrBeheer/PasrBeheer, zodat alle beheerpush hetzelfde werkt.

## Waarom de bestaande backends een kleine patch nodig hebben

APNs stuurt een melding alleen af als het *topic* (bundle-id) bij het token hoort. De backends van Bingr, Pasr en P2000
sturen nu met het topic van hun eigen beheerapp (`nl.lrvdlinden.bingr.beheer`, `nl.lrvdlinden.pasr.beheer`,
`nl.lrvdlinden.p2000beheer`). LRbeheer registreert zich bij die backends met precies dezelfde, bestaande acties
(`admin_push_register`, `push_register`, `POST /v1/beheer/devices`), maar zijn token hoort bij `app.lrvdlinden.lrbeheer`.

De patches doen alleen dit: antwoordt APNs `DeviceTokenNotForTopic`, dan **nog één keer** met het topic van LRbeheer
(en het veld `lrenv`, zodat LRbeheer bij een tik de juiste omgeving opent). Tokens van de oude beheerapps gaan precies
zoals nu; er is geen schemawijziging, geen nieuwe tabel en niets aan de websites. Het topic is te overschrijven met het
function-secret / de variabele `LRBEHEER_APNS_TOPIC`.

> Zonder deze patches werken alle functies van Bingr, Pasr en P2000 in LRbeheer gewoon, maar komen hun pushmeldingen
> niet op LRbeheer binnen (wel nog op de losse beheerapps). Met de huidige code zou een backend het LRbeheer-token
> bovendien als ongeldig opruimen.

Toepassen (in elke repo, daarna de gewone deploy-workflow):

```sh
git -C iptv-ios-appletv   apply ../app.lrvdlinden/beheer/server/patches/iptv-ios-appletv.patch
git -C bingr-beheer       apply ../app.lrvdlinden/beheer/server/patches/bingr-beheer.patch
git -C app.lrvdlinden.pasr apply ../app.lrvdlinden/beheer/server/patches/app.lrvdlinden.pasr.patch
git -C p2000-apeldoorn    apply ../app.lrvdlinden/beheer/server/patches/p2000-apeldoorn.patch
```

De patches zijn gecontroleerd met `git apply --check` tegen de huidige `main` van elke repo (6 november 2026).
Ze zijn **niet** toegepast of gedeployd: dat raakt productie en is jouw beslissing.

## De centrale functie `lrbeheer` installeren (Supabase-project van Tunr)

1. **Schema**: voer `supabase/schema.sql` uit (SQL Editor of Management API). Alleen nieuwe tabellen `lrbeheer_*`.
2. **Function-secrets** (Supabase → Edge Functions → Secrets, of `supabase secrets set`):

   | Secret | Waarde |
   | --- | --- |
   | `TUNR_TOKEN_SECRET` | staat er al (van `admin`) |
   | `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` | dezelfde APNs-sleutel (.p8) als Bingr/Pasr; een APNs-sleutel geldt voor alle apps van team EU3UY476T6 |
   | `LRBEHEER_CRON_SECRET` | nieuw, lange willekeurige tekst |
   | `LRBEHEER_NOTIFY_SECRET` | optioneel, voor haken van buitenaf (zie onder) |
   | `LRBEHEER_APNS_TOPIC` | optioneel, standaard `app.lrvdlinden.lrbeheer` |
   | `GITHUB_TOKEN` | optioneel, fine-grained, alleen *Public repositories (read-only)*; zonder token 60 GitHub-verzoeken per uur, ruim genoeg |

3. **Deploy**: kopieer `supabase/functions/lrbeheer` naar `tunr-beheer/supabase/functions/` (of deploy vanuit deze map) en
   zet in `config.toml`:

   ```toml
   [functions.lrbeheer]
   verify_jwt = false
   ```

   `supabase functions deploy lrbeheer --project-ref <ref>`

4. **Cron**: het blok onderaan `schema.sql` (pg_cron + pg_net, elke 5 minuten).

5. **Test**: log in LRbeheer in bij Tunr, ga naar Instellingen → Meldingen en tik *Stuur een testmelding*.

Tests van de logica: `deno test supabase/functions/lrbeheer/logic_test.ts` (9 tests).

## Welke meldingen de centrale functie stuurt

Alles op basis van openbare gegevens of de eigen Tunr-database; de websites zelf worden **niet** aangeroepen of aangepast.

| Omgeving | Soort | Bron | Melding |
| --- | --- | --- | --- |
| LRvdLinden | `store` | `logs/store-check.json` en `site/apps.json` in de openbare repo | Store-check met wijzigingen (bv. "Weekdot: versie 1.0.3"), nieuwe app op de site |
| LRvdLinden | `deploy` | GitHub Actions *Release site* | "lrvdlinden.app is bijgewerkt" / "Deploy mislukt" |
| PixelForges | `deploy` | GitHub Actions *Release site* | idem voor pixelforges.nl |
| PixelForges | `content` | commits op `site/content.json` | "Inhoud van pixelforges.nl gewijzigd" |
| PixelForges | `contact` | actie `notify` (haak) | nieuwe aanvraag via het contactformulier |
| Tunr | `installs` | tabel `installs` | elke dag om 20:00 het aantal nieuwe installaties per platform |
| Tunr | `presskit` | tabel `presskit_downloads` | perskit gedownload |

Elke melding heeft `lrenv` (omgeving) en `url` (`lrbeheer://<omgeving>/…`); LRbeheer opent bij een tik die omgeving.

### Optioneel: melding bij een nieuwe aanvraag op pixelforges.nl

Het contactformulier mailt nu alleen. Wil je er ook een pushmelding van, dan kan `contact.php` na het mailen één
verzoek doen. **Dit is niet toegepast** (de websites blijven ongewijzigd); het is een keuze voor later:

```php
// na een geslaagde mail() in contact.php
@file_get_contents('https://<PROJECT_REF>.supabase.co/functions/v1/lrbeheer', false, stream_context_create(['http' => [
  'method' => 'POST', 'timeout' => 3,
  'header' => "Content-Type: application/json\r\nx-lrbeheer-secret: <LRBEHEER_NOTIFY_SECRET>\r\n",
  'content' => json_encode(['action' => 'notify', 'env' => 'pixelforges', 'kind' => 'contact',
    'title' => 'Nieuwe aanvraag via pixelforges.nl', 'body' => $name . ($company !== '' ? " ($company)" : '')]),
]]));
```

## Secrets

De repo `LRvdLinden/app.lrvdlinden.secrets` was bij het bouwen **leeg** (geen bestanden). Er staan dus geen geheimen in
deze map of in de app: alle sleutels blijven function-secrets op de server. In de app staan alleen openbare waarden
(Supabase-URL's en publishable keys, die ook in de bestaande beheerapps staan).
