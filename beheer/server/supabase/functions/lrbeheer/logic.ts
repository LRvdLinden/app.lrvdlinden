// Functie lrbeheer: pure hulpjes (geen netwerk of database), getest in logic_test.ts.
// Centraal pushsysteem van de app LRbeheer voor LRvdLinden, PixelForges en Tunr. Draait in het Supabase-project van Tunr
// en hergebruikt de beheer-inlog van TunrBeheer: het token komt van de functie `admin` (zelfde vorm en sleutel, zie
// tunr-beheer/supabase/functions/admin/auth.ts; die functie zelf verandert niet).

const enc = new TextEncoder();

export const TOKEN_SCOPE = "admin";
export const MAX_TOKEN = 400;
export const DEFAULT_TOPIC = "app.lrvdlinden.lrbeheer";
export const ENVS = ["lrvdlinden", "pixelforges", "tunr"] as const;
export type Env = typeof ENVS[number];
export const KINDS: Record<Env, readonly string[]> = {
  lrvdlinden: ["store", "deploy"],
  pixelforges: ["deploy", "content", "contact"],
  tunr: ["installs", "presskit"],
};
export type Prefs = Record<Env, Record<string, boolean>>;
export const PLATFORMS = ["ios", "ipados", "macos"] as const;

export const b64u = (b: Uint8Array | ArrayBuffer) => {
  const u = b instanceof Uint8Array ? b : new Uint8Array(b);
  let s = "";
  for (let i = 0; i < u.length; i += 8192) s += String.fromCharCode(...u.subarray(i, i + 8192));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
export const unb64u = (s: string) =>
  Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));

export function sameBytes(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}
export async function hmac(key: string, data: string): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(data)));
}

/** Tunr-beheertoken controleren: handtekening (TUNR_TOKEN_SECRET), scope en verloop. Tokenversie vergelijkt de aanroeper. */
export async function readTunrToken(secret: string, token: unknown, now = Date.now()): Promise<{ v: number; e: number } | null> {
  if (!secret || typeof token !== "string" || token.length > MAX_TOKEN) return null;
  const m = /^([A-Za-z0-9_-]{8,300})\.([A-Za-z0-9_-]{43})$/.exec(token);
  if (!m) return null;
  let p: Record<string, unknown>;
  try {
    if (!sameBytes(unb64u(m[2]), await hmac(secret, m[1]))) return null;
    p = JSON.parse(new TextDecoder().decode(unb64u(m[1])));
  } catch { return null; }
  if (!p || typeof p !== "object" || Array.isArray(p)) return null;
  if (p.s !== TOKEN_SCOPE || !Number.isInteger(p.v) || !Number.isInteger(p.e)) return null;
  if ((p.e as number) <= Math.floor(now / 1000)) return null;
  return { v: p.v as number, e: p.e as number };
}

export function bearer(h: Headers): string | null {
  const m = /^Bearer\s+(\S+)$/i.exec((h.get("authorization") ?? "").trim());
  return m ? m[1] : null;
}

// ---- registratie ----

export function defaultPrefs(): Prefs {
  return Object.fromEntries(ENVS.map((e) => [e, Object.fromEntries(KINDS[e].map((k) => [k, true]))])) as Prefs;
}

/** Schakelaars opschonen: onbekende omgevingen/soorten vallen weg, ontbrekende staan aan. */
export function cleanPrefs(v: unknown): Prefs {
  const out = defaultPrefs();
  if (!v || typeof v !== "object" || Array.isArray(v)) return out;
  for (const e of ENVS) {
    const o = (v as Record<string, unknown>)[e];
    if (!o || typeof o !== "object" || Array.isArray(o)) continue;
    for (const k of KINDS[e]) {
      const b = (o as Record<string, unknown>)[k];
      if (typeof b === "boolean") out[e][k] = b;
    }
  }
  return out;
}

export type Register = { device_id: string; token: string; sandbox: boolean; platform: string; app_build: number; prefs: Prefs };

export function cleanRegister(b: Record<string, unknown>): Register | string {
  const id = typeof b.device_id === "string" && /^[A-Za-z0-9_-]{8,80}$/.test(b.device_id) ? b.device_id : null;
  if (!id) return "bad_device_id";
  const t = typeof b.apns_token === "string" ? b.apns_token.trim() : "";
  if (!/^[0-9a-fA-F]{64,200}$/.test(t) || t.length % 2) return "bad_apns_token";
  if (!(PLATFORMS as readonly unknown[]).includes(b.platform)) return "bad_platform";
  if (b.sandbox !== undefined && typeof b.sandbox !== "boolean") return "bad_sandbox";
  const build = typeof b.app_build === "number" && Number.isInteger(b.app_build) && b.app_build >= 0 && b.app_build < 1e6 ? b.app_build : 0;
  return { device_id: id, token: t.toLowerCase(), sandbox: b.sandbox === true, platform: b.platform as string, app_build: build, prefs: cleanPrefs(b.prefs) };
}

export function wants(prefs: unknown, env: Env, kind: string): boolean {
  const p = cleanPrefs(prefs);
  return p[env]?.[kind] !== false;
}

// ---- meldingen ----

export type Notice = { env: Env; kind: string; title: string; body: string; url: string; key: string };

const clip = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s);

/** APNs-payload. `lrenv` vertelt LRbeheer welke omgeving hij moet openen; `url` welk onderdeel. */
export function payload(n: Notice) {
  return {
    aps: { alert: { title: clip(n.title, 120), body: clip(n.body, 240) }, sound: "default", "thread-id": n.env },
    lrenv: n.env,
    kind: n.kind,
    url: n.url,
  };
}

/** Uitkomst van APNs: invalid = token weg (niet bij een ander topic: dan hoort het token bij een andere app). */
export function apnsResult(status: number, reason: string): { ok: true } | { ok: false; invalid: boolean; error: string } {
  if (status === 200) return { ok: true };
  const r = /^[A-Za-z]{1,40}$/.test(reason) ? reason : "";
  const invalid = status === 410 || ["BadDeviceToken", "Unregistered", "ExpiredToken"].includes(r);
  return { ok: false, invalid, error: `apns_${r || status}` };
}

export const apnsHost = (sandbox: boolean) => sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";

export function pemToDer(pem: string): Uint8Array {
  const body = String(pem ?? "").replace(/\\n/g, "\n").replace(/-----(BEGIN|END)[^-]+-----/g, "").replace(/\s+/g, "");
  if (!body) throw new Error("empty_key");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}
export function importApnsKey(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}
export async function apnsJwt(key: CryptoKey, keyId: string, teamId: string, nowS: number): Promise<string> {
  const input = `${b64u(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })))}.${b64u(enc.encode(JSON.stringify({ iss: teamId, iat: nowS })))}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(input));
  return `${input}.${b64u(sig)}`;
}

// ---- bronnen (alleen openbare gegevens; de sites zelf veranderen niet) ----

type StoreRun = { id?: unknown; time?: unknown; mode?: unknown; changed?: unknown; lines?: unknown };

/** logs/store-check.json van LRvdLinden/app.lrvdlinden: nieuwe runs met wijzigingen sinds `lastId`. */
export function storeNotices(book: unknown, lastId: string | null): { notices: Notice[]; newest: string | null } {
  const runs = (book && typeof book === "object" && Array.isArray((book as { runs?: unknown }).runs) ? (book as { runs: StoreRun[] }).runs : [])
    .filter((r) => r && (typeof r.id === "string" || typeof r.id === "number"))
    .sort((a, b) => String(b.time ?? "").localeCompare(String(a.time ?? "")));
  const newest = runs.length ? String(runs[0].id) : null;
  if (lastId === null) return { notices: [], newest }; // eerste keer: alleen onthouden, niets sturen
  const out: Notice[] = [];
  for (const r of runs) {
    if (String(r.id) === lastId) break;
    if (r.changed !== true) continue;
    const lines = Array.isArray(r.lines) ? r.lines.filter((l): l is string => typeof l === "string") : [];
    const mode = r.mode === "nieuw" ? "Nieuwe apps ophalen" : r.mode === "bijwerken" ? "Apps bijwerken" : "Dagelijkse check";
    out.push({
      env: "lrvdlinden", kind: "store", key: `store:${r.id}`,
      title: `Store-check: ${lines.length || 1} ${lines.length === 1 ? "wijziging" : "wijzigingen"}`,
      body: lines.length ? lines.slice(0, 3).join(" · ") + (lines.length > 3 ? ` (+${lines.length - 3})` : "") : mode,
      url: "lrbeheer://lrvdlinden/log",
    });
  }
  return { notices: out.slice(0, 5), newest };
}

/** Nieuwe apps in site/apps.json (id's die er de vorige keer niet waren). */
export function newAppNotices(apps: unknown, known: string[] | null): { notices: Notice[]; ids: string[] } {
  const list = (apps && typeof apps === "object" && Array.isArray((apps as { apps?: unknown }).apps) ? (apps as { apps: Record<string, unknown>[] }).apps : []);
  const ids = list.map((a) => String(a?.id ?? "")).filter(Boolean);
  if (known === null) return { notices: [], ids };
  const k = new Set(known);
  const added = list.filter((a) => a && !k.has(String(a.id ?? "")));
  return {
    ids,
    notices: added.slice(0, 5).map((a) => ({
      env: "lrvdlinden" as const, kind: "store", key: `app:${a.id}`,
      title: "Nieuwe app op lrvdlinden.app", body: String(a.name ?? a.id), url: "lrbeheer://lrvdlinden",
    })),
  };
}

type Run = { id?: unknown; name?: unknown; status?: unknown; conclusion?: unknown; html_url?: unknown; display_title?: unknown; updated_at?: unknown };

/** GitHub Actions-runs van de site-repo: afgerond sinds `lastId` → gepubliceerd of mislukt. */
export function deployNotices(env: "lrvdlinden" | "pixelforges", runs: unknown, lastId: number | null): { notices: Notice[]; newest: number | null } {
  const list = (Array.isArray(runs) ? runs as Run[] : []).filter((r) => typeof r?.id === "number" && r.status === "completed");
  const newest = list.length ? Math.max(...list.map((r) => r.id as number)) : lastId;
  if (lastId === null) return { notices: [], newest };
  const site = env === "lrvdlinden" ? "lrvdlinden.app" : "pixelforges.nl";
  const out: Notice[] = [];
  for (const r of list.filter((r) => (r.id as number) > lastId).sort((a, b) => (a.id as number) - (b.id as number))) {
    if (r.conclusion === "cancelled" || r.conclusion === "skipped") continue;
    const ok = r.conclusion === "success";
    // alleen de deploy-workflow ("Release site"), niet de dagelijkse store-check (die heeft een eigen melding)
    if (!/release|deploy|site/i.test(String(r.name ?? ""))) continue;
    out.push({
      env, kind: "deploy", key: `deploy:${r.id}`,
      title: ok ? `${site} is bijgewerkt` : `Deploy van ${site} mislukt`,
      body: clip(String(r.display_title ?? r.name ?? ""), 200),
      url: `lrbeheer://${env}`,
    });
  }
  return { notices: out.slice(-5), newest };
}

/** Laatste commit op site/content.json van PixelForges. */
export function contentNotice(commits: unknown, lastSha: string | null): { notice: Notice | null; sha: string | null } {
  const c = Array.isArray(commits) && commits.length ? commits[0] as { sha?: unknown; commit?: { message?: unknown } } : null;
  const sha = typeof c?.sha === "string" ? c.sha : null;
  if (!sha || lastSha === null || sha === lastSha) return { notice: null, sha: sha ?? lastSha };
  const msg = String(c?.commit?.message ?? "").split("\n")[0];
  return {
    sha,
    notice: { env: "pixelforges", kind: "content", key: `content:${sha}`, title: "Inhoud van pixelforges.nl gewijzigd", body: clip(msg, 200), url: "lrbeheer://pixelforges" },
  };
}

/** Dagelijks overzicht van nieuwe Tunr-installaties. */
export function installsNotice(day: string, count: number, byPlatform: Record<string, number>): Notice | null {
  if (count <= 0) return null;
  const parts = Object.entries(byPlatform).sort((a, b) => b[1] - a[1]).slice(0, 4).map(([p, n]) => `${p} ${n}`);
  return {
    env: "tunr", kind: "installs", key: `installs:${day}`,
    title: `Tunr: ${count} nieuwe ${count === 1 ? "installatie" : "installaties"}`,
    body: parts.join(" · "), url: "lrbeheer://tunr/overview",
  };
}

export function presskitNotice(lastId: number, rows: { id: number; version: string }[]): Notice | null {
  if (!rows.length) return null;
  const v = rows[rows.length - 1].version;
  return {
    env: "tunr", kind: "presskit", key: `presskit:${rows[rows.length - 1].id}`,
    title: rows.length === 1 ? "Tunr-perskit gedownload" : `Tunr-perskit ${rows.length}× gedownload`,
    body: v ? `Versie ${v}` : "Perskit", url: "lrbeheer://tunr/overview",
  };
}

/** Melding van buitenaf (actie notify met LRBEHEER_NOTIFY_SECRET), bv. een optionele haak in het contactformulier. */
export function cleanNotify(b: Record<string, unknown>): Notice | string {
  const env = b.env;
  if (!(ENVS as readonly unknown[]).includes(env)) return "bad_env";
  const kind = typeof b.kind === "string" ? b.kind : "";
  if (!KINDS[env as Env].includes(kind)) return "bad_kind";
  const title = typeof b.title === "string" ? b.title.trim() : "";
  if (!title) return "bad_title";
  const body = typeof b.body === "string" ? b.body.trim() : "";
  const url = typeof b.url === "string" && /^lrbeheer:\/\/[a-z0-9]+(\/[A-Za-z0-9_\/-]*)?$/.test(b.url) ? b.url : `lrbeheer://${env}`;
  return { env: env as Env, kind, title: clip(title, 120), body: clip(body, 240), url, key: `notify:${Date.now()}` };
}

/** Nederlandse datum (YYYY-MM-DD) en uur van een tijdstip. */
export function amsterdam(now: Date): { day: string; hour: number } {
  const f = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Amsterdam", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", hour12: false });
  const p = Object.fromEntries(f.formatToParts(now).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, hour: Number(p.hour) % 24 };
}
