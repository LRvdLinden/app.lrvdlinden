#!/usr/bin/env python3
"""App-icoon van LRbeheer (1024 × 1024) en de afbeeldingen voor de asset-catalogus.

Ontwerp: de LR-tegel van lrvdlinden.app (ink #121726, witte L en R, blauwe stip #4C6BFF, zelfde 512-raster als LRLogo in
MoreAppsCard.swift) met een subtiel verloop en rechtsonder een klein raster van vier vlakjes: meerdere beheeromgevingen in
één app. Zelfde ontwerp als BeheerMark in Shell/SplashView.swift.

Gebruik (vanuit beheer/): python3 tools/make_icon.py   (vereist rsvg-convert)
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "LRbeheer" / "Resources" / "Assets.xcassets"


def svg(full_bleed: bool) -> str:
    # 512-raster zoals LRLogo; app-icoon zonder eigen afronding (iOS rondt zelf af)
    radius = 0 if full_bleed else 116
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="1024" height="1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1A2138"/>
      <stop offset="1" stop-color="#0D1018"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.82" cy="0.18" r="0.55">
      <stop offset="0" stop-color="#4C6BFF" stop-opacity="0.35"/>
      <stop offset="1" stop-color="#4C6BFF" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="512" height="512" rx="{radius}" fill="url(#bg)"/>
  <rect width="512" height="512" rx="{radius}" fill="url(#glow)"/>
  <g fill="none" stroke="#FFFFFF" stroke-width="46" stroke-linecap="round" stroke-linejoin="round">
    <path d="M132 146 L132 370 L232 370"/>
    <path d="M292 370 L292 146 L340 146 A62 62 0 0 1 340 270 L292 270"/>
    <path d="M338 270 L390 370"/>
  </g>
  <circle cx="404" cy="126" r="34" fill="#4C6BFF" stroke="#121726" stroke-width="14"/>
  <g transform="translate(398 410)">
    <rect x="0" y="0" width="25" height="25" rx="7" fill="#FFFFFF" fill-opacity="0.95"/>
    <rect x="31" y="0" width="25" height="25" rx="7" fill="#FFFFFF" fill-opacity="0.5"/>
    <rect x="0" y="31" width="25" height="25" rx="7" fill="#FFFFFF" fill-opacity="0.5"/>
    <rect x="31" y="31" width="25" height="25" rx="7" fill="#4C6BFF"/>
  </g>
</svg>"""


def render(svg_text: str, out: Path, size: int):
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".svg")
    tmp.write_text(svg_text)
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(out), str(tmp)], check=True)
    tmp.unlink()


def main():
    render(svg(True), ASSETS / "AppIcon.appiconset" / "icon-1024.png", 1024)
    render(svg(True), ASSETS / "AppIconDisplay.imageset" / "icon.png", 1024)
    render(svg(False), ROOT / "Design" / "LRbeheer-logo.png", 1024)
    (ROOT / "Design").mkdir(exist_ok=True)
    (ROOT / "Design" / "LRbeheer-icon.svg").write_text(svg(True))
    print("iconen geschreven")


if __name__ == "__main__":
    main()
