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

-- Bekendr: downloads per dag (Apple per apparaat uit App Store Connect, Android uit GitHub Releases)
create table if not exists public.lrbeheer_bekendr_daily (
  day date not null,
  source text not null check (source in ('apple','android')),
  device text not null,
  kind text not null default 'download' check (kind in ('download','redownload','update')),
  units int not null default 0,
  primary key (day, source, device, kind)
);

alter table public.lrbeheer_devices enable row level security;
alter table public.lrbeheer_state enable row level security;
alter table public.lrbeheer_events enable row level security;
alter table public.lrbeheer_bekendr_daily enable row level security;
-- geen policies: alleen de functie (service role) leest en schrijft
revoke all on table public.lrbeheer_devices, public.lrbeheer_state, public.lrbeheer_events, public.lrbeheer_bekendr_daily from anon, authenticated;

-- Geschiedenis 90 dagen bewaren
create or replace function public.lrbeheer_cleanup() returns void language sql security definer as $$
  delete from public.lrbeheer_events where at < now() - interval '90 days';
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
