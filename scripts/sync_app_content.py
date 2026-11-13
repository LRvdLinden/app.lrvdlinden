"""Haalt per app de nieuwste content uit LRvdLinden/app.lrvdlinden.app-content voor de app-pagina's.

Per app (map in de content-repo met dezelfde naam als de app):
- screenshots (iPhone, NL en EN) uit de nieuwste map onder <App>/AppStore/<datum>/
- de App Store-teksten (description.txt, promotional_text.txt) per taal
- een deelafbeelding (OG) uit <App>/OG/<datum>/, anders wordt er een gemaakt met icoon, naam en ondertitel

Alles komt in site/app-content/<slug>/ met een content.json. Alleen gewijzigde bestanden worden opnieuw opgehaald
(op basis van de git-blob-sha), dus een run zonder wijzigingen doet niets.

Gebruik: python3 scripts/sync_app_content.py [site/apps.json]
  CONTENT_DIR=/pad/naar/lokale/clone  gebruikt een lokale clone in plaats van GitHub (om te testen)
"""
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from appslug import norm, page_slug  # noqa: E402

from PIL import Image, ImageDraw, ImageFilter, ImageFont  # noqa: E402

REPO = "LRvdLinden/app.lrvdlinden.app-content"
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
APPS_JSON = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "site", "apps.json")
SITE = os.path.dirname(os.path.abspath(APPS_JSON))
OUT = os.path.join(SITE, "app-content")
FONTS = os.path.join(ROOT, "tools", "fonts")
CONTENT_DIR = os.environ.get("CONTENT_DIR")
MAX_SHOTS = 8
SHOT_W = 540

IMG = (".png", ".jpg", ".jpeg", ".webp")
SKIP_DIRS = ("marketing", "promo", "header", "artwork", "banner", "productpage", "brand", "layers", "event", "icoon", "icon")
OTHER_LANGS = {"fr", "de", "es", "it", "pt", "sv", "da", "no", "nb", "pl", "ja", "zh", "ko", "tr", "fi", "ru"}
SIZE_PREF = ["6.3", "6.1", "6.9", "6.7", "6.5", "5.5"]


# ---------- bron: GitHub of lokale clone ----------
def gh_get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "lrvdlinden-content-sync", "Accept": "application/vnd.github+json"})
    tok = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if tok and "api.github.com" in url:
        req.add_header("Authorization", "Bearer " + tok)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def load_tree():
    """Lijst van (pad, blob-sha) en de commit waarvan we lezen."""
    if CONTENT_DIR:
        commit = subprocess.run(["git", "-C", CONTENT_DIR, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        out = subprocess.run(["git", "-C", CONTENT_DIR, "ls-tree", "-r", "-z", "HEAD"], capture_output=True).stdout.decode()
        files = {}
        for rec in out.split("\0"):
            if not rec:
                continue
            meta, path = rec.split("\t", 1)
            _, kind, sha = meta.split()
            if kind == "blob":
                files[path] = sha
        return commit, files
    ref = json.loads(gh_get(f"https://api.github.com/repos/{REPO}/commits/main"))
    commit = ref["sha"]
    tree = json.loads(gh_get(f"https://api.github.com/repos/{REPO}/git/trees/{commit}?recursive=1"))
    if tree.get("truncated"):
        print("::warning::De bestandslijst van de content-repo is afgekapt; niet alle apps worden gevonden.")
    return commit, {t["path"]: t["sha"] for t in tree.get("tree", []) if t.get("type") == "blob"}


def read_file(commit, path):
    if CONTENT_DIR:
        with open(os.path.join(CONTENT_DIR, path), "rb") as f:
            return f.read()
    return gh_get(f"https://raw.githubusercontent.com/{REPO}/{commit}/{urllib.parse.quote(path)}")


# ---------- kiezen wat bij een app hoort ----------
def tokens(path):
    return [t for t in re.split(r"[/\-_ ().]+", path.lower()) if t]


def lang_of(path):
    tk = tokens(path)
    if "nl" in tk:
        return "nl"
    if "en" in tk:
        return "en"
    if OTHER_LANGS & set(tk):
        return "other"
    return None


def size_rank(d):
    dl = d.lower()
    for i, s in enumerate(SIZE_PREF):
        if re.search(r"(?<![\d.])" + re.escape(s) + r"(?![\d])", dl):
            return i
    return len(SIZE_PREF)


def latest_date_dir(paths, prefix):
    """Nieuwste submap (op naam, bijv. 2026-11-12 of 2026-11-11-2) direct onder prefix."""
    subs = {p[len(prefix):].split("/", 1)[0] for p in paths if p.startswith(prefix) and "/" in p[len(prefix):]}
    subs = [s for s in subs if re.match(r"^\d{4}-\d\d-\d\d", s)]
    return max(subs) if subs else None


def pick(files, folder):
    """Screenshots, teksten en OG voor één map in de content-repo."""
    res = {"shots": {}, "text": {}, "og": {}}
    base = folder + "/AppStore/"
    d = latest_date_dir(files, base)
    if d:
        root = base + d + "/"
        in_root = [p for p in files if p.startswith(root)]
        res["source"] = root.rstrip("/")
        # screenshots: per map groeperen
        dirs = {}
        for p in in_root:
            if not p.lower().endswith(IMG):
                continue
            dpath = p.rsplit("/", 1)[0]
            low = dpath.lower()
            rel = low[len(root):]
            if any(s in rel for s in SKIP_DIRS) or any(x in tokens(rel) for x in ("ipad", "mac", "watch", "appletv", "tv")):
                continue
            iphone_size = size_rank(rel) < len(SIZE_PREF) or re.search(r"1206x2622|1320x2868|1179x2556|1284x2778|1242x2688|1242x2208|1290x2796", rel)
            if "iphone" not in rel and not ("screenshot" in rel and iphone_size):
                continue
            dirs.setdefault(dpath, []).append(p)
        by_lang = {}
        for dpath, ps in dirs.items():
            lg = lang_of(dpath)
            if lg == "other":
                continue
            by_lang.setdefault(lg, []).append((size_rank(dpath), -len(ps), dpath, sorted(ps)))
        for lg in ("nl", "en", None):
            if by_lang.get(lg):
                by_lang[lg].sort()
        fallback = by_lang.get(None, [])
        for lg in ("nl", "en"):
            cand = by_lang.get(lg) or fallback
            if cand:
                res["shots"][lg] = cand[0][3][:MAX_SHOTS]
        # teksten uit metadata/<taal>/
        for lg, codes in (("nl", ("nl-nl", "nl")), ("en", ("en-us", "en-gb", "en"))):
            for kind in ("description", "promotional_text", "subtitle"):
                hits = sorted(p for p in in_root if p.lower().endswith(f"/{kind}.txt")
                              and p.lower().split("/")[-2] in codes and "/metadata/" in p.lower())
                if hits:
                    res["text"].setdefault(lg, {})[kind] = hits[-1]
    # OG
    ob = folder + "/OG/"
    od = latest_date_dir(files, ob)
    if od:
        ogs = sorted(p for p in files if p.startswith(ob + od + "/") and p.lower().endswith((".png", ".jpg", ".jpeg")))
        for p in ogs:
            lg = lang_of(p.rsplit("/", 1)[-1]) or lang_of(p)
            if lg in ("nl", "en") and lg not in res["og"]:
                res["og"][lg] = p
        if ogs and not res["og"]:
            res["og"]["nl"] = ogs[0]
    return res


# ---------- verwerken ----------
def to_webp(data, width):
    im = Image.open(io.BytesIO(data))
    im = im.convert("RGBA") if im.mode in ("P", "LA") else im
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "WEBP", quality=80, method=6)
    return out.getvalue(), im.size


def to_og(data):
    im = Image.open(io.BytesIO(data)).convert("RGB")
    if im.size != (1200, 630):
        # bijsnijden naar 1,91:1 en schalen
        r = 1200 / 630
        if im.width / im.height > r:
            w = round(im.height * r)
            im = im.crop(((im.width - w) // 2, 0, (im.width - w) // 2 + w, im.height))
        else:
            h = round(im.width / r)
            im = im.crop((0, (im.height - h) // 2, im.width, (im.height - h) // 2 + h))
        im = im.resize((1200, 630), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "JPEG", quality=86, optimize=True, progressive=True)
    return out.getvalue()


def font(name, size, weight):
    f = ImageFont.truetype(os.path.join(FONTS, name), size)
    try:
        axes = f.get_variation_axes()
        f.set_variation_by_axes([weight if b"eight" in a["name"] else (a["default"] if b"Optical" not in a["name"] else min(a["maximum"], max(a["minimum"], size))) for a in axes])
    except Exception:
        pass
    return f


def wrap(draw, text, f, width, max_lines):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=f) <= width:
            cur = t
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        while draw.textlength(lines[-1] + "…", font=f) > width and " " in lines[-1]:
            lines[-1] = lines[-1].rsplit(" ", 1)[0]
        lines[-1] += "…"
    return lines


def make_og(app, lang):
    """Deelafbeelding 1200x630 in de stijl van de site: donker, icoon, naam en ondertitel."""
    W, H = 1200, 630
    im = Image.new("RGB", (W, H), (13, 16, 24))
    glow = Image.new("RGB", (W, H), (13, 16, 24))
    g = ImageDraw.Draw(glow)
    g.ellipse((640, -220, 1500, 640), fill=(52, 72, 170))
    g.ellipse((-300, 380, 420, 900), fill=(28, 36, 82))
    im = Image.blend(im, glow.filter(ImageFilter.GaussianBlur(160)), 0.85)
    d = ImageDraw.Draw(im)
    # icoon rechts
    icon_path = os.path.join(SITE, app.get("icon") or "")
    if app.get("icon") and os.path.isfile(icon_path):
        ic = Image.open(icon_path).convert("RGBA").resize((300, 300), Image.LANCZOS)
        mask = Image.new("L", (300, 300), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, 299, 299), radius=68, fill=255)
        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle((812, 190, 1112, 490), radius=68, fill=(0, 0, 0, 150))
        im = Image.alpha_composite(im.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(24))).convert("RGB")
        im.paste(ic, (800, 165), mask)
        d = ImageDraw.Draw(im)
    # merk
    logo = os.path.join(SITE, "logo.png")
    if os.path.isfile(logo):
        lg = Image.open(logo).convert("RGBA").resize((56, 56), Image.LANCZOS)
        im.paste(lg, (72, 64), lg)
    d.text((142, 70), "lrvdlinden.app", font=font("BricolageGrotesque.ttf", 30, 700), fill=(233, 236, 244))
    # naam en ondertitel
    name_f = font("BricolageGrotesque.ttf", 92, 800)
    size = 92
    while d.textlength(app["name"], font=name_f) > 660 and size > 54:
        size -= 6
        name_f = font("BricolageGrotesque.ttf", size, 800)
    def L(v):
        return (v.get(lang) or v.get("nl") or v.get("en") or "") if isinstance(v, dict) else (v or "")
    sub = L(app.get("subtitle"))
    if not sub:  # geen ondertitel: eerste zin van de omschrijving
        sub = re.split(r"(?<=[.!?])\s", L(app.get("description")).strip(), maxsplit=1)[0][:110]
    sub_f = font("HankenGrotesk.ttf", 34, 500)
    sub_lines = wrap(d, sub, sub_f, 660, 2) if sub else []
    y = 300 - (len(sub_lines) * 22)
    d.text((72, y), app["name"], font=name_f, fill=(233, 236, 244))
    y += size + 18
    for line in sub_lines:
        d.text((72, y), line, font=sub_f, fill=(170, 178, 198))
        y += 46
    # voetregel
    plats = app.get("platforms") or (["Homey"] if app.get("section") == "homey" else [])
    plat = " · ".join(plats[:5]) + (" …" if len(plats) > 5 else "")
    free = "Gratis · zonder advertenties" if lang == "nl" else "Free · no ads"
    d.text((72, 540), (plat + "   " if plat else "") + free, font=font("HankenGrotesk.ttf", 24, 600), fill=(138, 157, 255))
    out = io.BytesIO()
    im.save(out, "JPEG", quality=86, optimize=True, progressive=True)
    return out.getvalue()


def og_key(app, lang):
    icon_path = os.path.join(SITE, app.get("icon") or "")
    ih = hashlib.sha1(open(icon_path, "rb").read()).hexdigest() if app.get("icon") and os.path.isfile(icon_path) else ""
    return hashlib.sha1(json.dumps([app.get("name"), app.get("subtitle"), app.get("platforms"), app.get("section"), app.get("description"), ih, lang, 3],
                                   ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def main():
    data = json.load(open(APPS_JSON, encoding="utf-8"))
    apps = data.get("apps", [])
    commit, files = load_tree()
    folders = {}
    for p in files:
        top = p.split("/", 1)[0]
        if "/" in p:
            folders.setdefault(norm(top), top)
    os.makedirs(OUT, exist_ok=True)
    changed, log = False, []
    keep = set()
    for app in apps:
        slug = page_slug(app, apps)
        keep.add(slug)
        sdir = os.path.join(OUT, slug)
        cpath = os.path.join(sdir, "content.json")
        try:
            old = json.load(open(cpath, encoding="utf-8"))
        except (OSError, ValueError):
            old = {}
        old_src = old.get("sources", {})
        new = {"slug": slug, "id": app.get("id"), "shots": {}, "text": {}, "og": {}, "sources": {}}
        folder = folders.get(norm(app.get("name"))) if app.get("section") == "ios" else None
        picked = pick(files, folder) if folder else {"shots": {}, "text": {}, "og": {}}
        if folder:
            new["folder"] = folder
            if picked.get("source"):
                new["source"] = picked["source"]
        os.makedirs(sdir, exist_ok=True)
        wanted = set(["content.json"])

        def fetch(src, target, conv):
            """Bestand alleen ophalen als de bron veranderd is."""
            nonlocal changed
            sha = files[src]
            new["sources"][target] = sha
            wanted.add(target)
            tp = os.path.join(sdir, target)
            if old_src.get(target) == sha and os.path.isfile(tp):
                return
            out = conv(read_file(commit, src))
            with open(tp, "wb") as f:
                f.write(out)
            changed = True

        # screenshots
        for lg, srcs in picked["shots"].items():
            lst = []
            for i, src in enumerate(srcs, 1):
                target = f"shot-{lg}-{i:02d}.webp"
                try:
                    fetch(src, target, lambda b: to_webp(b, SHOT_W)[0])
                except Exception as e:  # kapot of geen afbeelding: overslaan
                    print(f"::warning::{app['name']}: {src} overgeslagen ({e})")
                    continue
                im = Image.open(os.path.join(sdir, target))
                if im.height <= im.width:  # alleen staande schermafbeeldingen
                    wanted.discard(target)
                    new["sources"].pop(target, None)
                    continue
                lst.append({"src": target, "w": im.width, "h": im.height})
            if lst:
                new["shots"][lg] = lst
        # teksten
        for lg, kinds in picked["text"].items():
            for kind, src in kinds.items():
                try:
                    txt = read_file(commit, src).decode("utf-8", "replace").strip() if old_src.get(f"text-{lg}-{kind}") != files[src] \
                        else (old.get("text", {}).get(lg, {}).get(kind) or "")
                except Exception:
                    txt = ""
                if txt:
                    new["text"].setdefault(lg, {})[kind] = txt
                    new["sources"][f"text-{lg}-{kind}"] = files[src]
        # OG: uit de content-repo, anders zelf maken
        for lg in ("nl", "en"):
            target = f"og-{lg}.jpg"
            src = picked["og"].get(lg)
            if src:
                try:
                    fetch(src, target, to_og)
                    new["og"][lg] = target
                    continue
                except Exception as e:
                    print(f"::warning::{app['name']}: OG {src} overgeslagen ({e})")
            key = "gen:" + og_key(app, lg)
            new["sources"][target] = key
            wanted.add(target)
            tp = os.path.join(sdir, target)
            if old_src.get(target) != key or not os.path.isfile(tp):
                with open(tp, "wb") as f:
                    f.write(make_og(app, lg))
                changed = True
            new["og"][lg] = target
        # oude bestanden opruimen
        for f in os.listdir(sdir):
            if f not in wanted:
                os.remove(os.path.join(sdir, f))
                changed = True
        if {k: v for k, v in old.items()} != new:
            with open(cpath, "w", encoding="utf-8") as f:
                json.dump(new, f, ensure_ascii=False, indent=1)
                f.write("\n")
            if old.get("sources") != new["sources"] or old.get("shots") != new["shots"]:
                n = sum(len(v) for v in new["shots"].values())
                log.append(f"- {app['name']}: {n} screenshots" + (f" uit {new.get('source', '').split('/AppStore/')[-1]}" if n else "")
                           + (", teksten" if new["text"] else "") + ", OG")
            changed = True
    # apps die niet meer bestaan
    for d in os.listdir(OUT):
        if d not in keep and os.path.isdir(os.path.join(OUT, d)):
            shutil.rmtree(os.path.join(OUT, d))
            log.append(f"- {d}: verwijderd")
            changed = True
    summary = "Content-sync: app-pagina's bijgewerkt\n\n" + ("\n".join(log) if log else "Geen inhoudelijke wijzigingen.") + "\n"
    open("content-sync-summary.md", "w", encoding="utf-8").write(summary)
    print(summary)
    print(f"::notice::Content-sync: {len(log)} app(s) bijgewerkt" if changed else "::notice::Content-sync: niets gewijzigd")


if __name__ == "__main__":
    main()
