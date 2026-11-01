"""Eenmalige verkenning 2: volledige Homey-API-antwoorden."""
import json, os, re, urllib.request
os.makedirs("probe", exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15"}
def get(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:500]
    except Exception as e:
        return 0, repr(e)
out = {}
for app in ["nl.lrvdlinden.p2000", "nl.lrvdlinden.postnl", "nl.lrvdlinden.weekdot"]:
    s, b = get(f"https://apps-api.athom.com/api/v1/app/{app}")
    open(f"probe/{app}.json", "w").write(b)
    for suffix in ["/changelog", "/versions", "/build", "/reviews", "/stats"]:
        s2, b2 = get(f"https://apps-api.athom.com/api/v1/app/{app}{suffix}")
        out[app + suffix] = {"status": s2, "body": b2[:3000]}
s, h = get("https://homey.app/nl-nl/app/nl.lrvdlinden.p2000/")
js = sorted(set(re.findall(r'src="([^"]+\.js[^"]*)"', h)))
out["js"] = js
for u in js:
    if u.startswith("/"): u = "https://homey.app" + u
    if "homey.app" not in u: continue
    s3, b3 = get(u)
    hits = [b3[max(0, m.start() - 400): m.start() + 400] for m in re.finditer(r"changelog", b3, re.I)][:6]
    if hits: out["jsHits " + u] = hits
json.dump(out, open("probe/result2.json", "w"), indent=2, ensure_ascii=False)
