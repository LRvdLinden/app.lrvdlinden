"""
Dagelijkse store-check voor lrvdlinden.app.

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

APPS_JSON = sys.argv[1] if len(sys.argv) > 1 else "site/apps.json"
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
def translate_batch(items):
    """items: lijst van (bron_tekst, doeltaal). Geeft lijst met vertalingen of None per item."""
    key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not items or not key:
        return [None] * len(items)
    names = {"nl": "Dutch", "en": "English"}
    payload = [{"i": i, "target": names[t], "text": s} for i, (s, t) in enumerate(items)]
    prompt = (
        "Translate each app release note below into the target language. "
        "Keep the meaning, tone, line breaks, bullet characters, version numbers and product names exactly. "
        "Use natural, informal app-store wording (Dutch: use 'je'). "
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
def check_appstore(apps, log):
    # Alleen iOS-apps. Een App Store-link bij een Homey-app is de bijbehorende iPhone-app, geen eigen versie.
    ios = [a for a in apps if a.get("section", "ios") != "homey" and appstore_id(a)]
    if not ios:
        return
    ids = ",".join(sorted({appstore_id(a) for a in ios}))
    per_country = {}
    for cc in COUNTRIES:
        data = get_json(f"https://itunes.apple.com/lookup?id={ids}&country={cc}&entity=software")
        if not FIXTURES:
            time.sleep(PAUSE)
        for r in (data or {}).get("results", []):
            per_country.setdefault(str(r.get("trackId")), {})[cc] = r
    for app in ios:
        res = per_country.get(appstore_id(app))
        if not res:
            log.append(f"- {app['name']}: niet gevonden in de App Store")
            continue
        main = res.get("nl") or res.get("us") or next(iter(res.values()))
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
        nl_txt = clean((res.get("nl") or {}).get("releaseNotes"))
        en_txt = clean((res.get("us") or res.get("gb") or {}).get("releaseNotes"))
        notes = {}
        if nl_txt and en_txt and nl_txt != en_txt:
            notes = {"nl": nl_txt, "en": en_txt}
        elif nl_txt or en_txt:
            t = nl_txt or en_txt
            notes = {detect_lang(t): t}
        if version:
            upsert_history(app, version, date, notes, keep=20)

        if snap(app) != before:
            log.append(f"- {app['name']}: versie {version}, {app.get('rating', '–')} ★ ({app.get('reviews', 0)} beoordelingen)")


# ---------- Homey ----------
def check_homey(apps, log):
    for app in [a for a in apps if a.get("section") == "homey"]:
        hid = homey_id(app)
        if not hid:
            continue
        info = get_json(f"https://apps-api.athom.com/api/v1/app/{hid}")
        if not info:
            log.append(f"- {app['name']} (Homey): niet gevonden")
            continue
        before = snap(app)
        live, test = info.get("liveVersion"), info.get("testVersion")
        app["status"] = "live" if live else ("beta" if test else app.get("status", "dev"))
        if info.get("rating") is not None:
            app["rating"] = round(float(info["rating"]), 1)
        # Link naar de reguliere of de testpagina
        name_slug = re.sub(r"[^A-Za-z0-9]+", "-", app.get("name", "app")).strip("-") or "app"
        links = app.setdefault("links", {})
        links["homey"] = f"https://homey.app/nl-nl/app/{hid}/" + ("" if live else f"{name_slug}/test/")

        log_cl = get_json(f"https://apps-api.athom.com/api/v1/app/{hid}/changelog") or {}
        states = ("live", "superseded") if live else ("test", "live", "superseded")
        entries = [(v, e) for v, e in log_cl.items() if isinstance(e, dict) and e.get("state") in states]
        entries.sort(key=lambda x: ver_key(x[0]), reverse=True)
        keep_versions = {str(v) for v, _ in entries[:HOMEY_HISTORY]}
        if keep_versions:  # alleen Homey-versies tonen (oude of verkeerd gekoppelde regels weg)
            app["history"] = [h for h in app.get("history") or [] if str(h.get("version")) in keep_versions]
        app.pop("reviews", None)  # Homey kent geen aantal beoordelingen
        if info.get("rating") is None:
            app.pop("rating", None)
        for v, e in entries[:HOMEY_HISTORY]:
            cl = e.get("changelog") or {}
            notes = {k: clean(cl[k]) for k in ("nl", "en") if cl.get(k)}
            if not notes and cl:
                t = clean(next(iter(cl.values())))
                notes = {detect_lang(t): t}
            upsert_history(app, v, (e.get("createdAt") or "")[:10], notes, keep=HOMEY_HISTORY)
        if snap(app) != before:
            log.append(f"- {app['name']} (Homey): versie {live or test}" + (f", {app['rating']} ★" if app.get("rating") else ""))



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
    write_texts(jobs)


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

# ---------- ontbrekende talen vertalen ----------
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


def main():
    raw = open(APPS_JSON, encoding="utf-8").read()
    data = json.loads(raw)
    apps = data.get("apps", [])
    log = []
    if os.environ.get("STORE_DISCOVER", "1") == "1":
        discover_appstore(apps, log)
        discover_homey(apps, log)
    check_appstore(apps, log)
    check_homey(apps, log)
    fill_translations(apps, log)
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
    print(summary)


if __name__ == "__main__":
    main()
