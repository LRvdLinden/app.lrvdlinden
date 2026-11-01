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
    body = json.dumps({"model": MODEL, "max_tokens": 8000,
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
        arr = json.loads(text[text.find("["): text.rfind("]") + 1])
        out = [None] * len(items)
        for o in arr:
            if isinstance(o, dict) and isinstance(o.get("i"), int) and 0 <= o["i"] < len(items):
                out[o["i"]] = clean(o.get("text"))
        return out
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read().decode()).get("error", {}).get("message", "")
        except Exception:
            msg = ""
        print(f"::warning::Vertalen mislukt (HTTP {e.code}: {msg or e.reason}). Teksten blijven in de originele taal.")
        return [None] * len(items)
    except Exception as e:
        print(f"::warning::Vertalen mislukt ({e}). Teksten blijven in de originele taal.")
        return [None] * len(items)


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


def ver_key(v):
    return [int(x) if x.isdigit() else 0 for x in re.split(r"[.\-]", str(v or "0"))]


# ---------- App Store ----------
def check_appstore(apps, log):
    ios = [a for a in apps if appstore_id(a)]
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
        before = json.dumps(app, sort_keys=True, ensure_ascii=False)

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

        if json.dumps(app, sort_keys=True, ensure_ascii=False) != before:
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
        before = json.dumps(app, sort_keys=True, ensure_ascii=False)
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
        for v, e in entries[:HOMEY_HISTORY]:
            cl = e.get("changelog") or {}
            notes = {k: clean(cl[k]) for k in ("nl", "en") if cl.get(k)}
            if not notes and cl:
                t = clean(next(iter(cl.values())))
                notes = {detect_lang(t): t}
            upsert_history(app, v, (e.get("createdAt") or "")[:10], notes, keep=HOMEY_HISTORY)
        if json.dumps(app, sort_keys=True, ensure_ascii=False) != before:
            log.append(f"- {app['name']} (Homey): versie {live or test}" + (f", {app['rating']} ★" if app.get("rating") else ""))


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
