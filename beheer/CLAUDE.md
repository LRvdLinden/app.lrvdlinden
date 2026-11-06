# LRbeheer: werkafspraken

- Het beheer van Bingr, Tunr, Pasr en P2000 wordt **hier** bijgewerkt, in `Modules/<App>Kit/Sources/`. Zolang de oude
  beheerapps (bingr-beheer/ios, tunr-beheer/apple, app.lrvdlinden.pasr/beheer/apple, p2000-apeldoorn/beheer) nog in gebruik
  zijn, krijgen die **dezelfde wijziging met de hand**, zodat beide gelijk blijven.
- Nieuwe app met beheer = nieuwe omgeving in LRbeheer (achteraan in het overzicht), geen losse beheerapp.
- Web-dashboards: per wijziging aan Léon vragen of het web-beheer ook mee moet.
- Bij elke nieuwe beheerfunctie: Wat is nieuw (Shell/SettingsView.swift, WhatsNewView) bijwerken, pushmelding voorstellen,
  functievergelijking in README.md bijwerken, teksten nl + en.
- Oplevering: BUILD in tools/make_project.py +1 en het script draaien, commit direct op main, Xcode-ZIP van beheer/ meeleveren.
- Nieuwe functies van een web-dashboard of backend van die apps ook hier overnemen.
- `tools/import_modules.py` niet draaien (overschrijft wijzigingen); alleen met `--overwrite` en na overleg.
- Serverkant (API's, Edge Functions, worker) blijft in de eigen repo's; niets aan de websites veranderen vanuit hier.
- Nieuwe bestanden in een gesynchroniseerde map neemt Xcode vanzelf mee; `tools/make_project.py` alleen bij nieuwe
  targets of instellingen (bv. buildnummer).
- Teksten: nl-sleutels in de Swift-code, Engelse vertaling in `tools/strings_en.json`, daarna `tools/make_strings.py`.
- Geen geheimen in de app of repo; inlog en APNs komen uit LRvdLinden/app.lrvdlinden.secrets (zie server/README.md).
- Commitberichten in het Nederlands.
