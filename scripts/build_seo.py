"""Bij elke release: sitemap.xml maken en gestructureerde gegevens (JSON-LD) in index.html zetten.

Gebruik: python3 scripts/build_seo.py build
Leest build/apps.json, schrijft build/sitemap.xml en vervangt <!--SEO-JSONLD--> in build/index.html.
"""
import json, os, re, sys
from datetime import datetime, timezone

BASE = "https://lrvdlinden.app/"
out = sys.argv[1] if len(sys.argv) > 1 else "build"
apps = json.load(open(os.path.join(out, "apps.json"), encoding="utf-8")).get("apps", [])
today = datetime.now(timezone.utc).strftime("%Y-%m-%d")


def L(v, lang="nl"):
    if isinstance(v, dict):
        return v.get(lang) or v.get("nl") or v.get("en") or ""
    return v or ""


def last_date(a):
    return max([h.get("date") or "" for h in a.get("history") or []] + [""])


# ---------- sitemap.xml ----------
import subprocess


def git_date(path):
    """Datum van de laatste commit van een bestand: alleen echte inhoudswijzigingen tellen."""
    try:
        out = subprocess.run(["git", "log", "-1", "--format=%cs", "--", path], capture_output=True, text=True).stdout.strip()
        return out or None
    except OSError:
        return None


home_mod = max([last_date(a) for a in apps] + [git_date("site/index.html") or ""]) or today
pages = [("", home_mod)]
for name in ("donate", "privacy"):  # nette URL's zonder .html
    if os.path.isfile(os.path.join(out, name + ".html")):
        pages.append((name, git_date(f"site/{name}.html") or today))
# eigen app-pagina's (gemaakt door scripts/build_app_pages.py)
try:
    for pg in json.load(open(os.path.join(out, "app", "pages.json"), encoding="utf-8")):
        pages.append((f"app/{pg['slug']}/", pg.get("lastmod") or today))
except (OSError, ValueError):
    pass
xml = ['<?xml version="1.0" encoding="UTF-8"?>',
       '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">']
for path, mod in pages:
    xml.append(f"  <url>\n    <loc>{BASE}{path}</loc>\n    <lastmod>{mod[:10]}</lastmod>")
    if path == "":
        xml.append(f"    <image:image><image:loc>{BASE}og-image.jpg</image:loc></image:image>")
    xml.append("  </url>")
xml.append("</urlset>")
open(os.path.join(out, "sitemap.xml"), "w", encoding="utf-8").write("\n".join(xml) + "\n")

# ---------- JSON-LD ----------
CAT = {"utilities": "UtilitiesApplication", "entertainment": "EntertainmentApplication", "news": "NewsApplication",
       "business": "BusinessApplication", "lifestyle": "LifestyleApplication", "games": "GameApplication",
       "music": "MultimediaApplication", "productivity": "BusinessApplication", "health": "HealthApplication",
       "education": "EducationalApplication", "travel": "TravelApplication", "weather": "UtilitiesApplication",
       "sports": "SportsApplication", "photo": "MultimediaApplication", "navigation": "TravelApplication",
       "finance": "FinanceApplication", "reference": "ReferenceApplication", "social": "SocialNetworkingApplication",
       "developer": "DeveloperApplication", "design": "DesignApplication", "shopping": "ShoppingApplication"}
person = {"@type": "Person", "@id": BASE + "#leon", "name": "Léon van der Linden", "url": BASE,
          "sameAs": ["https://github.com/LRvdLinden",
                     "https://apps.apple.com/nl/developer/leon-van-der-linden/id607860328",
                     "https://homey.app/nl-nl/apps/author/5d4da77a2c836a50f6936070/page/0/"]}
items = []
for a in apps:
    links = a.get("links") or {}
    homey = a.get("section") == "homey"
    url = links.get("homey") if homey else links.get("appstore")
    if a.get("status") != "live" or not url:
        continue
    app = {"@type": "SoftwareApplication", "name": a["name"],
           "description": L(a.get("description")) or L(a.get("subtitle")),
           "applicationCategory": "HomeApplication" if homey else CAT.get(a.get("category"), "UtilitiesApplication"),
           "operatingSystem": "Homey" if homey else "iOS",
           "url": url, "author": {"@id": BASE + "#leon"},
           "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"}}
    if a.get("icon"):
        app["image"] = BASE + a["icon"]
    if (a.get("history") or [{}])[0].get("version"):
        app["softwareVersion"] = str(a["history"][0]["version"])
    if a.get("rating") and int(a.get("reviews") or 0) > 0:
        app["aggregateRating"] = {"@type": "AggregateRating", "ratingValue": a["rating"], "ratingCount": int(a["reviews"])}
    items.append({"@type": "ListItem", "position": len(items) + 1, "item": app})
graph = {"@context": "https://schema.org", "@graph": [
    {"@type": "WebSite", "@id": BASE + "#site", "url": BASE, "name": "LRvdLinden Apps", "inLanguage": ["nl", "en"],
     "publisher": {"@id": BASE + "#leon"}},
    person,
    {"@type": "ItemList", "name": "Apps van Léon van der Linden", "itemListElement": items}]}
ld = '<script type="application/ld+json">' + json.dumps(graph, ensure_ascii=False).replace("</", "<\\/") + "</script>"
p = os.path.join(out, "index.html")
html = open(p, encoding="utf-8").read()
html = html.replace("<!--SEO-JSONLD-->", ld, 1)
open(p, "w", encoding="utf-8").write(html)
print(f"sitemap.xml: {len(pages)} pagina's, JSON-LD: {len(items)} apps")
