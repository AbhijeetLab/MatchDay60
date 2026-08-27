-- =====================================================================
-- Pickup Football Lineup — Supabase setup
-- Run this once in Supabase Dashboard → SQL Editor → New query → Run.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. LINEUPS
-- One row per match, keyed by the app's shareable Lineup ID.
-- Holds match details (from the setup screen), the roster + team split +
-- pitch layout (from the Match Day screen), team names/formations, and
-- the final result (score + Man of the Match) once the game is rated.
-- ---------------------------------------------------------------------
create table if not exists public.lineups (
  id            text primary key,                          -- matchMeta.id
  title         text default '',
  match_date    date,
  match_time    time,
  location      text default '',
  format_tag    text default '',                            -- e.g. "5v5"
  top_n         integer default 3,
  flying_gk     jsonb default '{"A":false,"B":false}'::jsonb,
  roster        jsonb default '[]'::jsonb,                  -- array of player objects
  player_team   jsonb default '{}'::jsonb,                  -- { "<playerId>": "A" | "B" }
  captains      jsonb default '{"A":null,"B":null}'::jsonb,
  formation     jsonb default '{"A":"balanced","B":"balanced"}'::jsonb,
  manual_pos    jsonb default '{}'::jsonb,                  -- drag-pinned pitch spots
  name_a        text default 'Black',
  name_b        text default 'White',
  score_a       integer,
  score_b       integer,
  mvp_player_id integer,
  mvp_avg       numeric(4,2),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.lineups is 'One row per created lineup/match, from the setup screen through full time.';

-- ---------------------------------------------------------------------
-- 2. RATINGS
-- One row per submitted rating response (append-only). Never overwritten,
-- so two teammates rating at the same moment on different phones can never
-- clobber each other. Man of the Match / per-player stats are computed
-- client-side by aggregating every row for a lineup_id.
-- ---------------------------------------------------------------------
create table if not exists public.ratings (
  id           bigint generated always as identity primary key,
  lineup_id    text not null references public.lineups(id) on delete cascade,
  rater_name   text default 'A teammate',
  ratings      jsonb not null default '{}'::jsonb,          -- { "<playerId>": 7.5 }
  stats        jsonb not null default '{}'::jsonb,          -- { "<playerId>": {goals,assists,saves} }
  mvp_nominee  integer,
  created_at   timestamptz not null default now()
);

create index if not exists ratings_lineup_id_idx on public.ratings (lineup_id);

comment on table public.ratings is 'Append-only player ratings/stats submissions for a lineup.';

-- ---------------------------------------------------------------------
-- 3. Keep updated_at current automatically
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_lineups_updated_at on public.lineups;
create trigger trg_lineups_updated_at
before update on public.lineups
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- 4. Row Level Security
-- This app has no login — the Lineup ID itself is the "shared link"
-- (same trust model as before, when state lived in a shared key/value
-- store). RLS is enabled with permissive policies so the anon/public key
-- can read and write. If you later add real authentication, tighten
-- these policies (e.g. restrict updates to rows the user created).
-- ---------------------------------------------------------------------
alter table public.lineups enable row level security;
alter table public.ratings enable row level security;

drop policy if exists "lineups_select" on public.lineups;
create policy "lineups_select" on public.lineups for select using (true);

drop policy if exists "lineups_insert" on public.lineups;
create policy "lineups_insert" on public.lineups for insert with check (true);

drop policy if exists "lineups_update" on public.lineups;
create policy "lineups_update" on public.lineups for update using (true) with check (true);

drop policy if exists "ratings_select" on public.ratings;
create policy "ratings_select" on public.ratings for select using (true);

drop policy if exists "ratings_insert" on public.ratings;
create policy "ratings_insert" on public.ratings for insert with check (true);

-- ---------------------------------------------------------------------
-- 5. Realtime
-- Adds both tables to Supabase's realtime publication so the app can
-- subscribe to live INSERT/UPDATE events (instant cross-device sync,
-- no polling / no page refresh needed).
-- If a table is already in the publication this will error harmlessly —
-- safe to ignore ("already member of publication").
-- ---------------------------------------------------------------------
alter publication supabase_realtime add table public.lineups;
alter publication supabase_realtime add table public.ratings;

-- =====================================================================
-- Done. Next steps:
-- 1. Project Settings → API → copy your Project URL and anon public key.
-- 2. Paste them into SUPABASE_URL / SUPABASE_ANON_KEY near the top of
--    the <script> block in the HTML file.
-- 3. Open the page — the "Live" dot next to the status pill confirms
--    the connection.
-- =====================================================================
