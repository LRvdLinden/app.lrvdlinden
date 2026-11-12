-- LRbeheer: tabellen van de centrale pushfunctie `lrbeheer`, in het Supabase-project van Tunr.
-- Alleen nieuwe tabellen (prefix lrbeheer_); bestaande tabellen van Tunr blijven ongewijzigd. Idempotent.
-- Toepassen: SQL Editor van het Tunr-project, of de Management API (zoals de workflow Backend van tunr-beheer).

create table if not exists public.lrbeheer_devices (
  device_id text primary key,
  token text not null,
  sandbox boolean not null default false,
  platform text not null default 'ios' check (platform in ('ios','ipados','macos')),
  app_build int not null default 0,
  prefs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists lrbeheer_devices_token on public.lrbeheer_devices(token);

create table if not exists public.lrbeheer_state (
  key text primary key,
  value jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.lrbeheer_events (
  id bigserial primary key,
  at timestamptz not null default now(),
  env text not null,
  kind text not null,
  title text not null,
  body text not null default '',
  url text not null default '',
  sent int not null default 0
);
create index if not exists lrbeheer_events_at on public.lrbeheer_events(at);

-- Bekendr: feedback op een bekendmaking (vanuit de app; geen persoonsgegevens, apparaat alleen als hash)
create table if not exists public.lrbeheer_bekendr_feedback (
  id bigserial primary key,
  at timestamptz not null default now(),
  notice_id text not null,
  notice_title text not null default '',
  notice_url text not null default '',
  reason text not null check (reason in ('locatie','categorie','gemeente','link','anders')),
  message text not null default '',
  platform text not null default '',
  app_version text not null default '',
  device_hash text not null default '',
  status text not null default 'nieuw' check (status in ('nieuw','afgehandeld')),
  handled_at timestamptz
);
create index if not exists lrbeheer_bekendr_feedback_at on public.lrbeheer_bekendr_feedback(at);

-- Bekendr: downloads per dag (Apple per apparaat uit App Store Connect, Android uit GitHub Releases)
create table if not exists public.lrbeheer_bekendr_daily (
  day date not null,
  source text not null check (source in ('apple','android')),
  device text not null,
  kind text not null default 'download' check (kind in ('download','redownload','update')),
  units int not null default 0,
  primary key (day, source, device, kind)
);

-- Noodpakket: downloads per dag (zelfde vorm als Bekendr)
create table if not exists public.lrbeheer_noodpakket_daily (
  day date not null,
  source text not null check (source in ('apple','android')),
  device text not null,
  kind text not null default 'download' check (kind in ('download','redownload','update')),
  units int not null default 0,
  primary key (day, source, device, kind)
);

-- Pairr: downloads per dag (alleen Apple, per apparaat uit App Store Connect; zelfde vorm als Bekendr)
create table if not exists public.lrbeheer_pairr_daily (
  day date not null,
  source text not null check (source in ('apple','android')),
  device text not null,
  kind text not null default 'download' check (kind in ('download','redownload','update')),
  units int not null default 0,
  primary key (day, source, device, kind)
);

-- Omzet van betaalde apps (nu Pairr): opbrengst per dag en valuta uit de verkoopoverzichten van App Store Connect
-- (Units × Developer Proceeds, terugbetalingen negatief), met een omrekening naar euro tegen de ECB-koers van de dag
-- waarop de functie het overzicht ophaalde. Apple betaalt later definitief uit in euro; dit is een schatting.
create table if not exists public.lrbeheer_revenue (
  app text not null,
  day date not null,
  currency text not null,
  units int not null default 0,
  proceeds numeric(12,2) not null default 0,
  proceeds_eur numeric(12,2),
  primary key (app, day, currency)
);

-- Noodpakket: apparaten die berichten willen ontvangen (iPhone/iPad met APNs-token; Android haalt zelf op).
-- Alleen een willekeurig apparaatnummer, het pushtoken, de taal en de appversie; geen account of persoonsgegevens.
create table if not exists public.lrbeheer_noodpakket_devices (
  device_id text primary key,
  platform text not null check (platform in ('ios','ipados','android')),
  apns_token text,
  sandbox boolean not null default false,
  lang text not null default 'nl' check (lang in ('nl','en')),
  app_version text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index if not exists lrbeheer_noodpakket_devices_token on public.lrbeheer_noodpakket_devices(apns_token);

-- Noodpakket: berichten aan gebruikers vanuit het beheer
create table if not exists public.lrbeheer_noodpakket_messages (
  id bigserial primary key,
  at timestamptz not null default now(),
  title text not null,
  body text not null default '',
  url text not null default '',
  lang text not null default 'all' check (lang in ('all','nl','en')),
  platform text not null default 'all' check (platform in ('all','apple','android')),
  sent_apple int not null default 0,
  failed_apple int not null default 0,
  fetched_android int not null default 0,
  withdrawn boolean not null default false
);
create index if not exists lrbeheer_noodpakket_messages_at on public.lrbeheer_noodpakket_messages(at);
-- Waarom APNs een melding weigerde (bv. {"apns_BadDeviceToken": 1}), om het in het beheer te tonen
alter table public.lrbeheer_noodpakket_messages add column if not exists errors jsonb not null default '{}'::jsonb;

-- Teller "opgehaald door Android" ophogen (aangeroepen door de functie)
create or replace function public.lrbeheer_noodpakket_fetched(ids bigint[]) returns void language sql security definer as $$
  update public.lrbeheer_noodpakket_messages set fetched_android = fetched_android + 1 where id = any(ids);
$$;
revoke all on function public.lrbeheer_noodpakket_fetched(bigint[]) from public, anon, authenticated;

alter table public.lrbeheer_devices enable row level security;
alter table public.lrbeheer_state enable row level security;
alter table public.lrbeheer_events enable row level security;
alter table public.lrbeheer_bekendr_daily enable row level security;
alter table public.lrbeheer_bekendr_feedback enable row level security;
alter table public.lrbeheer_noodpakket_daily enable row level security;
alter table public.lrbeheer_noodpakket_devices enable row level security;
alter table public.lrbeheer_noodpakket_messages enable row level security;
alter table public.lrbeheer_pairr_daily enable row level security;
alter table public.lrbeheer_revenue enable row level security;
-- geen policies: alleen de functie (service role) leest en schrijft
revoke all on table public.lrbeheer_devices, public.lrbeheer_state, public.lrbeheer_events, public.lrbeheer_bekendr_daily, public.lrbeheer_bekendr_feedback,
  public.lrbeheer_noodpakket_daily, public.lrbeheer_noodpakket_devices, public.lrbeheer_noodpakket_messages, public.lrbeheer_pairr_daily,
  public.lrbeheer_revenue
  from anon, authenticated;

-- Geschiedenis 90 dagen bewaren
create or replace function public.lrbeheer_cleanup() returns void language sql security definer as $$
  delete from public.lrbeheer_events where at < now() - interval '90 days';
  -- Noodpakket: apparaten die een half jaar niets van zich lieten horen, en berichten ouder dan een jaar
  delete from public.lrbeheer_noodpakket_devices where last_seen < now() - interval '180 days';
  delete from public.lrbeheer_noodpakket_messages where at < now() - interval '365 days';
$$;

-- Cron: elke 5 minuten de functie aanroepen (pg_cron + pg_net). Vervang <PROJECT_REF> en <LRBEHEER_CRON_SECRET>
-- (zelfde waarde als het function-secret) en voer dit blok één keer uit:
--
-- select cron.schedule('lrbeheer-push', '*/5 * * * *', $$
--   select net.http_post(
--     url := 'https://<PROJECT_REF>.supabase.co/functions/v1/lrbeheer',
--     headers := jsonb_build_object('Content-Type','application/json','x-lrbeheer-cron','<LRBEHEER_CRON_SECRET>'),
--     body := '{"action":"cron"}'::jsonb);
-- $$);
-- select cron.schedule('lrbeheer-cleanup', '17 3 * * *', $$ select public.lrbeheer_cleanup(); $$);
