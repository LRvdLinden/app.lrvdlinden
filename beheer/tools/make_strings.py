#!/usr/bin/env python3
"""Schrijft LRbeheer/Resources/Localizable.xcstrings en InfoPlist.xcstrings (Nederlands = brontaal, plus Engels).

De sleutels zijn de Nederlandse teksten uit de Swift-code van de app (net als in de bestaande beheerapps); de Engelse
vertalingen staan in tools/strings_en.json. Xcode vult bij het bouwen zelf nieuwe sleutels aan; draai dit script na het
toevoegen van vertalingen. De omgevingen zelf (Modules/*) houden hun eigen teksten (Tunr: Tunr.strings, nl + en).
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EN = json.loads((ROOT / "tools" / "strings_en.json").read_text())


def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}


def catalog(entries):
    return {"sourceLanguage": "nl", "version": "1.0", "strings": entries}


def main():
    strings = {}
    for nl, en in sorted(EN.items()):
        strings[nl] = {"localizations": {"en": unit(en), "nl": unit(nl)}}
    out = ROOT / "LRbeheer" / "Resources" / "Localizable.xcstrings"
    out.write_text(json.dumps(catalog(strings), indent=2, ensure_ascii=False) + "\n")

    info = {
        "CFBundleDisplayName": ("LRbeheer", "LRbeheer"),
        "CFBundleName": ("LRbeheer", "LRbeheer"),
        "NSFaceIDUsageDescription": ("LRbeheer gebruikt Face ID om de app en de beheeromgevingen te ontgrendelen.",
                                     "LRbeheer uses Face ID to unlock the app and the admin environments."),
        "NSPhotoLibraryUsageDescription": ("LRbeheer gebruikt je foto's alleen als je een icoon, banner of afbeelding uploadt.",
                                           "LRbeheer only uses your photos when you upload an icon, banner or image."),
    }
    entries = {k: {"localizations": {"nl": unit(nl), "en": unit(en)}} for k, (nl, en) in info.items()}
    (ROOT / "LRbeheer" / "Resources" / "InfoPlist.xcstrings").write_text(
        json.dumps(catalog(entries), indent=2, ensure_ascii=False) + "\n")
    print(f"{len(strings)} teksten, {len(entries)} Info.plist-teksten")


if __name__ == "__main__":
    main()
