// Functie lrbeheer: centraal pushsysteem van de app LRbeheer (LRvdLinden, PixelForges en Tunr).
// Deploy in het Supabase-project van Tunr (zie beheer/server/README.md). Verandert niets aan de functie `admin`,
// aan de sites of aan bestaande tabellen; voegt alleen de tabellen lrbeheer_* toe (schema.sql).
//
// POST /functions/v1/lrbeheer
//   App (Authorization: Bearer <Tunr-beheertoken>):  {action: register|unregister|test|history, ...}
//   Cron (x-lrbeheer-cron: LRBEHEER_CRON_SECRET):   {action: "cron"}   — pg_cron elke 5 minuten
//   Haak (x-lrbeheer-secret: LRBEHEER_NOTIFY_SECRET): {action: "notify", env, kind, title, body?, url?}
//
// Function-secrets: TUNR_TOKEN_SECRET (bestaat al, van `admin`), APNS_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID (dezelfde
// APNs-sleutel als Bingr/Pasr), LRBEHEER_APNS_TOPIC (optioneel, standaard app.lrvdlinden.lrbeheer),
// LRBEHEER_CRON_SECRET, LRBEHEER_NOTIFY_SECRET (optioneel), GITHUB_TOKEN (optioneel, alleen lezen van openbare repo's).
// Nooit tokens, sleutels of apparaat-id's loggen.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  amsterdam, apnsHost, apnsJwt, apnsResult, bearer, cleanNotify, cleanPrefs, cleanRegister, contentNotice, deployNotices,
  hmac, importApnsKey, installsNotice, newAppNotices, type Notice, payload, presskitNotice, readTunrToken, sameBytes,
  storeNotices, wants,
} from "./logic.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
/** APNs-sleutel: namen van Bingr/Pasr (APNS_*) of de centrale namen uit app.lrvdlinden.secrets (APN_*, TEAM_ID). */
const apnsKey = () => env("APNS_KEY_P8") || env("APN_P8_CERT");
const apnsKeyId = () => env("APNS_KEY_ID") || env("APN_KEY_ID");
const apnsTeam = () => env("APNS_TEAM_ID") || env("TEAM_ID") || "EU3UY476T6";
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { autoRefreshToken: false, persistSession: false } });

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

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

async function cron() {
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

  const res = await deliver(notices);
  if (errors.length) console.error("lrbeheer", "cron", errors.join("; "));
  return { notices: notices.length, ...res, errors: errors.length };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  // geen browsers: de app en de cron sturen geen Origin
  if (req.headers.get("Origin")) return json({ error: "forbidden" }, 403);
  let body: Record<string, unknown>;
  try {
    const t = await req.text();
    if (t.length > 8192) return json({ error: "too_large" }, 413);
    const b = JSON.parse(t || "{}");
    if (!b || typeof b !== "object" || Array.isArray(b)) return json({ error: "bad_json" }, 400);
    body = b;
  } catch { return json({ error: "bad_json" }, 400); }
  const action = typeof body.action === "string" ? body.action : "";

  try {
    if (action === "cron") {
      if (!(await sameSecret(req.headers.get("x-lrbeheer-cron"), env("LRBEHEER_CRON_SECRET")))) return json({ error: "unauthorized" }, 401);
      return json({ ok: true, ...(await cron()) });
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
    return json({ error: "server_error" }, 500);
  }
});
