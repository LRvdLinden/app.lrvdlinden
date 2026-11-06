# LRbeheer: werkafspraken

- Het beheer van Bingr, Tunr, Pasr en P2000 wordt **hier** bijgewerkt, in `Modules/<App>Kit/Sources/`. De beheerapps in de
  oude repo's (bingr-beheer/ios, tunr-beheer/apple, app.lrvdlinden.pasr/beheer/apple, p2000-apeldoorn/beheer) staan stil.
- Nieuwe functies van een web-dashboard of backend van die apps ook hier overnemen.
- `tools/import_modules.py` niet draaien (overschrijft wijzigingen); alleen met `--overwrite` en na overleg.
- Serverkant (API's, Edge Functions, worker) blijft in de eigen repo's; niets aan de websites veranderen vanuit hier.
- Nieuwe bestanden in een gesynchroniseerde map neemt Xcode vanzelf mee; `tools/make_project.py` alleen bij nieuwe
  targets of instellingen (bv. buildnummer).
- Teksten: nl-sleutels in de Swift-code, Engelse vertaling in `tools/strings_en.json`, daarna `tools/make_strings.py`.
- Geen geheimen in de app of repo; inlog en APNs komen uit LRvdLinden/app.lrvdlinden.secrets (zie server/README.md).
- Commitberichten in het Nederlands.
