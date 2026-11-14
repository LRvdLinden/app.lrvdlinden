"""Maakt bij elke release een eigen pagina per app: /app/<naam>/ voor iOS, /homey/<naam>/ voor Homey (NL en EN).

Bronnen: build/apps.json (wat in beheer en de store-check staat) en build/app-content/<slug>/content.json
(screenshots, App Store-teksten en deelafbeelding uit de content-repo, bijgehouden door scripts/sync_app_content.py).

Gebruik: python3 scripts/build_app_pages.py build
"""
import html
import json
import os
import re
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from appslug import content_key, legacy_homey_path, page_path  # noqa: E402
from platform_icons import name as plat_name, svg as plat_svg  # noqa: E402

BASE = "https://lrvdlinden.app"
OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
apps = json.load(open(os.path.join(OUT, "apps.json"), encoding="utf-8")).get("apps", [])

T = {
    "nl": dict(by="Léon van der Linden", back="Alle apps", appstore="Gratis in de App Store", testflight="Doe mee via TestFlight",
               website="Website", homey="Bekijk in de Homey App Store", homeyTest="Testversie installeren", shots="Screenshots",
               about="Over {n}", news="Wat is nieuw", more="Meer apps", devices="Apparaten", widgets="Widgets",
               flow="Flow-kaarten", when="Als…", andd="En…", then="Dan…", rating="Beoordeling", reviews="beoordelingen",
               version="Versie", size="Grootte", language="Talen", category="Categorie", platforms="Werkt op",
               free="Gratis · zonder advertenties", live="In de App Store", beta="Open beta", dev="In ontwikkeling",
               hlive="Live", htest="Test", donate="Doneren", privacy="Privacy", support="Steun mijn apps",
               nlonly="Deze app is alleen in het Nederlands beschikbaar.", allv="Toon alle versies", lessv="Toon minder",
               allc="Toon alle {n}", support_link="Ondersteuning"),
    "en": dict(by="Léon van der Linden", back="All apps", appstore="Free on the App Store", testflight="Join on TestFlight",
               website="Website", homey="View in the Homey App Store", homeyTest="Install test version", shots="Screenshots",
               about="About {n}", news="What's new", more="More apps", devices="Devices", widgets="Widgets",
               flow="Flow cards", when="When…", andd="And…", then="Then…", rating="Rating", reviews="ratings",
               version="Version", size="Size", language="Languages", category="Category", platforms="Works on",
               free="Free · no ads", live="On the App Store", beta="Open beta", dev="In development",
               hlive="Live", htest="Test", donate="Donate", privacy="Privacy", support="Support my apps",
               nlonly="This app is only available in Dutch.", allv="Show all versions", lessv="Show less",
               allc="Show all {n}", support_link="Support"),
}
CATS = {
    "nl": {"utilities": "Hulpmiddelen", "entertainment": "Amusement", "news": "Nieuws", "business": "Zakelijk", "lifestyle": "Lifestyle",
           "games": "Games", "music": "Muziek", "productivity": "Productiviteit", "health": "Gezondheid", "education": "Onderwijs",
           "travel": "Reizen", "weather": "Weer", "sports": "Sport", "photo": "Foto en video", "navigation": "Navigatie",
           "finance": "Financiën", "reference": "Naslag", "social": "Sociaal", "food": "Eten en drinken", "books": "Boeken",
           "developer": "Ontwikkelaarstools", "design": "Grafisch en ontwerp", "shopping": "Winkelen", "kids": "Kinderen",
           "appliances": "Apparaten", "climate": "Klimaat", "energy": "Energie", "internet": "Internet", "lights": "Verlichting",
           "localization": "Locatie", "security": "Veiligheid", "tools": "Hulpmiddelen", "video": "Video"},
    "en": {"utilities": "Utilities", "entertainment": "Entertainment", "news": "News", "business": "Business", "lifestyle": "Lifestyle",
           "games": "Games", "music": "Music", "productivity": "Productivity", "health": "Health", "education": "Education",
           "travel": "Travel", "weather": "Weather", "sports": "Sports", "photo": "Photo & Video", "navigation": "Navigation",
           "finance": "Finance", "reference": "Reference", "social": "Social", "food": "Food & Drink", "books": "Books",
           "developer": "Developer Tools", "design": "Graphics & Design", "shopping": "Shopping", "kids": "Kids",
           "appliances": "Appliances", "climate": "Climate", "energy": "Energy", "internet": "Internet", "lights": "Lights",
           "localization": "Localization", "security": "Security", "tools": "Tools", "video": "Video"},
}
CAT_LD = {"entertainment": "EntertainmentApplication", "news": "NewsApplication", "business": "BusinessApplication",
          "lifestyle": "LifestyleApplication", "games": "GameApplication", "music": "MultimediaApplication",
          "health": "HealthApplication", "education": "EducationalApplication", "travel": "TravelApplication",
          "sports": "SportsApplication", "finance": "FinanceApplication", "social": "SocialNetworkingApplication",
          "developer": "DeveloperApplication", "design": "DesignApplication", "shopping": "ShoppingApplication"}
MONTHS = {"nl": ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"],
          "en": ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]}

e = lambda s: html.escape(str(s if s is not None else ""), quote=True)


def L(v, lang):
    if isinstance(v, dict):
        return v.get(lang) or v.get("nl") or v.get("en") or ""
    return v or ""


def date(d, lang):
    m = re.match(r"(\d{4})-(\d\d)-(\d\d)", d or "")
    return f"{int(m[3])} {MONTHS[lang][int(m[2]) - 1]} {m[1]}" if m else e(d)


def paras(text):
    """Platte App Store-tekst naar HTML: kopjes in hoofdletters, opsommingen als lijst, de rest als alinea's."""
    out = []
    bullet = re.compile(r"^[•\-–*·]\s*")
    for block in re.split(r"\n\s*\n", (text or "").strip()):
        lines = [l.strip() for l in block.splitlines() if l.strip()]
        buf, items = [], []

        def flush():
            if buf:
                out.append("<p>" + "<br>".join(e(x) for x in buf) + "</p>")
                buf.clear()
            if items:
                out.append("<ul>" + "".join(f"<li>{e(x)}</li>" for x in items) + "</ul>")
                items.clear()
        for l in lines:
            if bullet.match(l):
                if buf:
                    flush()
                items.append(bullet.sub("", l))
            elif len(l) <= 48 and l.upper() == l and re.search(r"[A-Z]", l):
                flush()
                out.append(f'<h3 class="ph">{e(l.capitalize())}</h3>')
            else:
                if items:
                    flush()
                buf.append(l)
        flush()
    return "".join(out)


def flow_title(t):
    t = re.sub(r"!\{\{([^|}]*)\|[^}]*\}\}", r"\1", str(t or ""))
    return re.sub(r"\[\[[^\]]*\]\]", "…", t)


def homey_versions(a):
    x = a.get("homey") or {}
    hist = a.get("history") or []
    live = x.get("live") or (next((h.get("version") for h in hist if not h.get("test")), None) if a.get("status") == "live" else None)
    test = x.get("test") or ((hist[0].get("version") if hist else None) if a.get("status") != "live" else None)
    if test and live and str(test) == str(live):
        test = None
    return live, test


def buttons(a, lang):
    t, l, out = T[lang], a.get("links") or {}, []
    if a.get("section") == "homey":
        live, test = homey_versions(a)
        hurl = l.get("homey")
        if live and hurl:
            out.append((hurl, t["homey"], "primary"))
        turl = l.get("homeyTest") or (hurl if a.get("status") != "live" else None)
        if test and turl:
            out.append((turl.replace("/nl-nl/", "/nl-nl/" if lang == "nl" else "/en-us/"), f'{t["homeyTest"]} v{test}', "" if out else "primary"))
    else:
        if l.get("appstore"):
            out.append((l["appstore"], t["appstore"], "primary"))
        if l.get("testflight"):
            out.append((l["testflight"], t["testflight"], "" if out else "primary"))
    if l.get("website"):
        out.append((l["website"], t["website"], "" if out else "primary"))
    hx = a.get("homey") or {}
    if hx.get("support") and a.get("section") == "homey":
        sup = hx["support"]
        sup = sup if str(sup).startswith("http") else ("mailto:" + sup if "@" in str(sup) else "")
        if sup:
            out.append((sup, t["support_link"], ""))
    return "".join(f'<a class="btn {c}" href="{e(u)}" target="_blank" rel="noopener">{e(x)}</a>' for u, x, c in out)


def status_pill(a, lang):
    st = a.get("status") or "dev"
    if a.get("section") == "homey":
        return "" if st == "live" else f'<span class="pill beta">{e(T[lang]["htest"])}</span>'
    return f'<span class="pill {e(st)}">{e(T[lang][st] if st in T[lang] else st)}</span>'


def facts(a, lang):
    t, rows = T[lang], []
    if a.get("rating"):
        rv = f' <small>({a.get("reviews")} {t["reviews"]})</small>' if a.get("reviews") else ""
        rows.append((t["rating"], f'<span class="stars" aria-hidden="true">★</span> {str(a["rating"]).replace(".", "," if lang == "nl" else ".")}{rv}'))
    if a.get("section") == "homey":
        live, test = homey_versions(a)
        v = (f'<span class="vtag live">{t["hlive"]} v{e(live)}</span>' if live else "") + (f' <span class="vtag test">{t["htest"]} v{e(test)}</span>' if test else "")
        if v:
            rows.append((t["version"], v))
    elif a.get("history"):
        rows.append((t["version"], f'<span class="mono">{e(a["history"][0].get("version"))}</span>'))
    cat = (a.get("homey") or {}).get("category") if a.get("section") == "homey" else a.get("category")
    if cat:
        rows.append((t["category"], e(CATS[lang].get(cat, cat))))
    if a.get("size"):
        rows.append((t["size"], e(a["size"])))
    if a.get("languages"):
        rows.append((t["language"], e(a["languages"])))
    return "".join(f"<div><dt>{e(k)}</dt><dd>{v}</dd></div>" for k, v in rows)


def homey_blocks(a, lang):
    t, x, out = T[lang], a.get("homey") or {}, []
    drivers = x.get("drivers") or []
    if drivers:
        figs = []
        for d in drivers:
            img = d.get("image") or d.get("icon")
            pic = f'<img src="{e(img)}" alt="" loading="lazy">' if img else ""
            figs.append(f'<figure>{pic}<figcaption>{e(L(d.get("name"), lang))}</figcaption></figure>')
        out.append(f'<section class="block"><h2>{t["devices"]} <small>{len(drivers)}</small></h2><div class="drivers">{"".join(figs)}</div></section>')
    widgets = x.get("widgets") or []
    if widgets:
        figs = []
        for w in widgets:
            light, dark = w.get("light"), w.get("dark") or w.get("light")
            pics = (f'<img class="wl" src="{e(light)}" alt="" loading="lazy">' if light else "") + \
                   (f'<img class="wd" src="{e(dark)}" alt="" loading="lazy">' if dark else "")
            figs.append(f'<figure>{pics}<figcaption>{e(L(w.get("name"), lang))}</figcaption></figure>')
        out.append(f'<section class="block"><h2>{t["widgets"]} <small>{len(widgets)}</small></h2><div class="widgets">{"".join(figs)}</div></section>')
    f = x.get("flow") or {}
    cols = []
    for key, label in (("triggers", t["when"]), ("conditions", t["andd"]), ("actions", t["then"])):
        cards = f.get(key) or []
        if cards:
            items = "".join(f'<li class="{"more" if i >= 8 else ""}">{e(flow_title(L(c.get("title"), lang)))}</li>' for i, c in enumerate(cards))
            more = f'<button type="button" class="showall" data-a="{e(t["allc"].format(n=len(cards)))}" data-b="{e(t["lessv"])}">{e(t["allc"].format(n=len(cards)))}</button>' if len(cards) > 8 else ""
            cols.append(f'<div class="fcol {key}"><h3>{e(label)} <small>{len(cards)}</small></h3><ol>{items}</ol>{more}</div>')
    if cols:
        n = sum(len(f.get(k) or []) for k in ("triggers", "conditions", "actions"))
        out.append(f'<section class="block"><h2>{t["flow"]} <small>{n}</small></h2><div class="flow">{"".join(cols)}</div></section>')
    return "".join(out)


def page_content(a, c, lang, others):
    t = T[lang]
    name = a["name"]
    slug = c["ckey"]
    sub = L(a.get("subtitle"), lang)
    text = (c.get("text") or {}).get(lang) or {}
    long_desc = text.get("description") or ""
    promo = text.get("promotional_text") or ""
    short = L(a.get("description"), lang)
    shots = (c.get("shots") or {}).get(lang) or (c.get("shots") or {}).get("nl" if lang == "en" else "en") or []
    hist = [h for h in (a.get("history") or []) if L(h.get("notes"), lang)]
    plats = a.get("platforms") or ((a.get("homey") or {}).get("platforms") or ["Homey"] if a.get("section") == "homey" else [])

    hero = f'''
  <section class="hero wrap">
    <a class="crumb" href="/#{"homey" if a.get("section") == "homey" else "apps"}">← {e(t["back"])}</a>
    <div class="head">
      <span class="icon">{e(re.sub(r"[^A-Za-z0-9]", "", name)[:2])}{f'<img src="/{e(a["icon"])}" alt="{e(name)}" width="256" height="256">' if a.get("icon") else ""}</span>
      <div class="title">
        <h1>{e(name)}</h1>
        {f'<p class="sub">{e(sub)}</p>' if sub else ""}
        <div class="by">{e(t["by"])} {status_pill(a, lang)}</div>
      </div>
    </div>
    <div class="btns">{buttons(a, lang)}</div>
    <dl class="facts">{facts(a, lang)}</dl>
    {f'<div class="plat"><span class="lbl">{e(t["platforms"])}</span>' + "".join(f'<span class="tag ostag">{plat_svg(p)}{e(plat_name(p))}</span>' for p in plats) + "</div>" if plats else ""}
    {f'<p class="note">{e(t["nlonly"])}</p>' if a.get("nlOnly") and lang == "en" else ""}
  </section>'''
    shots_html = ""
    if shots:
        shots_html = f'''
  <section class="block wrap"><h2>{e(t["shots"])}</h2>
    <div class="shots" tabindex="0" aria-label="{e(t["shots"])}">{"".join(f'<img src="/app-content/{e(slug)}/{e(s["src"])}" alt="{e(name)} screenshot {i}" width="{s["w"]}" height="{s["h"]}" loading="{"eager" if i <= 2 else "lazy"}" decoding="async">' for i, s in enumerate(shots, 1))}</div>
  </section>'''
    about_body = (f'<p class="promo">{e(promo)}</p>' if promo else "") + (paras(long_desc) if long_desc else (f"<p>{e(short)}</p>" if short else ""))
    about = f'<section class="block wrap"><h2>{e(t["about"].format(n=name))}</h2><div class="prose">{about_body}</div></section>' if about_body else ""
    homey = f'<div class="wrap">{homey_blocks(a, lang)}</div>' if a.get("section") == "homey" else ""
    news = ""
    if hist:
        items = []
        for i, h in enumerate(hist[:10]):
            pill = f' <span class="pill beta">{e(t["htest"])}</span>' if h.get("test") else ""
            notes = "<br>".join(e(x) for x in L(h.get("notes"), lang).splitlines())
            items.append(f'<li class="{"more" if i >= 3 else ""}"><div><span class="mono">{e(h.get("version"))}{pill}</span>'
                         f'<span class="d">{date(h.get("date"), lang)}</span></div><p>{notes}</p></li>')
        more = f'<button type="button" class="showall" data-a="{e(t["allv"])}" data-b="{e(t["lessv"])}">{e(t["allv"])}</button>' if len(hist) > 3 else ""
        news = f'<section class="block wrap"><h2>{e(t["news"])}</h2><ol class="news">{"".join(items)}</ol>{more}</section>'
    minis = []
    for o, path in others:
        init = e(re.sub(r"[^A-Za-z0-9]", "", o["name"])[:2])
        pic = f'<img src="/{e(o["icon"])}" alt="" loading="lazy">' if o.get("icon") else ""
        sub_o = L(o.get("subtitle"), lang) or CATS[lang].get(o.get("category") or "", "Homey")
        minis.append(f'<a class="mini" href="{e(path)}"><span class="icon sm">{init}{pic}</span><span><b>{e(o["name"])}</b><small>{e(sub_o)}</small></span></a>')
    more_apps = "".join(minis)
    more = f'<section class="block wrap"><h2>{e(t["more"])}</h2><div class="minis">{more_apps}</div></section>' if more_apps else ""
    return hero + shots_html + about + homey + news + more


def page(a, c, others, lang):
    """Eén pagina in één taal. NL op /app/<naam>/, EN op /en/app/<naam>/, met eigen titel, tekst en OG."""
    t = T[lang]
    slug = c["ckey"]
    pre = "/en" if lang == "en" else ""
    url = BASE + pre + c["path"]
    url_nl, url_en = BASE + c["path"], BASE + "/en" + c["path"]
    has_en = not a.get("nlOnly")
    body = page_content(a, c, lang, [(o, ("/en" if lang == "en" and not o.get("nlOnly") else "") + p) for o, p in others])
    body = body.replace('href="/#', f'href="{pre}/#')
    name = a["name"]
    sub = L(a.get("subtitle"), lang)
    desc_src = ((c.get("text") or {}).get(lang) or {}).get("promotional_text") or L(a.get("description"), lang) or sub
    desc = re.sub(r"\s+", " ", desc_src).strip()
    if len(desc) > 158:
        desc = desc[:155].rsplit(" ", 1)[0] + "…"
    title = f"{name}" + (f": {sub}" if sub else "") + " | LRvdLinden Apps"
    if len(title) > 65:
        title = f"{name} | LRvdLinden Apps"
    og = c.get("og") or {}
    og_nl = f"{BASE}/app-content/{slug}/{og['nl']}" if og.get("nl") else f"{BASE}/og-image.jpg"
    og_en = f"{BASE}/app-content/{slug}/{og['en']}" if og.get("en") else f"{BASE}/og-image-en.jpg"
    og_img = og_en if lang == "en" else og_nl
    homey = a.get("section") == "homey"
    links = a.get("links") or {}
    ld_app = {"@type": "SoftwareApplication", "name": name, "url": url, "inLanguage": lang,
              "description": L(a.get("description"), lang) or sub,
              "applicationCategory": "HomeApplication" if homey else CAT_LD.get(a.get("category"), "UtilitiesApplication"),
              "operatingSystem": "Homey" if homey else ", ".join(p for p in (a.get("platforms") or ["iOS"]) if p) or "iOS",
              "author": {"@type": "Person", "name": "Léon van der Linden", "url": BASE + "/"},
              "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"}}
    if a.get("icon"):
        ld_app["image"] = f"{BASE}/{a['icon']}"
    shots = (c.get("shots") or {}).get(lang) or (c.get("shots") or {}).get("nl") or []
    if shots:
        ld_app["screenshot"] = [f"{BASE}/app-content/{slug}/{s['src']}" for s in shots[:4]]
    if a.get("history"):
        ld_app["softwareVersion"] = str(a["history"][0].get("version"))
    if a.get("rating") and int(a.get("reviews") or 0) > 0:
        ld_app["aggregateRating"] = {"@type": "AggregateRating", "ratingValue": a["rating"], "ratingCount": int(a["reviews"])}
    if links.get("appstore") or links.get("homey"):
        ld_app["installUrl"] = links.get("appstore") or links.get("homey")
    ld = {"@context": "https://schema.org", "@graph": [ld_app, {"@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "LRvdLinden Apps", "item": BASE + pre + "/"},
        {"@type": "ListItem", "position": 2, "name": name, "item": url}]}]}
    ld_s = json.dumps(ld, ensure_ascii=False).replace("</", "<\\/")
    alt = (f'<link rel="alternate" hreflang="nl" href="{url_nl}">\n<link rel="alternate" hreflang="en" href="{url_en}">\n'
           f'<link rel="alternate" hreflang="x-default" href="{url_nl}">') if has_en else ""
    tx = {"nl": dict(apps="iOS-apps", donate="Doneren", all="Alle apps", support="Steun mijn apps",
                     supportText="Al mijn apps zijn gratis en zonder advertenties. Met een kleine donatie help je ze online en up-to-date te houden."),
          "en": dict(apps="iOS apps", donate="Donate", all="All apps", support="Support my apps",
                     supportText="All my apps are free and ad-free. A small donation helps keep them online and up to date.")}[lang]
    switch = "" if not has_en else (
        f'<div class="lang" role="group" aria-label="Taal / Language">'
        f'<a href="{e(c["path"])}" lang="nl" aria-current="{"true" if lang == "nl" else "false"}">NL</a>'
        f'<a href="{e("/en" + c["path"])}" lang="en" aria-current="{"true" if lang == "en" else "false"}">EN</a></div>')
    return f'''<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<!-- Start cookieyes banner --> <script id="cookieyes" type="text/javascript" src="https://cdn-cookieyes.com/client_data/1471e3c42ec503ecd9bd0f17/script.js"></script> <!-- End cookieyes banner -->
<title>{e(title)}</title>
<meta name="description" content="{e(desc)}">
<meta name="author" content="Léon van der Linden">
<meta name="robots" content="index, follow, max-image-preview:large">
<link rel="canonical" href="{url}">
{alt}
<meta name="theme-color" content="#F3F5F9" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0D1018" media="(prefers-color-scheme: dark)">
<meta property="og:type" content="website">
<meta property="og:site_name" content="LRvdLinden Apps">
<meta property="og:url" content="{url}">
<meta property="og:title" content="{e(name + (": " + sub if sub else ""))}">
<meta property="og:description" content="{e(desc)}">
<meta property="og:image" content="{e(og_img)}">
<meta property="og:image:type" content="image/jpeg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="{e(name)}{e(" – " + sub if sub else "")}">
<meta property="og:locale" content="{"en_GB" if lang == "en" else "nl_NL"}">
<meta property="og:locale:alternate" content="{"nl_NL" if lang == "en" else "en_GB"}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{e(name + (": " + sub if sub else ""))}">
<meta name="twitter:description" content="{e(desc)}">
<meta name="twitter:image" content="{e(og_img)}">
<link rel="icon" type="image/svg+xml" href="/logo.svg">
<link rel="manifest" href="/site.webmanifest">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700;12..96,800&family=Hanken+Grotesk:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<script type="application/ld+json">{ld_s}</script>
<style>{CSS}</style>
</head>
<body>
<header class="top wrap">
  <div class="bar">
    <a class="brand" href="{pre}/">{LOGO} lrvdlinden.app</a>
    <div class="right">
      <nav aria-label="Menu"><a href="{pre}/#apps">{tx["apps"]}</a><a href="{pre}/#homey">Homey</a><a href="/donate">{tx["donate"]}</a></nav>
      {switch}
    </div>
  </div>
</header>
<main>
{body}
<section class="wrap support"><p>{e(tx["supportText"])}</p><a class="btn primary" href="/donate">{e(tx["support"])}</a></section>
</main>
<footer class="wrap"><div class="bar">
  <span>© lrvdlinden.app, Léon van der Linden. Powered by <a href="https://pixelforges.nl" target="_blank" rel="noopener">PixelForges</a></span>
  <nav><a href="{pre}/">{e(tx["all"])}</a><a href="/privacy">Privacy</a><a href="/donate">{e(tx["donate"])}</a></nav>
</div></footer>
<script>try{{localStorage.setItem("lr-lang","{lang}")}}catch(e){{}}{JS}</script>
</body>
</html>
'''


LOGO = ('<svg viewBox="0 0 512 512" aria-hidden="true"><rect width="512" height="512" rx="116" fill="#121726"/><g fill="none" stroke="#fff" '
        'stroke-width="46" stroke-linecap="round" stroke-linejoin="round"><path d="M132 146V370H232"/><path d="M292 370V146H340A62 62 0 0 1 340 270H292"/>'
        '<path d="M338 270L390 370"/></g><circle cx="404" cy="126" r="34" fill="#4C6BFF" stroke="#121726" stroke-width="14"/></svg>')

CSS = """
:root{--bg:#F3F5F9;--surface:#FFFFFF;--ink:#121726;--muted:#5D6578;--line:#DDE2EC;--accent:#2747E8;--accent-soft:#E6EBFF;
--build:#B45309;--build-soft:#FDF0DE;--beta:#0F766E;--beta-soft:#E0F4F1;--star:#E3A008;--on-accent:#FFFFFF;
--f-display:"Bricolage Grotesque","Avenir Next",system-ui,sans-serif;--f-body:"Hanken Grotesk",system-ui,-apple-system,"Segoe UI",sans-serif;
--f-mono:"JetBrains Mono",ui-monospace,"SF Mono",Menlo,monospace}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#0D1018;--surface:#161B27;--ink:#E9ECF4;--muted:#98A0B3;--line:#262D3D;
--accent:#8A9DFF;--accent-soft:#1D2547;--build:#F0B162;--build-soft:#33260F;--beta:#5EC8B8;--beta-soft:#13302C;--star:#F5C04A;--on-accent:#0D1018;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#0D1018;--surface:#161B27;--ink:#E9ECF4;--muted:#98A0B3;--line:#262D3D;--accent:#8A9DFF;--accent-soft:#1D2547;
--build:#F0B162;--build-soft:#33260F;--beta:#5EC8B8;--beta-soft:#13302C;--star:#F5C04A;--on-accent:#0D1018;color-scheme:dark}
*{box-sizing:border-box}html,body{margin:0}
body{background:var(--bg);color:var(--ink);font:400 16px/1.55 var(--f-body);-webkit-font-smoothing:antialiased}
.wrap{max-width:1120px;margin:0 auto;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}
a{color:inherit}:focus-visible{outline:2px solid var(--accent);outline-offset:3px;border-radius:6px}
h1,h2,h3{font-family:var(--f-display);text-wrap:balance;margin:0}
[hidden]{display:none!important}
header.top{padding-block:24px 8px}
.bar{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:10px;text-decoration:none;font-family:var(--f-display);font-weight:700;font-size:18px}
.brand svg{width:36px;height:36px;display:block}
.right{display:flex;align-items:center;gap:20px;flex-wrap:wrap}
.right nav{display:flex;gap:18px;font-size:14.5px;color:var(--muted)}.right nav a{text-decoration:none}.right nav a:hover{color:var(--ink)}
.lang{display:inline-flex;border:1px solid var(--line);border-radius:99px;padding:3px;background:var(--surface)}
.lang a{font:600 12.5px var(--f-body);letter-spacing:.04em;text-decoration:none;color:var(--muted);padding:5px 11px;border-radius:99px}
.lang a[aria-current="true"]{background:var(--ink);color:var(--bg)}
.hero{padding-block:28px 12px}
.crumb{display:inline-block;color:var(--muted);text-decoration:none;font-size:14px;margin-bottom:22px}.crumb:hover{color:var(--ink)}
.head{display:grid;grid-template-columns:auto minmax(0,1fr);gap:24px;align-items:center}
.icon{width:128px;height:128px;border-radius:29px;flex:none;position:relative;overflow:hidden;display:grid;place-items:center;font-family:var(--f-display);font-weight:800;font-size:40px;color:#fff;background:var(--ink);box-shadow:0 14px 36px -16px rgba(18,23,38,.45)}
.icon img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block}
.icon.sm{width:52px;height:52px;border-radius:12px;font-size:18px;box-shadow:none}
.title h1{font-size:clamp(34px,5.4vw,56px);line-height:1.02;font-weight:800;letter-spacing:-.03em}
.sub{margin:8px 0 0;font-size:clamp(17px,2vw,21px);color:var(--muted)}
.by{margin-top:12px;display:flex;align-items:center;gap:10px;flex-wrap:wrap;font-size:14px;color:var(--muted)}
.pill{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:600;padding:4px 10px;border-radius:99px;background:var(--build-soft);color:var(--build)}
.pill.live{background:var(--accent-soft);color:var(--accent)}.pill.beta{background:var(--beta-soft);color:var(--beta)}
.pill::before{content:"";width:6px;height:6px;border-radius:50%;background:currentColor}
.btns{display:flex;gap:10px;flex-wrap:wrap;margin-top:26px}
.btn{display:inline-flex;align-items:center;gap:8px;font:600 15px var(--f-body);padding:11px 20px;border-radius:99px;text-decoration:none;border:1px solid var(--line);background:var(--surface);color:var(--ink);cursor:pointer}
.btn:hover{border-color:var(--muted)}.btn.primary{background:var(--accent);border-color:var(--accent);color:var(--on-accent)}
.facts{display:flex;flex-wrap:wrap;gap:0;margin:28px 0 0;border-block:1px solid var(--line)}
.facts div{padding:14px 26px 14px 0;margin-right:26px;border-right:1px solid var(--line)}.facts div:last-child{border-right:0}
.facts dt{font-size:11.5px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}
.facts dd{margin:4px 0 0;font-weight:600}.facts small{font-weight:500;color:var(--muted)}
.stars{color:var(--star)}.mono{font-family:var(--f-mono);font-size:14px}
.vtag{display:inline-flex;align-items:center;gap:5px;font-family:var(--f-mono);font-size:14px;white-space:nowrap}
.vtag::before{content:"";width:6px;height:6px;border-radius:50%;background:var(--accent)}.vtag.test{color:var(--beta)}.vtag.test::before{background:var(--beta)}
.plat{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-top:18px}
.plat .lbl{font-size:13px;color:var(--muted);margin-right:4px}
.tag{font-size:12.5px;padding:3px 9px;border-radius:7px;border:1px solid var(--line);color:var(--muted);white-space:nowrap}
.ostag{display:inline-flex;align-items:center;gap:7px;padding:6px 12px 6px 9px;border-radius:10px;color:var(--ink);font-size:13.5px;font-weight:600}
.ostag svg{width:20px;height:20px;flex:none}
.note{margin:16px 0 0;color:var(--muted);font-size:14px}
.block{padding-block:34px 4px}
.block h2{font-size:clamp(22px,2.6vw,28px);font-weight:700;letter-spacing:-.02em;margin-bottom:16px}
.block h2 small{font:500 15px var(--f-body);color:var(--muted);letter-spacing:0}
.shots{display:flex;gap:14px;overflow-x:auto;scroll-snap-type:x mandatory;padding-bottom:12px;scrollbar-width:thin}
.shots img{height:min(560px,72vh);width:auto;flex:none;border-radius:22px;scroll-snap-align:start;border:1px solid var(--line);background:var(--surface)}
.prose{max-width:72ch;color:var(--ink)}.prose p{margin:0 0 14px}.prose ul{margin:0 0 14px;padding-left:20px}.prose li{margin:4px 0}
.prose .promo{font-size:18px;font-weight:500}
.prose .ph{font:700 17px var(--f-display);margin:22px 0 6px}
.news{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:14px;max-width:820px}
.news li{display:grid;grid-template-columns:150px minmax(0,1fr);gap:16px;padding:16px 18px;background:var(--surface);border:1px solid var(--line);border-radius:16px}
.news li>div{display:flex;flex-direction:column;gap:4px}.news .d{font-size:13px;color:var(--muted)}
.news p{margin:0;color:var(--muted);font-size:15px}
.news li.more,.fcol li.more{display:none}.open .news li.more{display:grid}.fcol.open li.more{display:list-item}
.showall{margin-top:12px;font:600 14px var(--f-body);background:none;border:0;color:var(--accent);cursor:pointer;padding:4px 0}
.drivers{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px}
.drivers figure{margin:0;background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:16px;display:flex;flex-direction:column;align-items:center;gap:10px;text-align:center}
.drivers img{width:64px;height:64px;object-fit:contain}.drivers figcaption{font-size:14px;font-weight:600}
.widgets{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}
.widgets figure{margin:0;background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:12px}
.widgets img{width:100%;border-radius:10px;display:block}.widgets figcaption{font-size:14px;font-weight:600;margin-top:8px}
.widgets .wd{display:none}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]) .widgets .wl{display:none}:root:not([data-theme="light"]) .widgets .wd{display:block}}
.flow{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}
.fcol{background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:16px 18px}
.fcol h3{font:600 13px var(--f-body);letter-spacing:.06em;text-transform:uppercase;margin-bottom:8px}
.fcol.triggers h3{color:#C2410C}.fcol.conditions h3{color:var(--beta)}.fcol.actions h3{color:var(--accent)}
.fcol h3 small{color:var(--muted);font-weight:500}
.fcol ol{margin:0;padding-left:18px;font-size:14.5px}.fcol li{margin:5px 0}
.minis{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:10px}
.mini{display:flex;gap:12px;align-items:center;text-decoration:none;background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:12px}
.mini:hover{border-color:var(--muted)}.mini b{display:block}.mini small{display:block;color:var(--muted);font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:180px}
.support{margin-top:40px;display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;background:var(--surface);border:1px solid var(--line);border-radius:20px;padding:22px 26px}
.support p{margin:0;color:var(--muted);max-width:60ch}
footer{padding-block:40px;color:var(--muted);font-size:14px}footer .bar{border-top:1px solid var(--line);padding-top:22px}footer nav{display:flex;gap:18px}
@media (max-width:760px){.head{grid-template-columns:minmax(0,1fr);gap:16px}.icon{width:96px;height:96px;border-radius:22px}
.flow{grid-template-columns:minmax(0,1fr)}.news li{grid-template-columns:minmax(0,1fr);gap:6px}.facts div{padding-right:16px;margin-right:16px}
.shots img{height:440px}.right nav{display:none}}
"""

JS = """
document.addEventListener("click",ev=>{const sa=ev.target.closest(".showall");if(sa){const box=sa.closest(".fcol")||sa.closest("section");
box.classList.toggle("open");sa.textContent=box.classList.contains("open")?sa.dataset.b:sa.dataset.a}});
"""


EN_HOME = [
    ('<span>© lrvdlinden.app, Léon van der Linden uit Apeldoorn. Powered by',
     '<span>© lrvdlinden.app, Léon van der Linden from Apeldoorn. Powered by'),
    ('<html lang="nl">', '<html lang="en">'),
    ('<title>Gratis iOS- en Homey-apps van Léon van der Linden | LRvdLinden Apps</title>',
     '<title>Free iOS and Homey apps by Léon van der Linden | LRvdLinden Apps</title>'),
    ('content="Gratis apps zonder advertenties van Léon van der Linden voor iPhone, iPad, Mac en Homey: Bingr, Tunr, HealthSync, DevTools, VlagDagen, P2000 en meer."',
     'content="Free, ad-free apps by Léon van der Linden for iPhone, iPad, Mac and Homey: Bingr, Tunr, HealthSync, DevTools, VlagDagen, P2000 and more."'),
    ('<link rel="canonical" href="https://lrvdlinden.app/">', '<link rel="canonical" href="https://lrvdlinden.app/en/">'),
    ('<meta property="og:url" content="https://lrvdlinden.app/">', '<meta property="og:url" content="https://lrvdlinden.app/en/">'),
    ('content="Apps voor je buurt, je huis en je dag | LRvdLinden Apps"', 'content="Apps for your neighbourhood, your home and your day | LRvdLinden Apps"'),
    ('content="Gratis iOS- en Homey-apps van Léon van der Linden, zonder advertenties. Voor iPhone, iPad, Mac en Homey."',
     'content="Free iOS and Homey apps by Léon van der Linden, without ads. For iPhone, iPad, Mac and Homey."'),
    ('content="Gratis iOS- en Homey-apps van Léon van der Linden, zonder advertenties."', 'content="Free iOS and Homey apps by Léon van der Linden, without ads."'),
    ('https://lrvdlinden.app/og-image.jpg', 'https://lrvdlinden.app/og-image-en.jpg'),
    ('content="lrvdlinden.app: apps voor je buurt, je huis en je dag, met iconen van de apps"',
     'content="lrvdlinden.app: apps for your neighbourhood, your home and your day, with the app icons"'),
    ('content="lrvdlinden.app: apps voor je buurt, je huis en je dag"', 'content="lrvdlinden.app: apps for your neighbourhood, your home and your day"'),
    ('<meta property="og:locale" content="nl_NL">\n<meta property="og:locale:alternate" content="en_GB">',
     '<meta property="og:locale" content="en_GB">\n<meta property="og:locale:alternate" content="nl_NL">'),
    ('<h1 data-t="h1" data-html>Apps voor je buurt, je huis en <em>je dag</em>.</h1>',
     '<h1 data-t="h1" data-html>Apps for your neighbourhood, your home and <em>your day</em>.</h1>'),
]


def build_en_home():
    """Engelse homepagina op /en/: zelfde pagina, met Engelse titel, omschrijving en OG-afbeelding."""
    src = os.path.join(OUT, "index.html")
    if not os.path.isfile(src):
        return
    h = open(src, encoding="utf-8").read()
    for a, b in EN_HOME:
        if a not in h:
            print(f"::warning::Engelse homepagina: tekst niet gevonden: {a[:60]}")
        h = h.replace(a, b)
    # alle relatieve paden (img/, apps.json) vanaf de root laden; ankers naar de Engelse pagina
    h = h.replace('<meta charset="utf-8">', '<meta charset="utf-8">\n<base href="/">', 1)
    h = re.sub(r'href="#([a-z]+)"', r'href="/en/#\1"', h)
    h = h.replace("<script>\nconst T = {", '<script>window.LR_LANG = "en";</script>\n<script>\nconst T = {', 1)
    if 'window.LR_LANG = "en"' not in h:
        print("::warning::Engelse homepagina: taalinstelling niet gezet.")
    os.makedirs(os.path.join(OUT, "en"), exist_ok=True)
    open(os.path.join(OUT, "en", "index.html"), "w", encoding="utf-8").write(h)


def main():
    content_root = os.path.join(OUT, "app-content")
    built = []
    paths = {id(a): page_path(a, apps) for a in apps}
    for a in apps:
        path = paths[id(a)]
        ckey = content_key(a, apps)
        try:
            c = json.load(open(os.path.join(content_root, ckey, "content.json"), encoding="utf-8"))
        except (OSError, ValueError):
            c = {}
        c["ckey"], c["path"] = ckey, path
        # Meer apps: eerst dezelfde soort (iOS of Homey), live en met icoon
        same = [o for o in apps if o is not a and o.get("section") == a.get("section") and o.get("icon")]
        others = [(o, paths[id(o)]) for o in sorted(same, key=lambda o: (o.get("status") != "live", 0))][:6]
        for lang in ("nl", "en"):
            if lang == "en" and a.get("nlOnly"):
                continue
            d = os.path.join(OUT, ("en/" if lang == "en" else "") + path.strip("/"))
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "index.html"), "w", encoding="utf-8") as f:
                f.write(page(a, c, others, lang))
        built.append(path)
    # overzicht voor de sitemap en de release-controle
    with open(os.path.join(OUT, "app-pages.json"), "w", encoding="utf-8") as f:
        json.dump([{"path": paths[id(a)], "ckey": content_key(a, apps), "lastmod": max([h.get("date") or "" for h in a.get("history") or []] + [""]) or None,
                    "nlOnly": bool(a.get("nlOnly"))} for a in apps], f)
    # oude adressen van Homey-apps (/app/<naam>/) doorsturen naar /homey/<naam>/
    ios_paths = {paths[id(a)].strip("/") for a in apps if a.get("section") != "homey"}
    rules = []
    for a in apps:
        if a.get("section") == "homey":
            old = legacy_homey_path(a, apps)
            if old not in ios_paths:
                rules.append(f"  RewriteRule ^{re.escape(old)}/?$ {paths[id(a)]} [R=301,L]")
    with open(os.path.join(OUT, "app-redirects.conf"), "w", encoding="utf-8") as f:
        f.write("<IfModule mod_rewrite.c>\n  RewriteEngine On\n" + "\n".join(rules) + "\n</IfModule>\n")
    build_en_home()
    print(f"App-pagina's: {len(built)} ({datetime.now(timezone.utc):%Y-%m-%d})")


if __name__ == "__main__":
    main()
