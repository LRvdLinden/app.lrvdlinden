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
  return crypto.subtle.importKey("pkcs8", new Uint8Array(pemToDer(pem)), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
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

// ---- Bekendr: downloads (App Store Connect + GitHub Releases) ----
// Bekendr heeft geen eigen server. Het beheer (LRbeheer en bekendr.lrvdlinden.app/beheer) praat met deze functie:
// inlog met de gedeelde beheer-inlog, downloads uit de verkoopoverzichten van App Store Connect (per apparaat) en de
// downloadtellers van de APK in GitHub Releases.

export const BEKENDR_ORIGIN = "https://bekendr.lrvdlinden.app";
export const BEKENDR_REPO = "LRvdLinden/app.lrvdlinden.bekendr";
const BEKENDR_TTL = 12 * 3600;

/** Token van het Bekendr-beheer: {s:"bekendr", e} met HMAC-handtekening. */
export async function makeBekendrToken(secret: string, nowMs = Date.now()): Promise<{ token: string; expires: number }> {
  const e = Math.floor(nowMs / 1000) + BEKENDR_TTL;
  const p = b64u(enc.encode(JSON.stringify({ s: "bekendr", e })));
  return { token: `${p}.${b64u(await hmac(secret, p))}`, expires: e };
}

export async function readBekendrToken(secret: string, token: unknown, nowMs = Date.now()): Promise<boolean> {
  if (!secret || typeof token !== "string" || token.length > MAX_TOKEN) return false;
  const [p, sig] = token.split(".");
  if (!p || !sig) return false;
  let given: Uint8Array;
  try { given = unb64u(sig); } catch { return false; }
  if (!sameBytes(given, await hmac(secret, p))) return false;
  try {
    const o = JSON.parse(new TextDecoder().decode(unb64u(p)));
    return o?.s === "bekendr" && typeof o.e === "number" && o.e * 1000 > nowMs;
  } catch { return false; }
}

/** JWT voor de App Store Connect API (ES256, max. 20 minuten geldig). */
export async function ascJwt(key: CryptoKey, keyId: string, issuer: string, nowS: number): Promise<string> {
  const head = { alg: "ES256", kid: keyId, typ: "JWT" };
  const body = { iss: issuer, iat: nowS, exp: nowS + 15 * 60, aud: "appstoreconnect-v1" };
  const input = `${b64u(enc.encode(JSON.stringify(head)))}.${b64u(enc.encode(JSON.stringify(body)))}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(input));
  return `${input}.${b64u(sig)}`;
}

export type SalesKind = "download" | "redownload" | "update";
/** Product Type Identifier → soort (apps: iPhone 1/3/7, universeel 1F/3F/7F, iPad 1T/3T/7T, Mac F1/F3/F7). */
export function salesKind(type: string): SalesKind | null {
  const t = type.trim().toUpperCase();
  if (["1", "1F", "1T", "F1", "1E", "1EP", "1EU"].includes(t)) return "download";
  if (["3", "3F", "3T", "F3"].includes(t)) return "redownload";
  if (["7", "7F", "7T", "F7"].includes(t)) return "update";
  return null;
}

/** Kolom Device → apparaat zoals in het beheer. */
export function salesDevice(device: string, type: string): string {
  const d = device.trim().toLowerCase();
  if (d === "iphone" || d === "ipod touch" || d === "ipod") return "iPhone";
  if (d === "ipad") return "iPad";
  if (d === "desktop" || d === "mac" || type.trim().toUpperCase().startsWith("F")) return "Mac";
  if (d === "apple tv") return "Apple TV";
  if (d === "apple vision" || d === "apple vision pro") return "Vision Pro";
  return d ? device.trim() : "Overig";
}

export type SalesRow = { device: string; kind: SalesKind; units: number };
/** Welke regels bij een app horen: Apple ID, anders SKU (en/of titel); titel ook met een toevoeging ("Pairr: …"). */
export type SalesMatch = { appleId?: string; title?: string; sku?: string };

function salesTable(tsv: string) {
  const lines = tsv.split(/\r?\n/).filter((l) => l.trim());
  const head = (lines[0] ?? "").split("\t").map((h) => h.trim().toLowerCase());
  return { rows: lines.slice(1).map((l) => l.split("\t")), col: (n: string) => head.indexOf(n) };
}

function salesMatcher(col: (n: string) => number, match: SalesMatch) {
  const iApple = col("apple identifier"), iTitle = col("title"), iSku = col("sku");
  return (c: string[]) => {
    if (match.appleId) return (c[iApple] ?? "").trim() === match.appleId;
    if (match.sku && iSku >= 0 && (c[iSku] ?? "").trim().toLowerCase() === match.sku.toLowerCase()) return true;
    const t = (c[iTitle] ?? "").trim().toLowerCase(), want = (match.title ?? "bekendr").toLowerCase();
    return t === want || (!!match.sku && (t.startsWith(want + ":") || t.startsWith(want + " -") || t.startsWith(want + " –")));
  };
}

/** Verkoopoverzicht (SALES/SUMMARY, tab-gescheiden) → rijen, opgeteld per apparaat en soort. */
export function parseSalesReport(tsv: string, match: SalesMatch): SalesRow[] {
  const { rows, col } = salesTable(tsv);
  const iType = col("product type identifier"), iUnits = col("units"), iDevice = col("device"), iParent = col("parent identifier");
  if (iType < 0 || iUnits < 0) return [];
  const ok = salesMatcher(col, match);
  const sum = new Map<string, SalesRow>();
  for (const c of rows) {
    if (iParent >= 0 && (c[iParent] ?? "").trim()) continue; // in-app aankopen
    if (!ok(c)) continue;
    const kind = salesKind(c[iType] ?? "");
    const units = Number((c[iUnits] ?? "").trim());
    if (!kind || !Number.isFinite(units) || units === 0) continue;
    const device = salesDevice(iDevice >= 0 ? c[iDevice] ?? "" : "", c[iType] ?? "");
    const k = `${device}|${kind}`;
    const r = sum.get(k) ?? { device, kind, units: 0 };
    r.units += units;
    sum.set(k, r);
  }
  return [...sum.values()];
}

// ---- Omzet (betaalde apps, bv. Pairr) ----
export type RevenueRow = { currency: string; units: number; proceeds: number };

/** Opbrengst per valuta uit het verkoopoverzicht: Units × Developer Proceeds van de app zelf (terugbetalingen negatief).
 * Gratis downloads en updates hebben opbrengst 0 en tellen niet mee. */
export function parseSalesRevenue(tsv: string, match: SalesMatch): RevenueRow[] {
  const { rows, col } = salesTable(tsv);
  const iUnits = col("units"), iProc = col("developer proceeds"), iCur = col("currency of proceeds"), iParent = col("parent identifier");
  if (iUnits < 0 || iProc < 0 || iCur < 0) return [];
  const ok = salesMatcher(col, match);
  const sum = new Map<string, RevenueRow>();
  for (const c of rows) {
    if (iParent >= 0 && (c[iParent] ?? "").trim()) continue;
    if (!ok(c)) continue;
    const units = Number((c[iUnits] ?? "").trim()), per = Number((c[iProc] ?? "").trim().replace(",", "."));
    const cur = (c[iCur] ?? "").trim().toUpperCase();
    if (!Number.isFinite(units) || !Number.isFinite(per) || per === 0 || units === 0 || !/^[A-Z]{3}$/.test(cur)) continue;
    const r = sum.get(cur) ?? { currency: cur, units: 0, proceeds: 0 };
    r.units += units;
    r.proceeds = Math.round((r.proceeds + units * per) * 100) / 100;
    sum.set(cur, r);
  }
  return [...sum.values()];
}

/** ECB-referentiekoersen (eurofxref-daily.xml) → { USD: 1.08, … } (1 EUR = x valuta). */
export function parseEcbRates(xml: string): Record<string, number> {
  const out: Record<string, number> = { EUR: 1 };
  for (const m of xml.matchAll(/currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/g)) {
    const r = Number(m[2]);
    if (r > 0) out[m[1]] = r;
  }
  return out;
}

/** Bedrag in euro (2 decimalen) of null als de koers onbekend is. */
export function toEur(amount: number, currency: string, rates: Record<string, number>): number | null {
  const r = rates[currency.toUpperCase()];
  return r ? Math.round((amount / r) * 100) / 100 : null;
}

export type RevenueDbRow = { day: string; currency: string; units: number; proceeds: number; proceeds_eur: number | null };

/** Omzetoverzicht: totaal, deze maand, laatste 30 dagen per dag, per valuta. */
export function revenueSummary(rows: RevenueDbRow[], today: string, days = 30) {
  const t = Date.parse(`${today}T00:00:00Z`);
  const perDay = new Map<string, { day: string; eur: number; units: number }>();
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(t - i * 86400_000).toISOString().slice(0, 10);
    perDay.set(d, { day: d, eur: 0, units: 0 });
  }
  const month = today.slice(0, 7);
  let total = 0, monthEur = 0, units = 0, unconverted = 0, last = "";
  const byCur: Record<string, { units: number; proceeds: number }> = {};
  for (const r of rows) {
    const eur = r.proceeds_eur == null ? null : Number(r.proceeds_eur);
    const u = Number(r.units) || 0;
    units += u;
    if (r.day > last) last = r.day;
    const c = byCur[r.currency] ??= { units: 0, proceeds: 0 };
    c.units += u; c.proceeds = Math.round((c.proceeds + Number(r.proceeds)) * 100) / 100;
    if (eur == null) { unconverted++; continue; }
    total += eur;
    if (r.day.startsWith(month)) monthEur += eur;
    const p = perDay.get(r.day);
    if (p) { p.eur = Math.round((p.eur + eur) * 100) / 100; p.units += u; }
  }
  const r2 = (n: number) => Math.round(n * 100) / 100;
  return { total_eur: r2(total), month_eur: r2(monthEur), units, last_day: last || null, unconverted, by_currency: byCur, days: [...perDay.values()] };
}

export type Release = { tag: string; name: string; published_at: string; downloads: number };

/** GitHub Releases → downloads per Android-release (alle .apk-bestanden opgeteld). Bekendr: tags `android-…`, Noodpakket: `v…`. */
export function apkReleases(releases: unknown, prefix = "android-"): Release[] {
  if (!Array.isArray(releases)) return [];
  return releases
    .filter((r) => r && typeof r === "object" && String((r as { tag_name?: unknown }).tag_name ?? "").startsWith(prefix))
    .map((r) => {
      const o = r as { tag_name: string; name?: unknown; published_at?: unknown; assets?: unknown };
      const assets = Array.isArray(o.assets) ? o.assets as { name?: unknown; download_count?: unknown }[] : [];
      const downloads = assets.filter((a) => String(a?.name ?? "").toLowerCase().endsWith(".apk"))
        .reduce((s, a) => s + (Number(a?.download_count) || 0), 0);
      return { tag: o.tag_name, name: String(o.name ?? o.tag_name), published_at: String(o.published_at ?? ""), downloads };
    })
    .sort((a, b) => b.published_at.localeCompare(a.published_at));
}

export type AndroidState = { day: string; base: number; last: number };

/** Nieuwe dagtoestand van de Android-teller: downloads van vandaag = totaal − stand aan het begin van de dag. */
export function androidStep(prev: AndroidState | null, day: string, total: number): { state: AndroidState; today: number } {
  let s: AndroidState;
  if (!prev) s = { day, base: total, last: total };
  else if (prev.day !== day) s = { day, base: Math.min(prev.last, total), last: total };
  else s = { day, base: Math.min(prev.base, total), last: total };
  return { state: s, today: Math.max(0, total - s.base) };
}

/** Dagen (YYYY-MM-DD, nieuwste eerst) waarvan het Apple-overzicht nog opgehaald moet worden. */
export function appleDaysToFetch(today: string, have: string[], back = 30, max = 8): string[] {
  const out: string[] = [];
  const t = Date.parse(`${today}T00:00:00Z`);
  for (let i = 1; i <= back && out.length < max; i++) {
    const d = new Date(t - i * 86400_000).toISOString().slice(0, 10);
    if (!have.includes(d)) out.push(d);
  }
  return out;
}

export type DailyRow = { day: string; source: string; device: string; kind: string; units: number };

/** Overzicht voor het beheer: totalen per apparaat en per dag (laatste `days` dagen). */
export function bekendrSummary(rows: DailyRow[], today: string, days = 30) {
  const appleTotals: Record<SalesKind, number> = { download: 0, redownload: 0, update: 0 };
  const byDevice: Record<string, number> = {};
  const perDay = new Map<string, { day: string; iPhone: number; iPad: number; Mac: number; other: number; android: number }>();
  const t = Date.parse(`${today}T00:00:00Z`);
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(t - i * 86400_000).toISOString().slice(0, 10);
    perDay.set(d, { day: d, iPhone: 0, iPad: 0, Mac: 0, other: 0, android: 0 });
  }
  let lastAppleDay = "";
  for (const r of rows) {
    const units = Number(r.units) || 0;
    if (r.source === "apple") {
      if (r.kind in appleTotals) appleTotals[r.kind as SalesKind] += units;
      if (r.day > lastAppleDay) lastAppleDay = r.day;
      if (r.kind !== "download") continue;
      byDevice[r.device] = (byDevice[r.device] ?? 0) + units;
      const p = perDay.get(r.day);
      if (p) {
        if (r.device === "iPhone" || r.device === "iPad" || r.device === "Mac") p[r.device] += units; else p.other += units;
      }
    } else if (r.source === "android") {
      const p = perDay.get(r.day);
      if (p) p.android += units;
    }
  }
  return { apple: { totals: appleTotals, by_device: byDevice, last_day: lastAppleDay || null }, days: [...perDay.values()] };
}

// ---- Bekendr: feedback op een bekendmaking (vanuit de app, zonder account) ----
export const FEEDBACK_REASONS = ["locatie", "categorie", "gemeente", "link", "anders"] as const;
export type FeedbackReason = typeof FEEDBACK_REASONS[number];
export type Feedback = {
  notice_id: string; notice_title: string; notice_url: string; reason: FeedbackReason; message: string;
  platform: string; app_version: string; device: string;
};

const clipText = (v: unknown, n: number) => (typeof v === "string" ? v.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").trim().slice(0, n) : "");

/** Feedback uit de app controleren. Geeft een foutcode (string) of de schone feedback. */
export function cleanFeedback(b: Record<string, unknown>): Feedback | string {
  const reason = clipText(b.reason, 20) as FeedbackReason;
  if (!FEEDBACK_REASONS.includes(reason)) return "bad_reason";
  const notice_id = clipText(b.notice_id, 200);
  if (!notice_id) return "bad_notice";
  const message = clipText(b.message, 2000);
  if (reason === "anders" && message.length < 3) return "message_required";
  let notice_url = clipText(b.notice_url, 500);
  try {
    const u = new URL(notice_url);
    if (u.protocol !== "https:" || !/(^|\.)(officielebekendmakingen\.nl|overheid\.nl)$/.test(u.hostname)) notice_url = "";
  } catch { notice_url = ""; }
  const platform = clipText(b.platform, 20);
  const device = clipText(b.device, 64);
  if (!/^[A-Za-z0-9-]{8,64}$/.test(device)) return "bad_device";
  return {
    notice_id, notice_title: clipText(b.notice_title, 300), notice_url, reason, message,
    platform: ["ios", "ipados", "macos", "android"].includes(platform) ? platform : "onbekend",
    app_version: clipText(b.app_version, 40), device,
  };
}

export const FEEDBACK_STATUS = ["nieuw", "afgehandeld"] as const;


// ---- Noodpakket: downloads, Android-builds en berichten aan gebruikers ----
// Noodpakket heeft geen eigen server. Het beheer (LRbeheer en noodpakket.lrvdlinden.app/beheer/) praat met deze functie,
// net als Bekendr. De apps zelf gebruiken alleen: noodpakket_register / noodpakket_unregister (iPhone en iPad, APNs) en
// noodpakket_messages (Android haalt nieuwe berichten op). Er gaat niets anders mee dan een willekeurig apparaatnummer,
// het pushtoken, de taal en de appversie.

export const NOODPAKKET_ORIGIN = "https://noodpakket.lrvdlinden.app";
export const NOODPAKKET_REPO = "LRvdLinden/app.lrvdlinden.noodkoffer";
export const NOODPAKKET_TOPIC = "app.lrvdlinden.noodpakket";
export const NP_PLATFORMS = ["ios", "ipados", "android"] as const;
export const NP_LANGS = ["nl", "en"] as const;
export const NP_TARGET_LANG = ["all", "nl", "en"] as const;
export const NP_TARGET_PLATFORM = ["all", "apple", "android"] as const;
/** Zo lang haalt Android een bericht nog op (dagen). */
export const NP_MESSAGE_DAYS = 7;
const SCOPED_TTL = 12 * 3600;

/** Token voor een beheeromgeving zonder eigen server: {s:<scope>, e} met HMAC-handtekening (12 uur). */
export async function makeScopedToken(secret: string, scope: string, nowMs = Date.now()): Promise<{ token: string; expires: number }> {
  const e = Math.floor(nowMs / 1000) + SCOPED_TTL;
  const p = b64u(enc.encode(JSON.stringify({ s: scope, e })));
  return { token: `${p}.${b64u(await hmac(secret, p))}`, expires: e };
}

export async function readScopedToken(secret: string, scope: string, token: unknown, nowMs = Date.now()): Promise<boolean> {
  if (!secret || typeof token !== "string" || token.length > MAX_TOKEN) return false;
  const [p, sig] = token.split(".");
  if (!p || !sig) return false;
  let given: Uint8Array;
  try { given = unb64u(sig); } catch { return false; }
  if (!sameBytes(given, await hmac(secret, p))) return false;
  try {
    const o = JSON.parse(new TextDecoder().decode(unb64u(p)));
    return o?.s === scope && typeof o.e === "number" && o.e * 1000 > nowMs;
  } catch { return false; }
}

export type NpDevice = { device_id: string; platform: string; apns_token: string | null; sandbox: boolean; lang: string; app_version: string };

/** Aanmelding van een iPhone of iPad (met APNs-token) of een Android-toestel (zonder token). */
export function cleanNpRegister(b: Record<string, unknown>): NpDevice | string {
  const id = typeof b.device_id === "string" && /^[A-Za-z0-9-]{8,64}$/.test(b.device_id) ? b.device_id : null;
  if (!id) return "bad_device_id";
  if (!(NP_PLATFORMS as readonly unknown[]).includes(b.platform)) return "bad_platform";
  const platform = b.platform as string;
  let apns: string | null = null;
  if (platform !== "android") {
    const t = typeof b.apns_token === "string" ? b.apns_token.trim() : "";
    if (!/^[0-9a-fA-F]{64,200}$/.test(t) || t.length % 2) return "bad_apns_token";
    apns = t.toLowerCase();
  }
  if (b.sandbox !== undefined && typeof b.sandbox !== "boolean") return "bad_sandbox";
  const lang = (NP_LANGS as readonly unknown[]).includes(b.lang) ? b.lang as string : "nl";
  return { device_id: id, platform, apns_token: apns, sandbox: b.sandbox === true, lang, app_version: clipText(b.app_version, 40) };
}

export type NpMessage = { title: string; body: string; lang: string; platform: string; url: string };

/** Bericht uit het beheer controleren: titel 3–80 tekens, tekst max. 400, doelgroep taal en platform. */
export function cleanNpMessage(b: Record<string, unknown>): NpMessage | string {
  const title = clipText(b.title, 200);
  const body = clipText(b.body, 2000);
  if (title.length < 3 || title.length > 80) return "bad_title";
  if (body.length > 400) return "bad_body";
  const lang = (NP_TARGET_LANG as readonly unknown[]).includes(b.lang) ? b.lang as string : "all";
  const platform = (NP_TARGET_PLATFORM as readonly unknown[]).includes(b.platform) ? b.platform as string : "all";
  let url = clipText(b.url, 300);
  if (url) {
    try {
      const u = new URL(url);
      if (u.protocol !== "https:") return "bad_url";
      url = u.toString();
    } catch { return "bad_url"; }
  }
  return { title, body, lang, platform, url };
}

/** Hoort een apparaat bij de doelgroep van een bericht? */
export function npTargets(msg: { lang: string; platform: string }, dev: { lang: string; platform: string }): boolean {
  const langOk = msg.lang === "all" || msg.lang === dev.lang;
  const platOk = msg.platform === "all" || (msg.platform === "android" ? dev.platform === "android" : dev.platform !== "android");
  return langOk && platOk;
}

/** APNs-payload voor de Noodpakket-app (opent bij een tik de app, of de link als die er is). */
export function npPayload(m: { id: number; title: string; body: string; url: string }) {
  return {
    aps: { alert: { title: clip(m.title, 120), body: clip(m.body, 240) }, sound: "default", "thread-id": "noodpakket" },
    np_message: m.id,
    ...(m.url ? { url: m.url } : {}),
  };
}

export type BuildRun = { id: number; title: string; status: string; conclusion: string | null; created_at: string; url: string; branch: string };

/** Runs van de Android-workflow (android.yml) → korte lijst voor het beheer. */
export function androidBuilds(runs: unknown, max = 8): BuildRun[] {
  const list = Array.isArray(runs) ? runs as Record<string, unknown>[] : [];
  return list
    .filter((r) => typeof r?.id === "number" && /android/i.test(String(r.name ?? r.path ?? "")))
    .map((r) => ({
      id: r.id as number,
      title: clip(String(r.display_title ?? r.name ?? ""), 120),
      status: String(r.status ?? ""),
      conclusion: r.conclusion == null ? null : String(r.conclusion),
      created_at: String(r.created_at ?? ""),
      url: String(r.html_url ?? ""),
      branch: String(r.head_branch ?? ""),
    }))
    .sort((a, b) => b.created_at.localeCompare(a.created_at))
    .slice(0, max);
}

// ---- Pairr: downloads (App Store Connect) en openstaande meldingen (GitHub Issues) ----
// Pairr heeft geen eigen server en geen Android-versie. Het beheer (LRbeheer en pairr.lrvdlinden.app/beheer/) gebruikt
// pairr_login / pairr_stats met een token van 12 uur (scope "pairr"). Support loopt via GitHub Issues van de openbare repo.
export const PAIRR_ORIGIN = "https://pairr.lrvdlinden.app";
export const PAIRR_REPO = "LRvdLinden/app.lrvdlinden.pairr";

export type Issue = { number: number; title: string; url: string; created_at: string; comments: number; labels: string[] };

/** GitHub Issues → open meldingen (zonder pull requests), nieuwste eerst. */
export function openIssues(raw: unknown, max = 20): Issue[] {
  if (!Array.isArray(raw)) return [];
  const out: Issue[] = [];
  for (const i of raw) {
    if (!i || typeof i !== "object" || "pull_request" in i) continue;
    const o = i as Record<string, unknown>;
    if (o.state !== "open" || typeof o.number !== "number") continue;
    const url = typeof o.html_url === "string" && o.html_url.startsWith("https://github.com/") ? o.html_url : "";
    out.push({
      number: o.number,
      title: String(o.title ?? "").slice(0, 200),
      url,
      created_at: String(o.created_at ?? ""),
      comments: Number(o.comments) || 0,
      labels: Array.isArray(o.labels) ? o.labels.map((l) => String((l as { name?: unknown })?.name ?? "")).filter(Boolean).slice(0, 5) : [],
    });
  }
  return out.sort((a, b) => b.created_at.localeCompare(a.created_at)).slice(0, max);
}
