// Functie lrbeheer: centraal pushsysteem van de app LRbeheer (LRvdLinden, PixelForges en Tunr).
// Deploy in het Supabase-project van Tunr (zie beheer/server/README.md). Verandert niets aan de functie `admin`,
// aan de sites of aan bestaande tabellen; voegt alleen de tabellen lrbeheer_* toe (schema.sql).
//
// POST /functions/v1/lrbeheer
//   App (Authorization: Bearer <Tunr-beheertoken>):  {action: register|unregister|test|history, ...}
//   Cron (x-lrbeheer-cron: LRBEHEER_CRON_SECRET):   {action: "cron"}   — pg_cron elke 5 minuten
//   Haak (x-lrbeheer-secret: LRBEHEER_NOTIFY_SECRET): {action: "notify", env, kind, title, body?, url?}
//
//   Bekendr-beheer (ook vanuit de browser op https://bekendr.lrvdlinden.app/beheer):
//     {action: "bekendr_login", user, password}  → token (12 uur), met de gedeelde beheer-inlog
//     {action: "bekendr_stats"} met Authorization: Bearer <Bekendr-token> → downloads Apple (per apparaat) en Android
//     {action: "bekendr_feedback_list" | "bekendr_feedback_update"} met het Bekendr-token → feedback bekijken en afhandelen
//   Bekendr-app (zonder account): {action: "bekendr_feedback", notice_id, notice_title, notice_url, reason, message, platform, app_version, device}
//
// Function-secrets: TUNR_TOKEN_SECRET (bestaat al, van `admin`), APNS_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID (dezelfde
// APNs-sleutel als Bingr/Pasr), LRBEHEER_APNS_TOPIC (optioneel, standaard app.lrvdlinden.lrbeheer),
// LRBEHEER_CRON_SECRET, LRBEHEER_NOTIFY_SECRET (optioneel), GITHUB_TOKEN (optioneel, alleen lezen van openbare repo's).
// Bekendr: BEHEER_APP_USER / BEHEER_APP_PASSWORD (gedeelde beheer-inlog), ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8 /
// ASC_VENDOR_NUMBER (App Store Connect-API, verkoopoverzichten), optioneel ASC_BEKENDR_APPLE_ID en BEKENDR_TOKEN_SECRET.
// Nooit tokens, sleutels of apparaat-id's loggen.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  amsterdam, androidStep, type AndroidState, apkReleases, apnsHost, apnsJwt, apnsResult, appleDaysToFetch, ascJwt,
  BEKENDR_ORIGIN, BEKENDR_REPO, bekendrSummary, bearer, cleanFeedback, FEEDBACK_STATUS, type DailyRow, makeBekendrToken, parseSalesReport, readBekendrToken, cleanNotify, cleanPrefs, cleanRegister, contentNotice, deployNotices,
  hmac, importApnsKey, installsNotice, newAppNotices, type Notice, payload, presskitNotice, readTunrToken, sameBytes,
  storeNotices, wants,
} from "./logic.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
/** APNs-sleutel: namen van Bingr/Pasr (APNS_*) of de centrale namen uit app.lrvdlinden.secrets (APN_*, TEAM_ID). */
const apnsKey = () => env("APNS_KEY_P8") || env("APN_P8_CERT");
const apnsKeyId = () => env("APNS_KEY_ID") || env("APN_KEY_ID");
const apnsTeam = () => env("APNS_TEAM_ID") || env("TEAM_ID") || "EU3UY476T6";
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { autoRefreshToken: false, persistSession: false } });

const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...extra } });

/** CORS alleen voor het web-beheer van Bekendr, en alleen voor de bekendr_*-acties. */
const bekendrCors = {
  "Access-Control-Allow-Origin": BEKENDR_ORIGIN,
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Max-Age": "86400",
  Vary: "Origin",
};

async function sameSecret(given: string | null, expected: string): Promise<boolean> {
  if (!given || !expected) return false;
  const [a, b] = await Promise.all([hmac(expected, `cmp|${given}`), hmac(expected, `cmp|${expected}`)]);
  return sameBytes(a, b);
}

/** Tunr-beheertoken geldig én tokenversie gelijk aan admin_token_state (Overal uitloggen in Tunr geldt ook hier). */
async function validToken(token: string | null): Promise<boolean> {
  const t = await readTunrToken(env("TUNR_TOKEN_SECRET"), token);
  if (!t) return false;
  const { data, error } = await db.from("admin_token_state").select("v").eq("id", 1).maybeSingle();
  return !error && Number(data?.v ?? 1) === t.v;
}

// ---- APNs ----
let apnsAuth: { jwt: string; at: number } | null = null;
async function apnsBearer(): Promise<string> {
  const now = Date.now();
  if (apnsAuth && now - apnsAuth.at < 50 * 60_000) return apnsAuth.jwt;
  const iat = Math.floor(now / 1000 / 1800) * 1800; // zelfde blok van 30 min als de andere functies (TooManyProviderTokenUpdates)
  const jwt = await apnsJwt(await importApnsKey(apnsKey()), apnsKeyId(), apnsTeam(), iat);
  apnsAuth = { jwt, at: iat * 1000 };
  return jwt;
}

async function apnsSend(token: string, sandbox: boolean, body: unknown, collapse?: string) {
  let auth: string;
  try { auth = await apnsBearer(); } catch { return { ok: false as const, invalid: false, error: "apns_bad_key" }; }
  try {
    const res = await fetch(`${apnsHost(sandbox)}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${auth}`,
        "apns-topic": env("LRBEHEER_APNS_TOPIC") || "app.lrvdlinden.lrbeheer",
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
        ...(collapse ? { "apns-collapse-id": collapse.slice(0, 64) } : {}),
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
    let reason = "";
    if (res.status !== 200) { try { reason = String((await res.json())?.reason ?? ""); } catch { /* leeg */ } }
    else await res.body?.cancel().catch(() => {});
    const r = apnsResult(res.status, reason);
    if (!r.ok && /^(Expired|Invalid)ProviderToken$/.test(reason)) apnsAuth = null;
    return r;
  } catch { return { ok: false as const, invalid: false, error: "apns_unreachable" }; }
}

type Device = { device_id: string; token: string; sandbox: boolean; prefs: unknown };

async function deliver(notices: Notice[]): Promise<{ sent: number; failed: number }> {
  let sent = 0, failed = 0;
  if (!notices.length) return { sent, failed };
  const { data, error } = await db.from("lrbeheer_devices").select("device_id, token, sandbox, prefs").limit(50);
  if (error) throw new Error(`lrbeheer_devices: ${error.code ?? "fout"}`);
  const devices = (data ?? []) as Device[];
  const gone = new Set<string>();
  for (const n of notices) {
    const targets = devices.filter((d) => !gone.has(d.device_id) && wants(d.prefs, n.env, n.kind));
    const results = await Promise.all(targets.map(async (d) => ({ d, r: await apnsSend(d.token, d.sandbox, payload(n), n.key) })));
    for (const { d, r } of results) {
      if (r.ok) sent++; else { failed++; if (r.invalid) gone.add(d.device_id); }
    }
    await db.from("lrbeheer_events").insert({ env: n.env, kind: n.kind, title: n.title, body: n.body, url: n.url, sent: results.filter((x) => x.r.ok).length });
  }
  if (gone.size) await db.from("lrbeheer_devices").delete().in("device_id", [...gone]);
  return { sent, failed };
}

// ---- Bekendr ----
async function bekendrSecret(): Promise<string> {
  if (env("BEKENDR_TOKEN_SECRET")) return env("BEKENDR_TOKEN_SECRET");
  const base = env("LRBEHEER_CRON_SECRET");
  if (!base) return "";
  return [...await hmac(base, "bekendr-token")].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const ascConfigured = () => !!(env("ASC_KEY_ID") && env("ASC_ISSUER_ID") && env("ASC_KEY_P8") && env("ASC_VENDOR_NUMBER"));

/** Eén dag uit de verkoopoverzichten: rijen, of null als er (nog) geen overzicht is. */
async function appleSalesDay(day: string, jwt: string): Promise<ReturnType<typeof parseSalesReport> | null> {
  const q = new URLSearchParams({
    "filter[frequency]": "DAILY", "filter[reportDate]": day, "filter[reportSubType]": "SUMMARY",
    "filter[reportType]": "SALES", "filter[vendorNumber]": env("ASC_VENDOR_NUMBER"), "filter[version]": "1_1",
  });
  const r = await fetch(`https://api.appstoreconnect.apple.com/v1/salesReports?${q}`, {
    headers: { Authorization: `Bearer ${jwt}`, Accept: "application/a-gzip" }, signal: AbortSignal.timeout(30000),
  });
  if (r.status === 404) { await r.body?.cancel().catch(() => {}); return null; }
  if (!r.ok || !r.body) { await r.body?.cancel().catch(() => {}); throw new Error(`App Store Connect HTTP ${r.status}`); }
  const tsv = await new Response(r.body.pipeThrough(new DecompressionStream("gzip"))).text();
  return parseSalesReport(tsv, env("ASC_BEKENDR_APPLE_ID") ? { appleId: env("ASC_BEKENDR_APPLE_ID") } : { title: "Bekendr" });
}

async function bekendrReleases() {
  return apkReleases(await getJSON(`https://api.github.com/repos/${BEKENDR_REPO}/releases?per_page=100`, true));
}

/** Elk uur: Android-teller bijwerken en ontbrekende Apple-dagen ophalen. */
async function bekendrSync(today: string) {
  const releases = await bekendrReleases();
  const total = releases.reduce((s, r) => s + r.downloads, 0);
  const a = androidStep(await getState<AndroidState>("bekendr_android"), today, total);
  await setState("bekendr_android", a.state);
  const { error } = await db.from("lrbeheer_bekendr_daily").upsert({ day: today, source: "android", device: "Android", kind: "download", units: a.today });
  if (error) throw new Error(`bekendr android: ${error.code ?? "db"}`);

  if (!ascConfigured()) return;
  const have = (await getState<string[]>("bekendr_apple_days")) ?? [];
  const todo = appleDaysToFetch(today, have);
  if (!todo.length) return;
  const jwt = await ascJwt(await importApnsKey(env("ASC_KEY_P8")), env("ASC_KEY_ID"), env("ASC_ISSUER_ID"), Math.floor(Date.now() / 1000));
  const done = new Set(have);
  for (const day of todo) {
    const rows = await appleSalesDay(day, jwt);
    const age = (Date.parse(`${today}T00:00:00Z`) - Date.parse(`${day}T00:00:00Z`)) / 86400_000;
    if (rows === null) { if (age >= 3) done.add(day); continue; } // geen overzicht = geen verkoop (na 3 dagen definitief)
    await db.from("lrbeheer_bekendr_daily").delete().eq("day", day).eq("source", "apple");
    if (rows.length) {
      const { error: e } = await db.from("lrbeheer_bekendr_daily").insert(rows.map((r) => ({ day, source: "apple", ...r })));
      if (e) throw new Error(`bekendr apple: ${e.code ?? "db"}`);
    }
    done.add(day);
  }
  const keep = [...done].sort().reverse().slice(0, 60);
  await setState("bekendr_apple_days", keep);
}

async function feedbackOpen(): Promise<number> {
  const { count } = await db.from("lrbeheer_bekendr_feedback").select("id", { count: "exact", head: true }).eq("status", "nieuw");
  return count ?? 0;
}

async function bekendrStats() {
  const { day: today } = amsterdam(new Date());
  const since = new Date(Date.parse(`${today}T00:00:00Z`) - 400 * 86400_000).toISOString().slice(0, 10);
  const { data, error } = await db.from("lrbeheer_bekendr_daily").select("day, source, device, kind, units").gte("day", since).limit(20000);
  if (error) throw new Error(error.message);
  let releases: Awaited<ReturnType<typeof bekendrReleases>> = [];
  let githubOk = true;
  try { releases = await bekendrReleases(); } catch { githubOk = false; }
  const sum = bekendrSummary((data ?? []) as DailyRow[], today);
  const { data: st } = await db.from("lrbeheer_state").select("updated_at").eq("key", "bekendr_android").maybeSingle();
  return {
    ok: true,
    today,
    synced_at: st?.updated_at ?? null,
    apple: { configured: ascConfigured(), ...sum.apple },
    android: { total: releases.reduce((s, r) => s + r.downloads, 0), releases: releases.slice(0, 20), available: githubOk },
    days: sum.days,
    feedback_open: await feedbackOpen(),
  };
}

// ---- toestand ----
async function getState<T>(key: string): Promise<T | null> {
  const { data } = await db.from("lrbeheer_state").select("value").eq("key", key).maybeSingle();
  return (data?.value ?? null) as T | null;
}
async function setState(key: string, value: unknown) {
  await db.from("lrbeheer_state").upsert({ key, value, updated_at: new Date().toISOString() });
}

// ---- bronnen ----
async function getJSON(url: string, github = false): Promise<unknown> {
  const headers: Record<string, string> = { "User-Agent": "lrbeheer-push", Accept: github ? "application/vnd.github+json" : "application/json" };
  if (github && env("GITHUB_TOKEN")) headers.Authorization = `Bearer ${env("GITHUB_TOKEN")}`;
  const r = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
  if (!r.ok) { await r.body?.cancel().catch(() => {}); throw new Error(`HTTP ${r.status}`); }
  return await r.json();
}

async function cron(forceBekendr = false) {
  const notices: Notice[] = [];
  const errors: string[] = [];
  const step = async (name: string, f: () => Promise<void>) => { try { await f(); } catch (e) { errors.push(`${name}: ${e instanceof Error ? e.message : "fout"}`); } };

  // LRvdLinden: store-check-logboek en nieuwe apps (openbare repo; de site zelf wordt niet aangeroepen)
  await step("store", async () => {
    const book = await getJSON("https://raw.githubusercontent.com/LRvdLinden/app.lrvdlinden/main/logs/store-check.json");
    const r = storeNotices(book, await getState<string>("store_last"));
    notices.push(...r.notices);
    if (r.newest) await setState("store_last", r.newest);
  });
  await step("apps", async () => {
    const apps = await getJSON("https://raw.githubusercontent.com/LRvdLinden/app.lrvdlinden/main/site/apps.json");
    const r = newAppNotices(apps, await getState<string[]>("apps_known"));
    notices.push(...r.notices);
    await setState("apps_known", r.ids);
  });
  // Deploys van beide sites (GitHub Actions)
  for (const [e, repo] of [["lrvdlinden", "LRvdLinden/app.lrvdlinden"], ["pixelforges", "LRvdLinden/pixelforges"]] as const) {
    await step(`deploy_${e}`, async () => {
      const d = await getJSON(`https://api.github.com/repos/${repo}/actions/runs?per_page=10`, true) as { workflow_runs?: unknown };
      const r = deployNotices(e, d.workflow_runs, await getState<number>(`deploy_${e}`));
      notices.push(...r.notices);
      if (r.newest !== null) await setState(`deploy_${e}`, r.newest);
    });
  }
  // PixelForges: wijziging van content.json (commit vanuit beheer)
  await step("content", async () => {
    const c = await getJSON("https://api.github.com/repos/LRvdLinden/pixelforges/commits?path=site/content.json&per_page=1", true);
    const r = contentNotice(c, await getState<string>("pf_content_sha"));
    if (r.notice) notices.push(r.notice);
    if (r.sha) await setState("pf_content_sha", r.sha);
  });
  // Tunr: perskit-downloads (direct) en elke dag om 20:00 het aantal nieuwe installaties van die dag
  await step("presskit", async () => {
    const last = await getState<number>("presskit_last");
    const { data, error } = await db.from("presskit_downloads").select("id, version").gt("id", last ?? 0).order("id").limit(50);
    if (error) throw new Error(error.code ?? "db");
    const rows = (data ?? []) as { id: number; version: string }[];
    if (last !== null) { const n = presskitNotice(last, rows); if (n) notices.push(n); }
    if (rows.length) await setState("presskit_last", rows[rows.length - 1].id);
    else if (last === null) {
      const { data: m } = await db.from("presskit_downloads").select("id").order("id", { ascending: false }).limit(1);
      await setState("presskit_last", Number(m?.[0]?.id ?? 0));
    }
  });
  await step("installs", async () => {
    const { day, hour } = amsterdam(new Date());
    if (hour < 20 || (await getState<string>("installs_day")) === day) return;
    const since = new Date(Date.now() - 24 * 3600_000).toISOString();
    const { data, error } = await db.from("installs").select("platform").gte("first_seen", since).limit(5000);
    if (error) throw new Error(error.code ?? "db");
    const by: Record<string, number> = {};
    for (const r of (data ?? []) as { platform: string }[]) by[r.platform] = (by[r.platform] ?? 0) + 1;
    const n = installsNotice(day, (data ?? []).length, by);
    if (n) notices.push(n);
    await setState("installs_day", day);
  });

  // Bekendr: downloads (elk uur)
  await step("bekendr", async () => {
    const { day, hour } = amsterdam(new Date());
    const stamp = `${day}T${hour}`;
    if (!forceBekendr && (await getState<string>("bekendr_hour")) === stamp) return;
    await setState("bekendr_hour", stamp);
    await bekendrSync(day);
  });

  const res = await deliver(notices);
  if (errors.length) console.error("lrbeheer", "cron", errors.join("; "));
  const bekendr = errors.find((e) => e.startsWith("bekendr:"))?.slice(9).trim() ?? "ok";
  return { notices: notices.length, ...res, errors: errors.length, bekendr };
}

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin");
  const web = origin === BEKENDR_ORIGIN;
  if (req.method === "OPTIONS") return web ? new Response(null, { status: 204, headers: bekendrCors }) : json({ error: "forbidden" }, 403);
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  // geen browsers, behalve het web-beheer van Bekendr voor de bekendr_*-acties; de app en de cron sturen geen Origin
  if (origin && !web) return json({ error: "forbidden" }, 403);
  let body: Record<string, unknown>;
  try {
    const t = await req.text();
    if (t.length > 8192) return json({ error: "too_large" }, 413);
    const b = JSON.parse(t || "{}");
    if (!b || typeof b !== "object" || Array.isArray(b)) return json({ error: "bad_json" }, 400);
    body = b;
  } catch { return json({ error: "bad_json" }, 400); }
  const action = typeof body.action === "string" ? body.action : "";
  if (web && !action.startsWith("bekendr_")) return json({ error: "forbidden" }, 403);
  const cors = web ? bekendrCors : {};

  try {
    if (action === "bekendr_login") {
      const user = typeof body.user === "string" ? body.user.trim() : "";
      const pass = typeof body.password === "string" ? body.password : "";
      const secret = await bekendrSecret();
      const okUser = await sameSecret(user, env("BEHEER_APP_USER"));
      const okPass = await sameSecret(pass, env("BEHEER_APP_PASSWORD"));
      if (!secret || !okUser || !okPass) {
        await new Promise((r) => setTimeout(r, 700));
        return json({ error: secret ? "unauthorized" : "not_configured" }, secret ? 401 : 503, cors);
      }
      return json({ ok: true, ...(await makeBekendrToken(secret)) }, 200, cors);
    }
    if (action === "bekendr_feedback") {
      if (web) return json({ error: "forbidden" }, 403, cors);
      const f = cleanFeedback(body);
      if (typeof f === "string") return json({ error: f }, 400);
      const device_hash = [...await hmac(await bekendrSecret() || "bekendr", `device|${f.device}`)].slice(0, 16).map((b) => b.toString(16).padStart(2, "0")).join("");
      const since = new Date(Date.now() - 3600_000).toISOString();
      const { count } = await db.from("lrbeheer_bekendr_feedback").select("id", { count: "exact", head: true }).eq("device_hash", device_hash).gte("at", since);
      if ((count ?? 0) >= 10) return json({ error: "too_many" }, 429);
      const { device: _d, ...rest } = f;
      const { error } = await db.from("lrbeheer_bekendr_feedback").insert({ ...rest, device_hash });
      if (error) throw new Error(error.message);
      return json({ ok: true });
    }
    if (action === "bekendr_feedback_list" || action === "bekendr_feedback_update") {
      if (!(await readBekendrToken(await bekendrSecret(), bearer(req.headers)))) return json({ error: "unauthorized" }, 401, cors);
      if (action === "bekendr_feedback_list") {
        const status = typeof body.status === "string" && (FEEDBACK_STATUS as readonly string[]).includes(body.status) ? body.status : null;
        let q = db.from("lrbeheer_bekendr_feedback")
          .select("id, at, notice_id, notice_title, notice_url, reason, message, platform, app_version, status, handled_at")
          .order("at", { ascending: false }).limit(200);
        if (status) q = q.eq("status", status);
        const { data, error } = await q;
        if (error) throw new Error(error.message);
        return json({ ok: true, items: data ?? [], open: await feedbackOpen() }, 200, cors);
      }
      const id = Number(body.id);
      if (!Number.isInteger(id) || id <= 0) return json({ error: "bad_id" }, 400, cors);
      if (body.delete === true) {
        const { error } = await db.from("lrbeheer_bekendr_feedback").delete().eq("id", id);
        if (error) throw new Error(error.message);
      } else {
        const status = String(body.status ?? "");
        if (!(FEEDBACK_STATUS as readonly string[]).includes(status)) return json({ error: "bad_status" }, 400, cors);
        const { error } = await db.from("lrbeheer_bekendr_feedback")
          .update({ status, handled_at: status === "afgehandeld" ? new Date().toISOString() : null }).eq("id", id);
        if (error) throw new Error(error.message);
      }
      return json({ ok: true, open: await feedbackOpen() }, 200, cors);
    }
    if (action === "bekendr_stats") {
      if (!(await readBekendrToken(await bekendrSecret(), bearer(req.headers)))) return json({ error: "unauthorized" }, 401, cors);
      return json(await bekendrStats(), 200, cors);
    }

    if (action === "cron") {
      if (!(await sameSecret(req.headers.get("x-lrbeheer-cron"), env("LRBEHEER_CRON_SECRET")))) return json({ error: "unauthorized" }, 401);
      return json({ ok: true, ...(await cron(body.force_bekendr === true)) });
    }
    if (action === "notify") {
      if (!(await sameSecret(req.headers.get("x-lrbeheer-secret"), env("LRBEHEER_NOTIFY_SECRET")))) return json({ error: "unauthorized" }, 401);
      const n = cleanNotify(body);
      if (typeof n === "string") return json({ error: n }, 400);
      return json({ ok: true, ...(await deliver([n])) });
    }

    if (!(await validToken(bearer(req.headers)))) return json({ error: "unauthorized" }, 401);
    switch (action) {
      case "register": {
        const r = cleanRegister(body);
        if (typeof r === "string") return json({ error: r }, 400);
        const { error } = await db.from("lrbeheer_devices").upsert({
          device_id: r.device_id, token: r.token, sandbox: r.sandbox, platform: r.platform, app_build: r.app_build,
          prefs: r.prefs, updated_at: new Date().toISOString(),
        });
        if (error) throw new Error(error.message);
        // hetzelfde token bij een ander device_id (app opnieuw geïnstalleerd) weghalen
        await db.from("lrbeheer_devices").delete().eq("token", r.token).neq("device_id", r.device_id);
        return json({ ok: true, prefs: r.prefs });
      }
      case "prefs": {
        const id = typeof body.device_id === "string" ? body.device_id : "";
        const { data, error } = await db.from("lrbeheer_devices").update({ prefs: cleanPrefs(body.prefs), updated_at: new Date().toISOString() }).eq("device_id", id).select("device_id");
        if (error) throw new Error(error.message);
        return data?.length ? json({ ok: true }) : json({ error: "not_registered" }, 404);
      }
      case "unregister": {
        await db.from("lrbeheer_devices").delete().eq("device_id", String(body.device_id ?? ""));
        return json({ ok: true });
      }
      case "test": {
        const { data } = await db.from("lrbeheer_devices").select("token, sandbox").eq("device_id", String(body.device_id ?? "")).maybeSingle();
        if (!data) return json({ error: "not_registered" }, 404);
        const r = await apnsSend(data.token, data.sandbox, payload({
          env: "lrvdlinden", kind: "store", key: "test", title: "LRbeheer", body: "Testmelding: pushmeldingen werken.", url: "lrbeheer://lrvdlinden",
        }));
        return r.ok ? json({ ok: true }) : json({ error: r.error }, 502);
      }
      case "history": {
        const { data, error } = await db.from("lrbeheer_events").select("at, env, kind, title, body, sent").order("at", { ascending: false }).limit(50);
        if (error) throw new Error(error.message);
        return json({ ok: true, events: data ?? [] });
      }
      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (e) {
    console.error("lrbeheer", action, e instanceof Error ? e.name : "fout");
    return json({ error: "server_error" }, 500, cors);
  }
});
