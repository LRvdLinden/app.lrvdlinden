#!/usr/bin/env python3
"""Neemt de volledige broncode van de vier bestaande beheerapps over in LRbeheer (beheer/Modules/<Kit>/Sources).

Elke beheerapp wordt een eigen framework-target (BingrKit, TunrKit, PasrKit, P2000Kit). Zo houdt iedere app zijn eigen
typenamen (Session, AdminAPI, RootView, ...) zonder botsingen, en blijft de code vrijwel letterlijk gelijk aan het origineel.

Alleen wat technisch nodig is om samen in één app te draaien wordt aangepast (zie PATCHES hieronder en README.md,
"Wat er aan de bestaande code is aangepast"):

  1. `@main` weg: alleen LRbeheer zelf heeft een app-ingang. De App-structs blijven als gewone code staan.
  2. `UserDefaults.standard` -> `UserDefaults.module` en `@AppStorage("x")` -> `@AppStorage("x", store: UserDefaults.module)`:
     elke beheerapp krijgt zijn eigen UserDefaults-suite, anders botsen sleutels als `push.device_id`, `lockEnabled` en
     `push.registration` tussen Bingr en Pasr.
  3. Per app een paar regels (PATCHES): widget-sleutelhangergroep van Bingr, vertaaltabel van Tunr, en P2000 die de
     delegate van het meldingencentrum niet meer zelf overneemt (dat doet LRbeheer centraal).

Assets (logo's, covers) gaan naar een eigen asset-catalogus per omgeving in de app (LRbeheer/Resources/<Naam>.xcassets),
zonder AppIcon/AccentColor/LaunchBackground (die heeft LRbeheer zelf). Tunr's Localizable.strings wordt Tunr.strings.

Gebruik (vanuit beheer/):
    python3 tools/import_modules.py --src /pad/naar/map-met-alle-repos

De map moet de clones bevatten: bingr-beheer, tunr-beheer, app.lrvdlinden.pasr, p2000-apeldoorn.
Het script overschrijft alleen Modules/*/Sources, Widgets/BingrWidgets en LRbeheer/Resources/{Bingr,Tunr,Pasr,P2000}.*;
de handgeschreven bruggen (Modules/*/Bridge) blijven staan.
"""
import argparse
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MODULES = {
    "BingrKit": {
        "repo": "bingr-beheer",
        "sources": ["ios/BingrBeheer", "ios/Shared"],
        "assets": "ios/BingrBeheer/Resources/Assets.xcassets",
        "asset_name": "Bingr",
        "suite": "bingr",
        "skip": [],
    },
    "TunrKit": {
        "repo": "tunr-beheer",
        "sources": ["apple/Shared"],
        "assets": "apple/Shared/Assets.xcassets",
        "asset_name": "Tunr",
        "suite": "tunr",
        "skip": [],
        "strings": "apple/Shared/Resources",
    },
    "PasrKit": {
        "repo": "app.lrvdlinden.pasr",
        "sources": ["beheer/apple/PasrBeheer"],
        "assets": "beheer/apple/PasrBeheer/Assets.xcassets",
        "asset_name": "Pasr",
        "suite": "pasr",
        "skip": [],
    },
    "P2000Kit": {
        "repo": "p2000-apeldoorn",
        "sources": ["beheer/P2000Beheer"],
        "assets": "beheer/P2000Beheer/Assets.xcassets",
        "asset_name": "P2000",
        "suite": "p2000",
        "skip": [],
    },
}

# Bestand (relatief aan Sources) -> lijst van (oud, nieuw). Elke vervanging moet precies passen, anders stopt het script.
PATCHES = {
    "BingrKit": {
        # Widget-token in de gedeelde Keychain-groep van LRbeheer (de oude groep hoort bij de app-id van BingrBeheer).
        "Shared/WidgetShared.swift": [
            ('private static let groupSuffix = "nl.lrvdlinden.bingr.beheer.shared"',
             'private static let groupSuffix = "app.lrvdlinden.lrbeheer.shared"'),
        ],
    },
    "TunrKit": {
        # Teksten uit de eigen tabel Tunr.strings (LRbeheer heeft zelf Localizable.xcstrings).
        "Core/Localization.swift": [
            ('NSLocalizedString(key, comment: "")', 'NSLocalizedString(key, tableName: "Tunr", comment: "")'),
        ],
    },
    "P2000Kit": {
        # LRbeheer is de delegate van het meldingencentrum voor alle omgevingen (tikken op meldingen, tonen in de app).
        "Services/PushRegistrar.swift": [
            ("        UNUserNotificationCenter.current().delegate = self\n", ""),
        ],
    },
}

APP_ONLY_ASSETS = {"AppIcon.appiconset", "AccentColor.colorset", "LaunchBackground.colorset"}

APPSTORAGE = re.compile(r'@AppStorage\("([^"]+)"\)')


def transform(text: str, keep_main: bool = False) -> str:
    if not keep_main:
        text = re.sub(r"^@main[ \t]*\n", "", text, flags=re.M)
    text = text.replace("UserDefaults.standard", "UserDefaults.module")
    text = APPSTORAGE.sub(r'@AppStorage("\1", store: UserDefaults.module)', text)
    return text


def defaults_file(kit: str, suite: str) -> str:
    return f'''// Gegenereerd door tools/import_modules.py — niet met de hand wijzigen.
import Foundation

extension UserDefaults {{
    /// Eigen UserDefaults-suite van deze beheeromgeving binnen LRbeheer, zodat sleutels van de verschillende
    /// beheerapps (bv. push.device_id, lockEnabled) niet botsen.
    static let module: UserDefaults = UserDefaults(suiteName: "app.lrvdlinden.lrbeheer.{suite}") ?? .standard
}}
'''


def import_module(kit: str, cfg: dict, src_root: Path) -> list[str]:
    repo = src_root / cfg["repo"]
    if not repo.is_dir():
        raise SystemExit(f"Repo niet gevonden: {repo}")
    dest = ROOT / "Modules" / kit / "Sources"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    copied = []
    for rel in cfg["sources"]:
        base = repo / rel
        for f in sorted(base.rglob("*.swift")):
            sub = f.relative_to(base)
            # ios/Shared van Bingr komt onder Shared/, de rest direct onder Sources/
            if rel.endswith("/Shared") and kit == "BingrKit":
                sub = Path("Shared") / sub
            out = dest / sub
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(transform(f.read_text()))
            copied.append(str(sub))
    (dest / "ModuleDefaults.swift").write_text(defaults_file(kit, cfg["suite"]))
    for rel, reps in PATCHES.get(kit, {}).items():
        p = dest / rel
        t = p.read_text()
        for old, new in reps:
            if t.count(old) != 1:
                raise SystemExit(f"Patch past niet in {kit}/{rel}: {old!r}")
            t = t.replace(old, new)
        p.write_text(t)

    # assets
    cat = ROOT / "LRbeheer" / "Resources" / f"{cfg['asset_name']}.xcassets"
    if cat.exists():
        shutil.rmtree(cat)
    shutil.copytree(repo / cfg["assets"], cat, ignore=shutil.ignore_patterns(*APP_ONLY_ASSETS))

    # Tunr: Localizable.strings -> Tunr.strings
    if "strings" in cfg:
        for lang in ("nl", "en"):
            s = repo / cfg["strings"] / f"{lang}.lproj" / "Localizable.strings"
            o = ROOT / "LRbeheer" / "Resources" / f"{lang}.lproj" / "Tunr.strings"
            o.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(s, o)
    return copied


def import_widgets(src_root: Path):
    """Widgets van BingrBeheer (servicestatus, support, overzicht) als widget-extensie van LRbeheer."""
    repo = src_root / "bingr-beheer" / "ios"
    dest = ROOT / "Widgets" / "BingrWidgets"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    privacy = (ROOT / "LRbeheer" / "Resources" / "PrivacyInfo.xcprivacy")
    for f in sorted((repo / "BingrBeheerWidgets").glob("*.swift")):
        # de widget-bundel houdt zijn @main: de extensie is een eigen programma
        (dest / f.name).write_text(transform(f.read_text(), keep_main=True))
    if privacy.exists():
        shutil.copy(privacy, dest / "PrivacyInfo.xcprivacy")
    # zelfde gedeelde bestanden als in ios/project.yml van BingrBeheer (target BingrBeheerWidgets)
    shared = {
        "WidgetShared.swift": repo / "Shared" / "WidgetShared.swift",
        "AdminAPI.swift": repo / "BingrBeheer" / "API" / "AdminAPI.swift",
        "JSON.swift": repo / "BingrBeheer" / "Core" / "JSON.swift",
        "Format.swift": repo / "BingrBeheer" / "Core" / "Format.swift",
        "Theme.swift": repo / "BingrBeheer" / "Core" / "Theme.swift",
    }
    sd = dest / "Shared"
    sd.mkdir()
    for name, p in shared.items():
        t = transform(p.read_text())
        if name == "WidgetShared.swift":
            for old, new in PATCHES["BingrKit"]["Shared/WidgetShared.swift"]:
                t = t.replace(old, new)
        (sd / name).write_text(t)
    (sd / "ModuleDefaults.swift").write_text(defaults_file("BingrWidgets", "bingr"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="map met de clones van de bestaande repo's")
    a = ap.parse_args()
    src = Path(a.src).resolve()
    report = {}
    for kit, cfg in MODULES.items():
        report[kit] = import_module(kit, cfg, src)
        print(f"{kit}: {len(report[kit])} Swift-bestanden")
    import_widgets(src)
    (ROOT / "Modules" / "IMPORT.json").write_text(json.dumps(
        {k: sorted(v) for k, v in report.items()}, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
