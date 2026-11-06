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
