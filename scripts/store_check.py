"""
Automatische store-check (twee keer per dag) voor lrvdlinden.app.

App Store (iOS-apps met een App Store-link):
  versie, releasedatum, wat-is-nieuw, sterren en aantal beoordelingen (opgeteld over meerdere landen),
  grootte en talen.
Homey App Store (Homey-apps):
  live-/testversie (status Live of Test), volledige changelog en sterren.

Wat-is-nieuw-teksten worden in het Nederlands en Engels opgeslagen. Ontbreekt een taal, dan wordt hij
vertaald met de Claude API (secret ANTHROPIC_API_KEY). Zonder sleutel blijft alleen de originele taal staan.

Gebruik:  python3 scripts/store_check.py site/apps.json
Schrijft het bestand alleen als er iets veranderd is en zet een samenvatting in store-check-summary.md.
"""
import json, os, re, sys, time, urllib.request, urllib.error
from datetime import datetime

APPS_JSON = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "site/apps.json"
FIXTURES = os.environ.get("STORE_FIXTURES")  # alleen voor lokaal testen
# Beoordelingen telt Apple per land; dit zijn de grootste App Store-landen (plus NL/BE).
COUNTRIES = ["nl", "be", "us", "gb", "de", "fr", "es", "it", "ca", "au", "ie", "at", "ch", "lu", "dk", "se", "no", "fi",
             "pl", "pt", "cz", "gr", "tr", "nz", "za", "in", "jp", "kr", "cn", "tw", "hk", "sg", "my", "id", "ph", "th",
             "ae", "sa", "il", "br", "mx", "ar", "cl", "co"]
PAUSE = float(os.environ.get("STORE_PAUSE", "3"))  # Apple staat ongeveer 20 aanvragen per minuut toe
HOMEY_HISTORY = 10
MODEL = os.environ.get("TRANSLATE_MODEL", "claude-haiku-5-5")
UA = {"User-Agent": "lrvdlinden.app store-check (+https://lrvdlinden.app)"}


DEVELOPER_ID = os.environ.get("APPSTORE_DEVELOPER_ID", "607860328")
HOMEY_AUTHORS = os.environ.get("HOMEY_AUTHORS", "5d4da77a2c836a50f6936070,6ac4bc064c7de6266bbdb73e").split(",")
IMG_DIR = os.path.join(os.path.dirname(os.path.abspath(APPS_JSON)), "img")

CATEGORY_MAP = {
    "Utilities": "utilities", "Entertainment": "entertainment", "News": "news", "Business": "business",
    "Lifestyle": "lifestyle", "Games": "games", "Music": "music", "Productivity": "productivity",
    "Health & Fitness": "health", "Medical": "health", "Education": "education", "Travel": "travel",
    "Weather": "weather", "Sports": "sports", "Photo & Video": "photo", "Navigation": "navigation",
    "Finance": "finance", "Reference": "reference", "Social Networking": "social", "Food & Drink": "food",
    "Books": "books", "Developer Tools": "developer", "Graphics & Design": "design", "Shopping": "shopping",
    "Kids": "kids",
}


def get_raw(url):
    """Haalt een URL op als bytes (voor HTML en iconen)."""
    if FIXTURES:
        return None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
        except Exception:
            pass
        time.sleep(3 * (attempt + 1))
    return None


def get_json(url):
    if FIXTURES:
        key = re.sub(r"[^a-zA-Z0-9]+", "_", url)[-120:]
        path = os.path.join(FIXTURES, key + ".json")
        return json.load(open(path)) if os.path.exists(path) else None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            err = e
        except Exception as e:  # netwerkfout: opnieuw proberen
            err = e
        time.sleep(3 * (attempt + 1))
    print(f"::warning::Ophalen mislukt: {url} ({err})")
    return None


# ---------- taal ----------
NL_WORDS = set("de het een en van is je jouw voor met niet nu op naar bij wordt worden zijn verbeterd opgelost nieuwe nieuw kun kunt als ook dat deze meer".split())
EN_WORDS = set("the a and is you your for with now to of in fixed improved new can when also that this more app's".split())


def detect_lang(text):
    words = re.findall(r"[a-zA-Zàáéëèïíóöüú']+", (text or "").lower())
    nl = sum(w in NL_WORDS for w in words)
    en = sum(w in EN_WORDS for w in words)
    return "nl" if nl > en else "en"


def clean(text):
    text = (text or "").replace("\r\n", "\n").strip()
    return re.sub(r"\n{3,}", "\n\n", text)


# ---------- vertalen ----------
def translate_batch(items, kind="notes"):
    """items: lijst van (bron_tekst, doeltaal). Geeft lijst met vertalingen of None per item."""
    key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not items or not key:
        return [None] * len(items)
    names = {"nl": "Dutch", "en": "English"}
    payload = [{"i": i, "target": names[t], "text": s} for i, (s, t) in enumerate(items)]
    what = ("app release note" if kind == "notes" else
            "short Homey smart-home app text (device name, widget name or Flow card title as shown in the Homey app)")
    prompt = (
        f"Translate each {what} below into the target language. "
        "Keep the meaning, tone, line breaks, bullet characters, version numbers and product names exactly. "
        "Keep placeholders like !{{is|isn't}}, [[name]] and {{token}} intact; translate only the words inside !{{...|...}}. "
        "Use the wording the Homey app uses (Dutch: informal 'je'). "
        "Reply with only a JSON array of objects {\"i\": number, \"text\": string}, nothing else.\n\n"
        + json.dumps(payload, ensure_ascii=False)
    )
    arr = claude_json(prompt)
    if not isinstance(arr, list):
        return [None] * len(items)
    out = [None] * len(items)
    for o in arr:
        if isinstance(o, dict) and isinstance(o.get("i"), int) and 0 <= o["i"] < len(items):
            out[o["i"]] = clean(o.get("text"))
    return out


def claude_json(prompt, max_tokens=8000):
    """Stuurt een prompt naar de Claude API en geeft het JSON-antwoord terug (of None)."""
    key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not key:
        return None
    body = json.dumps({"model": MODEL, "max_tokens": max_tokens,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    headers = {"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"}
    ws = os.environ.get("ANTHROPIC_WORKSPACE_ID", "").strip()
    if ws:  # nodig bij een sleutel die niet aan een workspace gekoppeld is
        headers["anthropic-workspace-id"] = ws
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=body, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            res = json.loads(r.read().decode())
        text = "".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
        start = min([i for i in (text.find("["), text.find("{")) if i >= 0] or [0])
        end = max(text.rfind("]"), text.rfind("}")) + 1
        return json.loads(text[start:end])
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read().decode()).get("error", {}).get("message", "")
        except Exception:
            msg = ""
        print(f"::warning::Claude API mislukt (HTTP {e.code}: {msg or e.reason}). Teksten blijven in de originele taal.")
        return None
    except Exception as e:
        print(f"::warning::Claude API mislukt ({e}). Teksten blijven in de originele taal.")
        return None


# ---------- helpers ----------
def fmt_size(b):
    if not b:
        return None
    b = int(b)
    if b >= 1_000_000_000:
        return f"{b / 1_000_000_000:.1f} GB".replace(".", ",")
    if b >= 1_000_000:
        return f"{b / 1_000_000:.1f} MB".replace(".", ",")
    return f"{round(b / 1000)} kB"


def fmt_langs(codes):
    codes = [c.upper() for c in (codes or [])]
    if not codes:
        return None
    first = "NL" if "NL" in codes else ("EN" if "EN" in codes else codes[0])
    return first if len(codes) == 1 else f"{first} + {len(codes) - 1}"


def appstore_id(app):
    m = re.search(r"/id(\d+)", (app.get("links") or {}).get("appstore", "") or "")
    return m.group(1) if m else None


def homey_id(app):
    b = app.get("bundleId") or ""
    if re.match(r"^[a-zA-Z0-9_.-]+\.[a-zA-Z0-9_.-]+$", b) and " " not in b:
        return b
    m = re.search(r"/app/([^/]+)/", (app.get("links") or {}).get("homey", "") or "")
    return m.group(1) if m else None


def upsert_history(app, version, date, notes, keep=None):
    """notes: dict taal->tekst (kan leeg zijn). Geeft True als er iets veranderde."""
    hist = app.setdefault("history", [])
    entry = next((h for h in hist if str(h.get("version")) == str(version)), None)
    changed = False
    if entry is None:
        entry = {"version": version, "date": date or "", "notes": {}}
        hist.append(entry)
        changed = True
    if date and not entry.get("date"):
        entry["date"] = date
        changed = True
    entry.setdefault("notes", {})
    src = entry.setdefault("_src", {})
    for lang, text in notes.items():
        if text and src.get(lang) != text:
            # Nieuwe brontekst voor deze taal. Was er al een eerdere brontekst, dan is de vertaling
            # in de andere taal verouderd en wordt die opnieuw gemaakt. Handmatige teksten blijven staan.
            prev = src.get(lang)
            entry["notes"][lang] = text
            src[lang] = text
            other = "en" if lang == "nl" else "nl"
            if prev is not None and src.get(other) is None:
                entry["notes"].pop(other, None)
            changed = True
    hist.sort(key=lambda h: (h.get("date") or "", ver_key(h.get("version"))), reverse=True)
    if keep:
        del hist[keep:]
    return changed


def snap(app):
    """Momentopname van een app voor de vergelijking, zonder interne velden."""
    a = json.loads(json.dumps(app))
    for h in a.get("history") or []:
        h.pop("_src", None)
    return json.dumps(a, sort_keys=True, ensure_ascii=False)


def ver_key(v):
    return [int(x) if x.isdigit() else 0 for x in re.split(r"[.\-]", str(v or "0"))]


# ---------- App Store ----------
CHECKED = []  # wat de stores teruggaven, voor het overzicht in de run


def check_appstore(apps, log, only=None):
    # Alleen iOS-apps. Een App Store-link bij een Homey-app is de bijbehorende iPhone-app, geen eigen versie.
    ios = [a for a in apps if a.get("section", "ios") != "homey" and appstore_id(a)
           and (only is None or a["id"] in only)]
    if not ios:
        return
    ids = ",".join(sorted({appstore_id(a) for a in ios}))
    per_country = {}
    for cc in COUNTRIES:
        # cb= omzeilt de cache van Apple, die na een nieuwe release soms uren de oude versie blijft geven
        data = get_json(f"https://itunes.apple.com/lookup?id={ids}&country={cc}&entity=software&cb={int(time.time())}")
        if not FIXTURES:
            time.sleep(PAUSE)
        for r in (data or {}).get("results", []):
            per_country.setdefault(str(r.get("trackId")), {})[cc] = r
    for app in ios:
        res = per_country.get(appstore_id(app))
        if not res:
            log.append(f"- {app['name']}: niet gevonden in de App Store")
            continue
        newest = max((r.get("version") or "0" for r in res.values()), key=ver_key)
        # Nieuwste versie aanhouden, ook als nog niet elk land die doorgeeft
        fresh = {cc: r for cc, r in res.items() if (r.get("version") or "0") == newest}
        main = fresh.get("nl") or fresh.get("us") or res.get("nl") or res.get("us") or next(iter(res.values()))
        if main.get("version") != newest:
            main = next(iter(fresh.values()))
        chk = {"app": app["name"], "store": "App Store", "version": main.get("version") or "",
               "date": (main.get("currentVersionReleaseDate") or "")[:10], "changed": False}
        CHECKED.append(chk)
        before = snap(app)

        # Sterren en aantal beoordelingen, opgeteld over alle landen
        total = sum(int(r.get("userRatingCount") or 0) for r in res.values())
        if total:
            avg = sum(float(r.get("averageUserRating") or 0) * int(r.get("userRatingCount") or 0) for r in res.values()) / total
            app["rating"] = round(avg, 1)
            app["reviews"] = total
        elif len(res) >= len(COUNTRIES) // 2:  # alleen als de meeste landen zijn opgehaald
            app.pop("rating", None)
            app["reviews"] = 0
        size = fmt_size(main.get("fileSizeBytes"))
        if size:
            app["size"] = size
        langs = fmt_langs(main.get("languageCodesISO2A"))
        if langs:
            app["languages"] = langs

        # Wat is nieuw
        version = main.get("version")
        date = (main.get("currentVersionReleaseDate") or "")[:10]
        nl_txt = clean((fresh.get("nl") or {}).get("releaseNotes"))
        en_txt = clean((fresh.get("us") or fresh.get("gb") or {}).get("releaseNotes"))
        if not nl_txt and not en_txt:
            en_txt = clean(main.get("releaseNotes"))
        notes = {}
        if nl_txt and en_txt and nl_txt != en_txt:
            notes = {"nl": nl_txt, "en": en_txt}
        elif nl_txt or en_txt:
            t = nl_txt or en_txt
            notes = {detect_lang(t): t}
        if version:
            upsert_history(app, version, date, notes, keep=20)

        if snap(app) != before:
            chk["changed"] = True
            log.append(f"- {app['name']}: versie {version}, {app.get('rating', '–')} ★ ({app.get('reviews', 0)} beoordelingen)")


# ---------- Homey ----------
def loc(d):
    """Meertalig Homey-veld terugbrengen tot {nl, en}. Ontbreken beide, dan de eerste taal als en."""
    if isinstance(d, str):
        return {"en": d}
    if not isinstance(d, dict):
        return {}
    out = {k: clean(d[k]) for k in ("nl", "en") if isinstance(d.get(k), str) and d[k].strip()}
    if not out:
        first = next((v for v in d.values() if isinstance(v, str) and v.strip()), None)
        if first:
            out["en"] = clean(first)
    return out


def known_translations(old):
    """Bestaande vertalingen uit de vorige versie, zodat ze niet elke dag opnieuw gemaakt worden."""
    table = {}
    def walk(o):
        if isinstance(o, dict):
            if set(o) <= {"nl", "en"} and o.get("nl") and o.get("en"):
                table[("en", o["en"])] = o["nl"]
                table[("nl", o["nl"])] = o["en"]
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(old or {})
    return table


def homey_category(c):
    """Eerste categorie uit de Homey App Store (bijv. security, climate, tools)."""
    if isinstance(c, list):
        c = next((x for x in c if isinstance(x, str) and x), None)
    return c if isinstance(c, str) and c else None


def homey_details(build, old):
    """Apparaten, widgets en Flow-kaarten zoals de Homey App Store ze toont."""
    table = known_translations(old)
    def L(d):
        t = loc(d)
        for have, need in (("en", "nl"), ("nl", "en")):
            if t.get(have) and not t.get(need) and (have, t[have]) in table:
                t[need] = table[(have, t[have])]
        return t
    drivers = []
    for d in build.get("drivers") or []:
        if not isinstance(d, dict) or d.get("deprecated"):
            continue
        drivers.append({k: v for k, v in {
            "id": d.get("id"), "name": L(d.get("name")), "class": d.get("class"),
            "image": d.get("imageSmall") or d.get("imageLarge"), "icon": d.get("icon"),
        }.items() if v})
    widgets = []
    w = build.get("widgets") or {}
    for wid, wd in (w.items() if isinstance(w, dict) else enumerate(w)):
        if not isinstance(wd, dict) or wd.get("deprecated"):
            continue
        widgets.append({k: v for k, v in {
            "id": wd.get("id") or str(wid), "name": L(wd.get("name")),
            "light": wd.get("previewLight"), "dark": wd.get("previewDark"),
        }.items() if v})
    flow = {}
    for kind in ("triggers", "conditions", "actions"):
        cards = []
        for c in (build.get("flow") or {}).get(kind) or []:
            if not isinstance(c, dict) or c.get("deprecated") or not c.get("title"):
                continue
            cards.append({"id": c.get("id"), "title": L(c.get("title"))})
        if cards:
            flow[kind] = cards
    out = {"drivers": drivers, "widgets": widgets, "flow": flow,
           "platforms": build.get("platforms") or [], "compatibility": build.get("compatibility"),
           "color": build.get("brandColor"), "homepage": build.get("homepage"), "support": build.get("support"),
           "category": homey_category(build.get("category"))}
    return {k: v for k, v in out.items() if v}


def check_homey(apps, log, only=None):
    for app in [a for a in apps if a.get("section") == "homey" and (only is None or a["id"] in only)]:
        hid = homey_id(app)
        if not hid:
            continue
        info = get_json(f"https://apps-api.athom.com/api/v1/app/{hid}")
        if not info:
            log.append(f"- {app['name']} (Homey): niet gevonden")
            continue
        before = snap(app)
        live, test = info.get("liveVersion"), info.get("testVersion")
        chk = {"app": app["name"], "store": "Homey", "version": live or test or "",
               "test": test if live and test and test != live else "", "changed": False}
        CHECKED.append(chk)
        app["status"] = "live" if live else ("beta" if test else app.get("status", "dev"))
        if info.get("rating") is not None:
            app["rating"] = round(float(info["rating"]), 1)
        # Link naar de reguliere of de testpagina
        name_slug = re.sub(r"[^A-Za-z0-9]+", "-", app.get("name", "app")).strip("-") or "app"
        links = app.setdefault("links", {})
        links["homey"] = f"https://homey.app/nl-nl/app/{hid}/" + ("" if live else f"{name_slug}/test/")

        log_cl = get_json(f"https://apps-api.athom.com/api/v1/app/{hid}/changelog") or {}
        states = ("test", "live", "superseded")  # testversies ook tonen, ook bij een app die al live is
        entries = [(v, e) for v, e in log_cl.items() if isinstance(e, dict) and e.get("state") in states
                   # oude testversies die nooit live gingen weglaten; alleen een test nieuwer dan live tonen
                   and not (live and e.get("state") == "test" and ver_key(v) <= ver_key(live))]
        entries.sort(key=lambda x: ver_key(x[0]), reverse=True)
        keep_versions = {str(v) for v, _ in entries[:HOMEY_HISTORY]}
        if keep_versions:  # alleen Homey-versies tonen (oude of verkeerd gekoppelde regels weg)
            app["history"] = [h for h in app.get("history") or [] if str(h.get("version")) in keep_versions]
        app.pop("reviews", None)  # Homey kent geen aantal beoordelingen
        if info.get("rating") is None:
            app.pop("rating", None)
        build = info.get("liveBuild") if live else (info.get("testBuild") or info.get("liveBuild"))
        if isinstance(build, dict):
            app["homey"] = homey_details(build, app.get("homey"))
        # Live- en testversie apart bewaren; een test die gelijk is aan live telt niet
        hx = app.setdefault("homey", {})
        hx.pop("live", None); hx.pop("test", None)
        if live:
            hx["live"] = str(live)
        if test and test != live and (not live or ver_key(test) > ver_key(live)):
            hx["test"] = str(test)
            links["homeyTest"] = f"https://homey.app/nl-nl/app/{hid}/{name_slug}/test/"
        else:
            links.pop("homeyTest", None)
        for v, e in entries[:HOMEY_HISTORY]:
            cl = e.get("changelog") or {}
            notes = {k: clean(cl[k]) for k in ("nl", "en") if cl.get(k)}
            if not notes and cl:
                t = clean(next(iter(cl.values())))
                notes = {detect_lang(t): t}
            upsert_history(app, v, (e.get("createdAt") or "")[:10], notes, keep=HOMEY_HISTORY)
            entry = next((h for h in app["history"] if str(h.get("version")) == str(v)), None)
            if entry is not None:
                if e.get("state") == "test" and live:
                    entry["test"] = True
                else:
                    entry.pop("test", None)
        if snap(app) != before:
            chk["changed"] = True
            log.append(f"- {app['name']} (Homey): versie {live or test}" + (f", test {test}" if live and test and test != live else "") + (f", {app['rating']} ★" if app.get("rating") else ""))



# ---------- nieuwe apps zoeken en beta-apps aanvullen ----------
def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-") or "app"


def norm(text):
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def unique_id(apps, base):
    ids = {a["id"] for a in apps}
    i, cand = 2, base
    while cand in ids:
        cand, i = f"{base}-{i}", i + 1
    return cand


def ios_platforms(res):
    devs = " ".join(res.get("supportedDevices") or [])
    out = []
    for key, label in (("iPhone", "iPhone"), ("iPad", "iPad"), ("MacDesktop", "Mac"), ("AppleTV", "Apple TV"),
                       ("Watch", "Apple Watch"), ("Reality", "Vision Pro")):
        if key in devs:
            out.append(label)
    if res.get("kind") == "mac-software" and "Mac" not in out:
        out.append("Mac")
    return out or ["iPhone"]


def save_icon(app_id, url, kind="png"):
    """Slaat een icoon op in site/img en geeft het pad voor apps.json terug."""
    data = get_raw(url)
    if not data:
        return None
    os.makedirs(IMG_DIR, exist_ok=True)
    name = f"{app_id}.{kind}"
    open(os.path.join(IMG_DIR, name), "wb").write(data)
    return f"img/{name}"


def save_homey_icon(app_id, svg_url, color):
    """Homey-iconen zijn een eenkleurig SVG-masker op de merkkleur. Bouw daar een vierkant icoon van."""
    import base64
    raw = get_raw(svg_url) if svg_url else None
    if not raw:
        return None
    color = color if re.match(r"^#[0-9a-fA-F]{3,8}$", color or "") else "#2747E8"
    b64 = base64.b64encode(raw).decode()
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 256 256">'
        '<defs><mask id="m" style="mask-type:alpha" maskUnits="userSpaceOnUse" x="0" y="0" width="256" height="256">'
        f'<image href="data:image/svg+xml;base64,{b64}" xlink:href="data:image/svg+xml;base64,{b64}" '
        'x="52" y="52" width="152" height="152"/></mask></defs>'
        f'<rect width="256" height="256" fill="{color}"/>'
        '<rect width="256" height="256" fill="#fff" mask="url(#m)"/></svg>'
    )
    os.makedirs(IMG_DIR, exist_ok=True)
    open(os.path.join(IMG_DIR, f"{app_id}.svg"), "w").write(svg)
    return f"img/{app_id}.svg"


def write_texts(jobs):
    """jobs: lijst van dicts {app, name, nl, en, need:[velden]}. Vult omschrijving en ondertitel in NL en EN."""
    if not jobs:
        return 0
    payload = [{"i": i, "app": j["name"], "store_text_dutch": (j.get("nl") or "")[:3000],
                "store_text_english": (j.get("en") or "")[:3000], "fields": j["need"]} for i, j in enumerate(jobs)]
    prompt = (
        "You write short texts for an app portfolio website, based on App Store or Homey App Store descriptions. "
        "For each item, write only the requested fields:\n"
        "- description_nl / description_en: 1 or 2 sentences, at most 230 characters, plain and concrete, "
        "what the app does for the user. Dutch uses informal 'je'. No marketing superlatives, no emoji.\n"
        "- subtitle_nl / subtitle_en: 1 to 3 words describing the kind of app (e.g. 'IPTV-speler' / 'IPTV player').\n"
        "If a store text is missing in one language, use the other one as the source.\n"
        "Reply with only a JSON array of objects {\"i\": number, ...fields}, nothing else.\n\n"
        + json.dumps(payload, ensure_ascii=False)
    )
    arr = claude_json(prompt)
    filled = 0
    if isinstance(arr, list):
        for o in arr:
            if not (isinstance(o, dict) and isinstance(o.get("i"), int) and 0 <= o["i"] < len(jobs)):
                continue
            app = jobs[o["i"]]["app"]
            for field in jobs[o["i"]]["need"]:
                val = clean(o.get(field) or "")
                if not val:
                    continue
                key, lang = field.rsplit("_", 1)
                app.setdefault(key, {})[lang] = val
                filled += 1
    # Zonder Claude: eerste zinnen van de storetekst gebruiken
    for j in jobs:
        app = j["app"]
        if not any((app.get("description") or {}).values()):
            src = j.get("nl") or j.get("en") or ""
            first = " ".join(re.split(r"(?<=[.!?])\s+", src.replace("\n", " ").strip())[:2])[:260]
            if first:
                app["description"] = {detect_lang(first): first}
    return filled


def discover_appstore(apps, log):
    found = {}
    for cc in ("nl", "us", "nz", "gb"):
        for entity in ("software", "macSoftware"):
            data = get_json(f"https://itunes.apple.com/lookup?id={DEVELOPER_ID}&entity={entity}&country={cc}&limit=200")
            for r in (data or {}).get("results", []):
                if r.get("wrapperType") != "software":
                    continue
                found.setdefault(str(r["trackId"]), {})[cc] = r
            if not FIXTURES:
                time.sleep(PAUSE)
    known = {appstore_id(a) for a in apps if appstore_id(a)}
    names = sorted({(next(iter(r.values())).get("trackName") or "?") for r in found.values()})
    print(f"::notice::App Store: {len(found)} apps bij ontwikkelaar {DEVELOPER_ID}, "
          f"{len([t for t in found if t not in known])} nog niet op de site. ({', '.join(names)})")
    return add_appstore(found, apps, log)


def add_appstore(found, apps, log, extra_links=None):
    """found: {trackId: {land: lookup-resultaat}}. Voegt nieuwe apps toe of vult beta-apps aan."""
    touched_ids = set()
    known = {appstore_id(a) for a in apps if appstore_id(a)}
    jobs = []
    for tid, res in found.items():
        if tid in known:
            continue
        en = res.get("us") or res.get("gb") or res.get("nz") or next(iter(res.values()))
        nl = res.get("nl") or {}
        name = re.split(r"\s+[-–:|]\s+", en.get("trackName", ""))[0].strip() or en.get("trackName", "")
        # Bestaande app zonder App Store-link met dezelfde naam (bijv. nog in beta)? Dan aanvullen.
        app = next((a for a in apps if a.get("section", "ios") == "ios" and not appstore_id(a)
                    and norm(a.get("name")) == norm(name)), None)
        new = app is None
        if new:
            app = {"id": unique_id(apps, slug(name)), "name": name, "section": "ios", "status": "live",
                   "description": {}, "links": {}, "history": []}
            last_ios = max([i for i, a in enumerate(apps) if a.get("section", "ios") == "ios"] or [len(apps) - 1])
            apps.insert(last_ios + 1, app)
        app.setdefault("links", {})["appstore"] = (en.get("trackViewUrl") or "").split("?")[0]
        for k, v in (extra_links or {}).items():
            app["links"].setdefault(k, v)
        if app.get("status") in ("beta", "dev"):
            app["status"] = "live"
        if not app.get("category"):
            app["category"] = CATEGORY_MAP.get(en.get("primaryGenreName"), "utilities")
        if not app.get("platforms"):
            app["platforms"] = ios_platforms(en)
        if not app.get("icon"):
            art = (en.get("artworkUrl512") or en.get("artworkUrl100") or "")
            art = re.sub(r"/\d+x\d+bb\.(png|jpg)$", "/256x256bb.png", art)
            icon = save_icon(app["id"], art) if art else None
            if icon:
                app["icon"] = icon
        need = [f"{k}_{l}" for k in ("description", "subtitle") for l in ("nl", "en")
                if not (app.get(k) or {}).get(l)]
        if need:
            jobs.append({"app": app, "name": name, "nl": nl.get("description"), "en": en.get("description"), "need": need})
        log.append(f"- {'Nieuwe app' if new else 'Aangevuld'}: {name} (App Store)")
        touched_ids.add(app["id"])
    write_texts(jobs)
    return touched_ids


def discover_homey(apps, log):
    listed = []
    for author in [a.strip() for a in HOMEY_AUTHORS if a.strip()]:
        for page in range(0, 10):
            html = (get_raw(f"https://homey.app/nl-nl/apps/author/{author}/page/{page}/") or b"").decode("utf-8", "replace")
            ids = re.findall(r'href="https://homey\.app/[a-z-]+/app/([^/"]+)/', html)
            fresh = [i for i in dict.fromkeys(ids) if i not in listed]
            if not fresh:
                break
            listed += fresh
    known = {homey_id(a) for a in apps if a.get("section") == "homey"}
    print(f"::notice::Homey: {len(listed)} apps op de auteurspagina's, "
          f"{len([h for h in listed if h not in known])} nog niet op de site. ({', '.join(listed)})")
    return add_homey(listed, apps, log)


def add_homey(listed, apps, log, extra_links=None):
    """listed: Homey-app-id's (bijv. nl.lrvdlinden.p2000). Voegt nieuwe apps toe of vult ze aan."""
    known = {homey_id(a) for a in apps if a.get("section") == "homey"}
    jobs = []
    touched = []
    for hid in listed:
        app = next((a for a in apps if a.get("section") == "homey" and homey_id(a) == hid), None)
        if app is not None and app.get("status") == "live" and app.get("icon") and any((app.get("description") or {}).values()):
            continue  # bekend en compleet
        info = get_json(f"https://apps-api.athom.com/api/v1/app/{hid}")
        build = (info or {}).get("liveBuild") or (info or {}).get("testBuild") or {}
        if not build:
            continue
        names = build.get("name") or {}
        name = names.get("nl") or names.get("en") or next(iter(names.values()), hid)
        new = hid not in known
        if new:
            app = {"id": unique_id(apps, "homey-" + slug(hid.split(".")[-1])), "name": name, "section": "homey",
                   "status": "live", "bundleId": hid, "description": {}, "links": {}, "history": []}
            apps.append(app)
        touched.append((app, new, None if new else snap(app)))
        for k, v in (extra_links or {}).items():
            app.setdefault("links", {}).setdefault(k, v)
        desc = build.get("description") or {}
        for lang in ("nl", "en"):
            if desc.get(lang) and not (app.get("description") or {}).get(lang):
                app.setdefault("description", {})[lang] = clean(desc[lang])
        if not app.get("icon"):
            icon = build.get("icon")
            if isinstance(icon, dict):
                icon = icon.get("url") or icon.get("svg")
            path = save_homey_icon(app["id"], icon, build.get("brandColor")) if isinstance(icon, str) else None
            if path:
                app["icon"] = path
        missing = [f"description_{l}" for l in ("nl", "en") if not (app.get("description") or {}).get(l)]
        if missing:
            readme = build.get("readme") or {}
            jobs.append({"app": app, "name": name,
                         "nl": desc.get("nl") or readme.get("nl"), "en": desc.get("en") or readme.get("en"),
                         "need": missing})
    write_texts(jobs)
    for app, new, before in touched:
        if new or snap(app) != before:
            log.append(f"- {'Nieuwe app' if new else 'Aangevuld'}: {app['name']} (Homey)")
    return {app["id"] for app, _, _ in touched}

# ---------- app toevoegen via een link (knop "Nieuwe app" in beheer) ----------
def lookup_appstore(tid):
    res = {}
    for cc in ("nl", "us", "gb"):
        for entity in ("", "&entity=macSoftware"):
            data = get_json(f"https://itunes.apple.com/lookup?id={tid}&country={cc}{entity}")
            hit = next((r for r in (data or {}).get("results", []) if r.get("wrapperType") == "software"), None)
            if hit:
                res[cc] = hit
                break
    return {str(tid): res} if res else {}


def html_meta(html):
    """Titel, omschrijving en icoon uit de HTML van een website."""
    def meta(*names):
        for n in names:
            m = re.search(r'<meta[^>]+(?:property|name)=["\']' + re.escape(n) + r'["\'][^>]*content=["\']([^"\']+)', html, re.I) or \
                re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]*(?:property|name)=["\']' + re.escape(n) + r'["\']', html, re.I)
            if m:
                return clean(re.sub(r"&amp;", "&", m.group(1)))
        return ""
    title = meta("og:site_name", "application-name", "apple-mobile-web-app-title")
    if not title:
        m = re.search(r"<title[^>]*>(.*?)</title>", html, re.I | re.S)
        title = clean(m.group(1)) if m else ""
    title = re.split(r"\s+[-–:|·]\s+", title)[0].strip()
    desc = meta("og:description", "description", "twitter:description")
    icons = []
    for m in re.finditer(r"<link[^>]+>", html, re.I):
        tag = m.group(0)
        rel = (re.search(r'rel=["\']([^"\']+)', tag, re.I) or [None, ""])[1].lower()
        href = (re.search(r'href=["\']([^"\']+)', tag, re.I) or [None, ""])[1]
        if href and "apple-touch-icon" in rel:
            icons.insert(0, href)
        elif href and "icon" in rel and not href.endswith(".ico"):
            icons.append(href)
    og_img = meta("og:image")
    return title, desc, icons, og_img


def save_icon_any(app_id, url):
    """Icoon van een website opslaan als vierkant 256x256 webp (of het origineel als Pillow ontbreekt)."""
    data = get_raw(url) if url else None
    if not data:
        return None
    os.makedirs(IMG_DIR, exist_ok=True)
    try:
        from PIL import Image
        import io
        im = Image.open(io.BytesIO(data)).convert("RGBA")
        side = min(im.size)
        im = im.crop(((im.width - side) // 2, (im.height - side) // 2, (im.width - side) // 2 + side, (im.height - side) // 2 + side))
        im = im.resize((256, 256), Image.LANCZOS)
        im.save(os.path.join(IMG_DIR, f"{app_id}.webp"), "WEBP", quality=88)
        return f"img/{app_id}.webp"
    except Exception:
        if data[:4] == b"\x89PNG":
            open(os.path.join(IMG_DIR, f"{app_id}.png"), "wb").write(data)
            return f"img/{app_id}.png"
    return None


def add_from_url(apps, log, url):
    """Voegt één app toe vanaf een App Store-, Homey-, TestFlight- of website-link. Geeft de id's terug."""
    from urllib.parse import urljoin, urlparse
    url = (url or "").strip()
    print(f"Toevoegen vanaf: {url}")
    m = re.search(r"apps\.apple\.com/.*?/id(\d+)", url) or re.fullmatch(r"(?:id)?(\d{6,12})", url)
    if m:
        if m.group(1) in {appstore_id(a) for a in apps}:
            log.append(f"- Staat al op de site: App Store-app {m.group(1)}")
            return {a["id"] for a in apps if appstore_id(a) == m.group(1)}
        found = lookup_appstore(m.group(1))
        if not found:
            log.append(f"- Niet gevonden in de App Store: {url}")
            return set()
        return add_appstore(found, apps, log)
    m = re.search(r"homey\.app/[a-z-]+/app/([^/?#]+)", url) or re.fullmatch(r"([a-z0-9]+(?:\.[a-z0-9_-]+){2,})", url)
    if m:
        return add_homey([m.group(1)], apps, log)
    if not re.match(r"^https?://", url):
        url = "https://" + url
    html = (get_raw(url) or b"").decode("utf-8", "replace")
    tf = "testflight.apple.com/join/" in url
    # Website met een link naar de App Store of de Homey App Store: die app toevoegen, met de website erbij
    if not tf:
        m = re.search(r"https://apps\.apple\.com/[^\"'\s<>]*?/id(\d+)", html)
        if m:
            found = lookup_appstore(m.group(1))
            if found:
                return add_appstore(found, apps, log, extra_links={"website": url})
        m = re.search(r"https://homey\.app/[a-z-]+/app/([^/\"'\s<>]+)", html)
        if m:
            return add_homey([m.group(1)], apps, log, extra_links={"website": url})
    title, desc, icons, og_img = html_meta(html)
    if tf:  # TestFlight-pagina: "Join the X beta - TestFlight - Apple"
        tt = re.search(r"Join the (.+?) beta", html) or re.search(r"Doe mee aan de bèta van (.+?)[ -]", html)
        title = (tt.group(1) if tt else title).strip()
    if not title:
        title = urlparse(url).netloc.replace("www.", "").split(".")[0].capitalize()
    existing = next((a for a in apps if norm(a.get("name")) == norm(title)), None)
    if existing:
        existing.setdefault("links", {}).setdefault("testflight" if tf else "website", url)
        log.append(f"- Aangevuld: {existing['name']} ({'TestFlight' if tf else 'website'})")
        return {existing["id"]}
    app = {"id": unique_id(apps, slug(title)), "name": title, "section": "ios", "status": "beta" if tf else "dev",
           "featured": True, "category": "utilities", "description": {}, "links": {("testflight" if tf else "website"): url}, "history": []}
    last_ios = max([i for i, a in enumerate(apps) if a.get("section", "ios") == "ios"] or [len(apps) - 1])
    apps.insert(last_ios + 1, app)
    for src in icons + ([og_img] if og_img else []):
        icon = save_icon_any(app["id"], urljoin(url, src))
        if icon:
            app["icon"] = icon
            break
    write_texts([{"app": app, "name": title, "nl": desc if detect_lang(desc) == "nl" else "", "en": desc if detect_lang(desc) != "nl" else "",
                  "need": ["description_nl", "description_en", "subtitle_nl", "subtitle_en"]}] if desc else [])
    log.append(f"- Nieuwe app: {title} ({'TestFlight' if tf else 'website'}, {'beta' if tf else 'in ontwikkeling'})")
    return {app["id"]}


# ---------- ontbrekende talen vertalen ----------
def fill_homey_translations(apps, log):
    """Ontbrekende NL/EN-teksten in apparaten, widgets en Flow-kaarten vertalen."""
    todo = []
    def walk(o):
        if isinstance(o, dict):
            if set(o) <= {"nl", "en"} and o and len([k for k in ("nl", "en") if o.get(k)]) == 1:
                have = "nl" if o.get("nl") else "en"
                todo.append((o, have, "en" if have == "nl" else "nl"))
                return
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    for app in apps:
        if app.get("section") == "homey":
            walk(app.get("homey"))
    if not todo:
        return
    results = []
    for i in range(0, len(todo), 60):
        chunk = todo[i:i + 60]
        results += translate_batch([(o[have], need) for o, have, need in chunk], kind="short")
    done = 0
    for (o, have, need), text in zip(todo, results):
        if text:
            o[need] = text
            done += 1
    if done:
        log.append(f"- {done} Homey-tekst(en) (apparaten, widgets, Flow-kaarten) vertaald")


def fill_translations(apps, log):
    todo = []
    for app in apps:
        for h in app.get("history") or []:
            notes = h.get("notes") or {}
            for have, need in (("en", "nl"), ("nl", "en")):
                if notes.get(have) and not notes.get(need):
                    todo.append((h, have, need))
                    break
    if not todo:
        return
    results = []
    for i in range(0, len(todo), 25):
        chunk = todo[i:i + 25]
        results += translate_batch([(h["notes"][have], need) for h, have, need in chunk])
    done = 0
    for (h, have, need), text in zip(todo, results):
        if text:
            h["notes"][need] = text
            done += 1
    if done:
        log.append(f"- {done} wat-is-nieuw-tekst(en) vertaald")
    elif not os.environ.get("ANTHROPIC_API_KEY"):
        print(f"::notice::{len(todo)} tekst(en) niet vertaald: secret ANTHROPIC_API_KEY ontbreekt.")


LOGBOOK = os.environ.get("STORE_LOGBOOK", "logs/store-check.json")


def write_logbook(mode, changed, log):
    """Elke run vastleggen voor het logboek in beheer.html (laatste 150 runs)."""
    try:
        book = json.load(open(LOGBOOK, encoding="utf-8"))
    except (OSError, ValueError):
        book = {"runs": []}
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    url = (f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{run_id}"
           if run_id and os.environ.get("GITHUB_REPOSITORY") else "")
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    entry = {
        "id": run_id,
        "time": datetime.now().astimezone().isoformat(timespec="seconds"),
        "mode": mode,
        "trigger": "schedule" if event == "schedule" else ("manual" if event == "workflow_dispatch" else event or "local"),
        "changed": bool(changed),
        "lines": [l[2:] if l.startswith("- ") else l for l in log],
        "checked": CHECKED,
        "url": url,
    }
    # los bewaren, zodat de workflow het bij een gelijktijdige wijziging opnieuw kan toevoegen
    with open("store-check-entry.json", "w", encoding="utf-8") as f:
        json.dump(entry, f, ensure_ascii=False)
    add_to_logbook(entry, book)


def add_to_logbook(entry, book=None):
    if book is None:
        try:
            book = json.load(open(LOGBOOK, encoding="utf-8"))
        except (OSError, ValueError):
            book = {"runs": []}
    rid = entry.get("id")
    book["runs"] = [entry] + [r for r in book.get("runs", []) if not rid or r.get("id") != rid]
    book["runs"] = sorted(book["runs"], key=lambda r: r.get("time") or "", reverse=True)[:150]
    os.makedirs(os.path.dirname(LOGBOOK) or ".", exist_ok=True)
    with open(LOGBOOK, "w", encoding="utf-8") as f:
        json.dump(book, f, ensure_ascii=False, indent=1)
        f.write("\n")


def main():
    raw = open(APPS_JSON, encoding="utf-8").read()
    data = json.loads(raw)
    apps = data.get("apps", [])
    log = []
    # STORE_MODE: alles (standaard), nieuw (alleen nieuwe en beta-apps), bijwerken (alleen bestaande apps)
    mode = os.environ.get("STORE_MODE", "alles").strip().lower() or "alles"
    if os.environ.get("STORE_DISCOVER", "1") != "1":
        mode = "bijwerken"
    print(f"Modus: {mode}")
    only = None
    if mode == "toevoegen":
        only = add_from_url(apps, log, os.environ.get("STORE_ADD", ""))
    elif mode in ("alles", "nieuw"):
        touched = discover_appstore(apps, log) | discover_homey(apps, log)
        if mode == "nieuw":
            only = touched  # nieuw gevonden of aangevulde apps meteen volledig ophalen
    if only is None or only:
        check_appstore(apps, log, only)
        check_homey(apps, log, only)
    fill_translations(apps, log)
    fill_homey_translations(apps, log)
    for app in apps:
        if "history" in app:
            # lege versieregels (zonder versie en zonder tekst) opruimen
            app["history"] = [h for h in app["history"]
                              if str(h.get("version") or "").strip() or any((h.get("notes") or {}).values())]
        for h in app.get("history") or []:
            if not h.get("_src"):  # intern veld alleen bewaren als het iets bevat
                h.pop("_src", None)
    indent = 4 if '\n    "apps"' in raw else 2
    new = json.dumps(data, ensure_ascii=False, indent=indent) + "\n"
    stamp = datetime.now().strftime("%d-%m-%Y %H:%M")
    if new != raw:
        open(APPS_JSON, "w", encoding="utf-8").write(new)
        summary = f"Store-check {stamp}\n\n" + ("\n".join(log) if log else "- kleine wijzigingen")
    else:
        summary = f"Store-check {stamp}: geen wijzigingen"
    open("store-check-summary.md", "w", encoding="utf-8").write(summary + "\n")
    if CHECKED:  # alleen in de Actions-samenvatting, niet in de commit
        rows = [f"| {c['app']} | {c['store']} | {c['version'] or '–'}" + (f" (test {c['test']})" if c.get("test") else "")
                + f" | {c.get('date', '')} | {'ja' if c['changed'] else ''} |" for c in CHECKED]
        open("store-check-overview.md", "w", encoding="utf-8").write(
            "\n\n### Gecontroleerd\n\n| App | Store | Versie in de store | Datum | Bijgewerkt |\n|---|---|---|---|---|\n"
            + "\n".join(rows) + "\n")
    write_logbook(mode, new != raw, log)
    print(summary)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--add-log":
        # gebruik: store_check.py --add-log store-check-entry.json
        add_to_logbook(json.load(open(sys.argv[2], encoding="utf-8")))
    else:
        main()
