"""Eenmalige verkenning: haalt ruwe store-gegevens op en schrijft ze naar probe/."""
import json, os, re, urllib.request

os.makedirs("probe", exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15"}

def get(url):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:2000]
    except Exception as e:
        return 0, repr(e)

out = {}
for cc in ["nl", "us"]:
    s, b = get(f"https://itunes.apple.com/lookup?id=6821401598,1583422149&country={cc}&entity=software")
    out[f"itunes_{cc}"] = {"status": s, "body": json.loads(b) if s == 200 else b}

for app in ["nl.lrvdlinden.p2000", "nl.lrvdlinden.weekdot"]:
    for url in [
        f"https://apps-api.athom.com/api/v1/app/{app}",
        f"https://apps-api.athom.com/api/v1/app/{app}/build/latest",
        f"https://apps-api.athom.com/api/v1/app/{app}/version/latest",
        f"https://apps.athom.com/api/v1/app/{app}",
    ]:
        s, b = get(url)
        out[url] = {"status": s, "body": b[:6000]}
    for loc in ["nl-nl", "en-us"]:
        url = f"https://homey.app/{loc}/app/{app}/"
        s, b = get(url)
        open(f"probe/{app}-{loc}.html", "w").write(b)
        scripts = re.findall(r'<script[^>]*>(.*?)</script>', b, re.S)
        out[url] = {
            "status": s,
            "len": len(b),
            "json_scripts": [x[:4000] for x in scripts if ("version" in x.lower() or "changelog" in x.lower())][:5],
            "api_urls": sorted(set(re.findall(r'https?://[a-z0-9.-]*athom[a-z0-9./_-]*', b)))[:40],
            "version_snippets": [m.group(0) for m in re.finditer(r'.{0,160}(?:[Vv]ersie|[Vv]ersion|[Cc]hangelog|Wat is (?:er )?nieuw|What.s new|rating|review|install).{0,240}', re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', b)))][:25],
        }

json.dump(out, open("probe/result.json", "w"), indent=2, ensure_ascii=False)
print("klaar")
