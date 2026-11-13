"""Adres van de eigen app-pagina (/app/<slug>/). Zelfde regels als pageSlug() in site/index.html."""
import re
import unicodedata


def slugify(name):
    s = unicodedata.normalize("NFKD", str(name or ""))
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "app"


def page_slug(app, apps):
    base = slugify(app.get("name"))
    clash = any(o is not app and slugify(o.get("name")) == base and o.get("section") != app.get("section") for o in apps)
    slug = base + "-homey" if clash and app.get("section") == "homey" else base
    same = [o for o in apps if slugify(o.get("name")) == base and o.get("section") == app.get("section")]
    if len(same) > 1:
        i = next(i for i, o in enumerate(same) if o is app)
        if i > 0:
            slug += f"-{i + 1}"
    return slug


def norm(name):
    """Voor het koppelen van een app aan een map in de content-repo: alleen letters en cijfers."""
    return re.sub(r"[^a-z0-9]", "", slugify(name))
