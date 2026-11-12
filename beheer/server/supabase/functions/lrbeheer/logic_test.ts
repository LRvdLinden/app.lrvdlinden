// deno test supabase/functions/lrbeheer/logic_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  apnsResult, b64u, cleanNotify, cleanPrefs, cleanRegister, contentNotice, defaultPrefs, deployNotices, hmac, installsNotice,
  newAppNotices, payload, readTunrToken, storeNotices, wants,
} from "./logic.ts";

const enc = new TextEncoder();
async function tunrToken(secret: string, v: number, e: number) {
  const p = b64u(enc.encode(JSON.stringify({ v, e, s: "admin" })));
  return `${p}.${b64u(await hmac(secret, p))}`;
}

Deno.test("Tunr-token: geldig, verlopen, verkeerde sleutel", async () => {
  const now = Date.now(), e = Math.floor(now / 1000) + 3600;
  const t = await tunrToken("geheim", 3, e);
  assertEquals(await readTunrToken("geheim", t, now), { v: 3, e });
  assertEquals(await readTunrToken("anders", t, now), null);
  assertEquals(await readTunrToken("geheim", t, (e + 1) * 1000), null);
  assertEquals(await readTunrToken("geheim", "x.y", now), null);
});

Deno.test("prefs: onbekend weg, ontbrekend aan", () => {
  const p = cleanPrefs({ lrvdlinden: { store: false, x: true }, foo: {} });
  assertEquals(p.lrvdlinden, { store: false, deploy: true });
  assertEquals(p.tunr, defaultPrefs().tunr);
  assert(!wants({ lrvdlinden: { store: false } }, "lrvdlinden", "store"));
  assert(wants({}, "pixelforges", "contact"));
});

Deno.test("register: controle", () => {
  const ok = cleanRegister({ device_id: "ABCDEFGH-1234", apns_token: "A".repeat(64), platform: "ios", sandbox: true, app_build: 1 });
  assert(typeof ok !== "string");
  if (typeof ok !== "string") assertEquals(ok.token, "a".repeat(64));
  assertEquals(cleanRegister({ device_id: "x", apns_token: "a".repeat(64), platform: "ios" }), "bad_device_id");
  assertEquals(cleanRegister({ device_id: "ABCDEFGH", apns_token: "zz", platform: "ios" }), "bad_apns_token");
  assertEquals(cleanRegister({ device_id: "ABCDEFGH", apns_token: "a".repeat(64), platform: "android" }), "bad_platform");
});

Deno.test("store-check: eerste keer niets, daarna alleen nieuwe runs met wijzigingen", () => {
  const book = { runs: [
    { id: "3", time: "2026-11-05T20:46:55+00:00", mode: "nieuw", changed: false, lines: [] },
    { id: "2", time: "2026-11-05T20:46:08+00:00", mode: "bijwerken", changed: true, lines: ["Weekdot: versie 1.0.3"] },
    { id: "1", time: "2026-11-04T08:00:00+00:00", mode: "alles", changed: true, lines: ["Oud"] },
  ] };
  assertEquals(storeNotices(book, null), { notices: [], newest: "3" });
  const r = storeNotices(book, "1");
  assertEquals(r.notices.length, 1);
  assertEquals(r.notices[0].body, "Weekdot: versie 1.0.3");
  assertEquals(r.notices[0].env, "lrvdlinden");
  assertEquals(storeNotices(book, "3").notices.length, 0);
});

Deno.test("nieuwe apps", () => {
  const apps = { apps: [{ id: "a", name: "A" }, { id: "b", name: "B" }] };
  assertEquals(newAppNotices(apps, null).notices.length, 0);
  const r = newAppNotices(apps, ["a"]);
  assertEquals(r.notices.map((n) => n.body), ["B"]);
  assertEquals(r.ids, ["a", "b"]);
});

Deno.test("deploys: alleen afgeronde release-runs na de vorige", () => {
  const runs = [
    { id: 12, name: "Release site", status: "completed", conclusion: "failure", display_title: "Beheer: X bijgewerkt" },
    { id: 11, name: "Release site", status: "completed", conclusion: "success", display_title: "ok" },
    { id: 13, name: "Store-check", status: "completed", conclusion: "success" },
    { id: 14, name: "Release site", status: "in_progress" },
  ];
  assertEquals(deployNotices("pixelforges", runs, null).notices.length, 0);
  const r = deployNotices("pixelforges", runs, 10);
  assertEquals(r.notices.map((n) => n.title), ["pixelforges.nl is bijgewerkt", "Deploy van pixelforges.nl mislukt"]);
  assertEquals(r.newest, 13);
});

Deno.test("content.json-commit", () => {
  const c = [{ sha: "abc", commit: { message: "Bijgewerkt via beheer\n\nmeer" } }];
  assertEquals(contentNotice(c, null).notice, null);
  assertEquals(contentNotice(c, "abc").notice, null);
  assertEquals(contentNotice(c, "old").notice?.body, "Bijgewerkt via beheer");
});

Deno.test("installaties en payload", () => {
  assertEquals(installsNotice("2026-11-06", 0, {}), null);
  const n = installsNotice("2026-11-06", 3, { ios: 2, android: 1 })!;
  assertEquals(n.title, "Tunr: 3 nieuwe installaties");
  const p = payload(n);
  assertEquals(p.lrenv, "tunr");
  assertEquals(p.aps["thread-id"], "tunr");
});

Deno.test("notify en APNs-uitkomst", () => {
  assertEquals(cleanNotify({ env: "x", kind: "deploy", title: "t" }), "bad_env");
  assertEquals(cleanNotify({ env: "pixelforges", kind: "x", title: "t" }), "bad_kind");
  const n = cleanNotify({ env: "pixelforges", kind: "contact", title: "Nieuwe aanvraag", url: "javascript:alert(1)" });
  assert(typeof n !== "string" && n.url === "lrbeheer://pixelforges");
  assertEquals(apnsResult(200, ""), { ok: true });
  assertEquals(apnsResult(400, "DeviceTokenNotForTopic"), { ok: false, invalid: false, error: "apns_DeviceTokenNotForTopic" });
  assertEquals(apnsResult(410, "Unregistered"), { ok: false, invalid: true, error: "apns_Unregistered" });
});

// ---- Bekendr ----
import {
  androidStep, apkReleases, appleDaysToFetch, bekendrSummary, makeBekendrToken, parseSalesReport, readBekendrToken, salesDevice, salesKind,
} from "./logic.ts";

Deno.test("Bekendr-token: geldig, verlopen, verkeerde sleutel", async () => {
  const now = Date.now();
  const { token, expires } = await makeBekendrToken("geheim", now);
  assert(expires > now / 1000);
  assertEquals(await readBekendrToken("geheim", token, now), true);
  assertEquals(await readBekendrToken("anders", token, now), false);
  assertEquals(await readBekendrToken("geheim", token, (expires + 1) * 1000), false);
  assertEquals(await readBekendrToken("", token, now), false);
  assertEquals(await readBekendrToken("geheim", "x.y", now), false);
});

Deno.test("Verkoopoverzicht: soorten en apparaten", () => {
  assertEquals(salesKind("1F"), "download");
  assertEquals(salesKind("F1"), "download");
  assertEquals(salesKind("3T"), "redownload");
  assertEquals(salesKind("7"), "update");
  assertEquals(salesKind("IA1"), null);
  assertEquals(salesDevice("Desktop", "F1"), "Mac");
  assertEquals(salesDevice("iPad", "1F"), "iPad");
  assertEquals(salesDevice("iPod touch", "1"), "iPhone");
});

Deno.test("Verkoopoverzicht: alleen Bekendr, opgeteld per apparaat", () => {
  const head = ["Provider", "SKU", "Title", "Product Type Identifier", "Units", "Apple Identifier", "Device", "Parent Identifier"].join("\t");
  const row = (title: string, type: string, units: string, device: string, parent = "") =>
    ["APPLE", "sku", title, type, units, "123", device, parent].join("\t");
  const tsv = [head, row("Bekendr", "1F", "3", "iPhone"), row("Bekendr", "1F", "2", "iPhone"), row("Bekendr", "1F", "1", "iPad"),
    row("Bekendr", "F1", "4", "Desktop"), row("Bekendr", "7F", "5", "iPhone"), row("Andere app", "1F", "9", "iPhone"),
    row("Bekendr", "IA1", "1", "iPhone", "parent")].join("\n");
  const rows = parseSalesReport(tsv, { title: "Bekendr" });
  const get = (d: string, k: string) => rows.find((r) => r.device === d && r.kind === k)?.units ?? 0;
  assertEquals(get("iPhone", "download"), 5);
  assertEquals(get("iPad", "download"), 1);
  assertEquals(get("Mac", "download"), 4);
  assertEquals(get("iPhone", "update"), 5);
  assertEquals(rows.length, 4);
  assertEquals(parseSalesReport(tsv, { appleId: "999" }).length, 0);
});

Deno.test("Android: releases en dagteller", () => {
  const r = apkReleases([
    { tag_name: "android-1.0.0-build7", published_at: "2026-11-09T10:00:00Z", assets: [{ name: "Bekendr.apk", download_count: 4 }, { name: "Bekendr-1.0.0-build7.apk", download_count: 2 }, { name: "notes.txt", download_count: 9 }] },
    { tag_name: "android-1.0.0-build4", published_at: "2026-11-08T10:00:00Z", assets: [{ name: "Bekendr-1.0.0-build4.apk", download_count: 3 }] },
    { tag_name: "v-ander", assets: [] },
  ]);
  assertEquals(r.map((x) => x.downloads), [6, 3]);
  let s = androidStep(null, "2026-11-09", 9);
  assertEquals(s.today, 0);
  s = androidStep(s.state, "2026-11-09", 12);
  assertEquals(s.today, 3);
  s = androidStep(s.state, "2026-11-10", 13);
  assertEquals(s.today, 1);
  assertEquals(s.state.base, 12);
});

Deno.test("Apple-dagen en overzicht", () => {
  assertEquals(appleDaysToFetch("2026-11-09", ["2026-11-08"], 3), ["2026-11-07", "2026-11-06"]);
  const sum = bekendrSummary([
    { day: "2026-11-08", source: "apple", device: "iPhone", kind: "download", units: 3 },
    { day: "2026-11-08", source: "apple", device: "Mac", kind: "download", units: 1 },
    { day: "2026-11-07", source: "apple", device: "iPad", kind: "update", units: 8 },
    { day: "2026-11-09", source: "android", device: "Android", kind: "download", units: 2 },
  ], "2026-11-09", 3);
  assertEquals(sum.apple.totals, { download: 4, redownload: 0, update: 8 });
  assertEquals(sum.apple.by_device, { iPhone: 3, Mac: 1 });
  assertEquals(sum.apple.last_day, "2026-11-08");
  assertEquals(sum.days.map((d) => d.day), ["2026-11-07", "2026-11-08", "2026-11-09"]);
  assertEquals(sum.days[1].iPhone, 3);
  assertEquals(sum.days[2].android, 2);
});

import { cleanFeedback } from "./logic.ts";
Deno.test("Feedback: controle", () => {
  const base = { notice_id: "gmb-2026-1", notice_title: "Dakkapel", notice_url: "https://zoek.officielebekendmakingen.nl/gmb-2026-1.html", reason: "locatie", message: "", platform: "ios", app_version: "1.0.0 (1)", device: "0F8A2C3E-1111-2222-3333-444455556666" };
  const ok = cleanFeedback(base);
  assert(typeof ok !== "string");
  assertEquals(cleanFeedback({ ...base, reason: "spam" }), "bad_reason");
  assertEquals(cleanFeedback({ ...base, reason: "anders", message: "" }), "message_required");
  assertEquals(cleanFeedback({ ...base, device: "x" }), "bad_device");
  const evil = cleanFeedback({ ...base, notice_url: "https://evil.example/x" });
  assert(typeof evil !== "string" && evil.notice_url === "");
  const plat = cleanFeedback({ ...base, platform: "windows" });
  assert(typeof plat !== "string" && plat.platform === "onbekend");
});

// ---- Noodpakket ----
import {
  androidBuilds, apkReleases as apk, cleanNpMessage, cleanNpRegister, makeScopedToken, npPayload, npTargets, readScopedToken,
} from "./logic.ts";

Deno.test("Noodpakket-token: eigen scope, niet uitwisselbaar met Bekendr", async () => {
  const now = Date.now();
  const { token, expires } = await makeScopedToken("geheim", "noodpakket", now);
  assertEquals(await readScopedToken("geheim", "noodpakket", token, now), true);
  assertEquals(await readScopedToken("geheim", "bekendr", token, now), false);
  assertEquals(await readScopedToken("geheim", "noodpakket", token, (expires + 1) * 1000), false);
  assertEquals(await readScopedToken("", "noodpakket", token, now), false);
});

Deno.test("Noodpakket-aanmelding: iPhone met token, Android zonder", () => {
  const tok = "ab".repeat(32);
  const ios = cleanNpRegister({ device_id: "ABCDEF12-3456", platform: "ios", apns_token: tok.toUpperCase(), lang: "en", app_version: "1.0.0" });
  assert(typeof ios !== "string");
  assertEquals(ios.apns_token, tok);
  assertEquals(ios.lang, "en");
  const and = cleanNpRegister({ device_id: "ABCDEF12-3456", platform: "android", apns_token: "x" });
  assert(typeof and !== "string" && and.apns_token === null && and.lang === "nl");
  assertEquals(cleanNpRegister({ device_id: "kort", platform: "ios", apns_token: tok }), "bad_device_id");
  assertEquals(cleanNpRegister({ device_id: "ABCDEF12-3456", platform: "ios", apns_token: "123" }), "bad_apns_token");
  assertEquals(cleanNpRegister({ device_id: "ABCDEF12-3456", platform: "macos" }), "bad_platform");
});

Deno.test("Noodpakket-bericht: lengtes, doelgroep en link", () => {
  assertEquals(cleanNpMessage({ title: "Hi" }), "bad_title");
  assertEquals(cleanNpMessage({ title: "Storm op komst", body: "x".repeat(401) }), "bad_body");
  assertEquals(cleanNpMessage({ title: "Storm op komst", url: "http://x.nl" }), "bad_url");
  const m = cleanNpMessage({ title: " Storm op komst ", body: "Loop je pakket na.", lang: "nl", platform: "apple", url: "https://www.knmi.nl" });
  assert(typeof m !== "string");
  assertEquals(m.title, "Storm op komst");
  assertEquals(cleanNpMessage({ title: "Storm op komst", lang: "de", platform: "pc" }), { title: "Storm op komst", body: "", lang: "all", platform: "all", url: "" });
  assert(npTargets({ lang: "nl", platform: "apple" }, { lang: "nl", platform: "ipados" }));
  assert(!npTargets({ lang: "nl", platform: "apple" }, { lang: "nl", platform: "android" }));
  assert(!npTargets({ lang: "en", platform: "all" }, { lang: "nl", platform: "android" }));
  assert(npTargets({ lang: "all", platform: "android" }, { lang: "en", platform: "android" }));
  const p = npPayload({ id: 7, title: "T", body: "B", url: "" });
  assertEquals(p.np_message, 7);
  assert(!("url" in p));
});

Deno.test("Noodpakket: APK-releases met v-tags en Android-builds", () => {
  const rel = [
    { tag_name: "v1.0.1", published_at: "2026-11-12T08:00:00Z", assets: [{ name: "noodpakket.apk", download_count: 5 }] },
    { tag_name: "v1.0.0", published_at: "2026-11-11T08:00:00Z", assets: [{ name: "noodpakket.apk", download_count: 3 }, { name: "x.txt", download_count: 9 }] },
    { tag_name: "android-1", published_at: "2026-11-10T08:00:00Z", assets: [] },
  ];
  const r = apk(rel, "v");
  assertEquals(r.map((x) => x.tag), ["v1.0.1", "v1.0.0"]);
  assertEquals(r[1].downloads, 3);
  assertEquals(apk(rel).map((x) => x.tag), ["android-1"]);
  const b = androidBuilds([
    { id: 2, name: "Android", display_title: "Build", status: "completed", conclusion: "success", created_at: "2026-11-12T08:00:00Z", html_url: "u", head_branch: "main" },
    { id: 1, name: "Website", status: "completed", conclusion: "success", created_at: "2026-11-12T09:00:00Z" },
    { id: 3, name: "Android", status: "queued", conclusion: null, created_at: "2026-11-12T10:00:00Z" },
  ]);
  assertEquals(b.map((x) => x.id), [3, 2]);
  assertEquals(b[0].conclusion, null);
});

// ---- Pairr ----
import { openIssues } from "./logic.ts";

Deno.test("Pairr-token: eigen scope", async () => {
  const now = Date.now();
  const { token } = await makeScopedToken("geheim", "pairr", now);
  assertEquals(await readScopedToken("geheim", "pairr", token, now), true);
  assertEquals(await readScopedToken("geheim", "noodpakket", token, now), false);
});

Deno.test("Pairr-meldingen: alleen open issues, geen pull requests, nieuwste eerst", () => {
  const raw = [
    { number: 1, state: "open", title: "Oud", html_url: "https://github.com/x/y/issues/1", created_at: "2026-11-01T10:00:00Z", comments: 2, labels: [{ name: "bug" }] },
    { number: 2, state: "open", title: "PR", pull_request: {}, created_at: "2026-11-05T10:00:00Z" },
    { number: 3, state: "closed", title: "Dicht", created_at: "2026-11-06T10:00:00Z" },
    { number: 4, state: "open", title: "Nieuw", html_url: "javascript:alert(1)", created_at: "2026-11-10T10:00:00Z" },
  ];
  const r = openIssues(raw);
  assertEquals(r.map((i) => i.number), [4, 1]);
  assertEquals(r[0].url, "");
  assertEquals(r[1].labels, ["bug"]);
  assertEquals(openIssues(null), []);
});
