"""Adressen van de app-pagina's. Zelfde regels als pageSlug()/pageUrl() in site/index.html.

- iOS-apps:   /app/<naam>/     bijv. /app/bekendr/
- Homey-apps: /homey/<naam>/   bijv. /homey/p2000/
Hebben twee apps in dezelfde soort dezelfde naam, dan krijgt de tweede -2, enz.
De content (screenshots, OG) staat in site/app-content/<content_key>/: <naam> voor iOS, homey-<naam> voor Homey.
"""
import re
import unicodedata


def slugify(name):
    s = unicodedata.normalize("NFKD", str(name or ""))
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "app"


def page_kind(app):
    return "homey" if app.get("section") == "homey" else "app"


def page_slug(app, apps):
    base = slugify(app.get("name"))
    same = [o for o in apps if slugify(o.get("name")) == base and page_kind(o) == page_kind(app)]
    if len(same) > 1:
        i = next(i for i, o in enumerate(same) if o is app)
        if i > 0:
            return f"{base}-{i + 1}"
    return base


def page_path(app, apps):
    """Pad zonder domein, bijv. /homey/p2000/"""
    return f"/{page_kind(app)}/{page_slug(app, apps)}/"


def content_key(app, apps):
    slug = page_slug(app, apps)
    return f"homey-{slug}" if page_kind(app) == "homey" else slug


def legacy_homey_path(app, apps):
    """Oud adres van een Homey-app (13 nov 2026 kort gebruikt): /app/<naam>/ of /app/<naam>-homey/."""
    base = slugify(app.get("name"))
    clash = any(o is not app and slugify(o.get("name")) == base and o.get("section") != "homey" for o in apps)
    return f"app/{base}-homey" if clash else f"app/{base}"


def norm(name):
    """Voor het koppelen van een app aan een map in de content-repo: alleen letters en cijfers."""
    return re.sub(r"[^a-z0-9]", "", slugify(name))
