-- Plant Guard: Supabase schema (v2: live status + Realtime for the Flutter app)
-- Paste all of this into Supabase > SQL Editor > New query, then click Run.
-- Safe to run more than once, and safe to run on a project that has the v1 schema.

-- 1. Tables ---------------------------------------------------------------

-- History: one row every 5 minutes, plus one straight after anything changes.
create table if not exists public.readings (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  device_id     text        not null,
  temp_c        real,
  humidity      real,
  soil_pct      smallint,
  soil_raw      smallint,
  water_ok      boolean,
  water_raw     smallint,
  pump_on       boolean,
  auto_enabled  boolean,
  fault         boolean
);

create index if not exists readings_device_time
  on public.readings (device_id, created_at desc);

-- Event log: boot, low_water, refilled, watering_done, fault, manual_shot, ...
create table if not exists public.events (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  device_id   text        not null,
  type        text        not null,
  message     text
);

create index if not exists events_device_time
  on public.events (device_id, created_at desc);

-- What you control from the app. The ESP32 reads it every 5 s.
create table if not exists public.device_settings (
  device_id       text primary key,
  auto_enabled    boolean     not null default true,
  water_now_at    timestamptz,               -- app sets this to now() to ask for one shot
  clear_fault_at  timestamptz,               -- app sets this to now() to clear a fault
  updated_at      timestamptz not null default now()
);

alter table public.device_settings
  add column if not exists clear_fault_at timestamptz;

insert into public.device_settings (device_id)
values ('plant-guard-1')
on conflict (device_id) do nothing;

-- Use the server's clock, not the phone's, for command times. The ESP32
-- ignores a Water now older than 60 s, so a wrong phone clock would break it.
create or replace function public.device_settings_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if new.water_now_at is distinct from old.water_now_at and new.water_now_at is not null then
    new.water_now_at := now();
  end if;
  if new.clear_fault_at is distinct from old.clear_fault_at and new.clear_fault_at is not null then
    new.clear_fault_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists device_settings_stamp on public.device_settings;
create trigger device_settings_stamp
  before update on public.device_settings
  for each row execute function public.device_settings_stamp();

-- Live state: one row per device, overwritten every 5 s by heartbeat().
-- The app treats the device as offline when updated_at is older than ~60 s.
create table if not exists public.device_status (
  device_id     text primary key,
  updated_at    timestamptz not null default now(),
  temp_c        real,
  humidity      real,
  soil_pct      smallint,
  soil_raw      smallint,
  water_ok      boolean,
  water_raw     smallint,
  pump_on       boolean,
  auto_enabled  boolean,
  fault         boolean,
  rssi          smallint,
  uptime_s      integer,
  fw            text
);

-- 2. heartbeat(): the ESP32's single call every 5 s -----------------------
-- Saves the live status and returns the settings in one HTTPS request.
-- Runs as the table owner, so the device needs no direct access to
-- device_status. Only devices that have a device_settings row are accepted.

create or replace function public.heartbeat(p_device_id text, p_status jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.device_settings%rowtype;
begin
  select * into s from public.device_settings where device_id = p_device_id;
  if not found then
    return null;
  end if;

  insert into public.device_status as d (
    device_id, updated_at, temp_c, humidity, soil_pct, soil_raw,
    water_ok, water_raw, pump_on, auto_enabled, fault, rssi, uptime_s, fw
  ) values (
    p_device_id,
    now(),
    (p_status->>'temp_c')::real,
    (p_status->>'humidity')::real,
    round((p_status->>'soil_pct')::numeric)::smallint,
    round((p_status->>'soil_raw')::numeric)::smallint,
    (p_status->>'water_ok')::boolean,
    round((p_status->>'water_raw')::numeric)::smallint,
    (p_status->>'pump_on')::boolean,
    (p_status->>'auto_enabled')::boolean,
    (p_status->>'fault')::boolean,
    round((p_status->>'rssi')::numeric)::smallint,
    round((p_status->>'uptime_s')::numeric)::integer,
    left(p_status->>'fw', 32)
  )
  on conflict (device_id) do update set
    updated_at   = excluded.updated_at,
    temp_c       = excluded.temp_c,
    humidity     = excluded.humidity,
    soil_pct     = excluded.soil_pct,
    soil_raw     = excluded.soil_raw,
    water_ok     = excluded.water_ok,
    water_raw    = excluded.water_raw,
    pump_on      = excluded.pump_on,
    auto_enabled = excluded.auto_enabled,
    fault        = excluded.fault,
    rssi         = excluded.rssi,
    uptime_s     = excluded.uptime_s,
    fw           = excluded.fw;

  return jsonb_build_object(
    'auto_enabled',    s.auto_enabled,
    'water_now_at',    s.water_now_at,
    'water_now_age_s', extract(epoch from now() - s.water_now_at),
    'clear_fault_at',  s.clear_fault_at
  );
end;
$$;

revoke all on function public.heartbeat(text, jsonb) from public, anon, authenticated;
grant execute on function public.heartbeat(text, jsonb) to anon;

-- History for the app's charts, averaged into buckets on the server
-- (24 h -> 5 min, 7 d -> 30 min, 30 d -> 2 h), so it never hits the
-- 1000-row API limit. Runs as the caller, so Row Level Security applies.
create or replace function public.readings_history(
  p_device_id text,
  p_since timestamptz,
  p_bucket_minutes integer
)
returns table (
  bucket     timestamptz,
  soil_pct   real,
  temp_c     real,
  humidity   real,
  water_low  boolean,
  samples    integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    date_bin(make_interval(mins => greatest(p_bucket_minutes, 1)), r.created_at, timestamptz '2000-01-01'),
    avg(r.soil_pct)::real,
    avg(r.temp_c)::real,
    avg(r.humidity)::real,
    coalesce(bool_or(not r.water_ok), false),
    count(*)::integer
  from public.readings r
  where r.device_id = p_device_id
    and r.created_at >= p_since
  group by 1
  order by 1;
$$;

revoke all on function public.readings_history(text, timestamptz, integer) from public, anon, authenticated;
grant execute on function public.readings_history(text, timestamptz, integer) to authenticated;

-- 3. Security (Row Level Security) ---------------------------------------
-- Device = publishable key (role "anon"): may add readings/events, read
--          settings, and call heartbeat(). Nothing else.
-- You    = logged in to the app (role "authenticated"): may read everything
--          and change settings.

alter table public.readings        enable row level security;
alter table public.events          enable row level security;
alter table public.device_settings enable row level security;
alter table public.device_status   enable row level security;

grant insert on public.readings, public.events to anon;
grant select on public.device_settings         to anon;
grant select on public.readings, public.events, public.device_settings, public.device_status
  to authenticated;
grant update on public.device_settings         to authenticated;

drop policy if exists "device inserts readings" on public.readings;
create policy "device inserts readings" on public.readings
  for insert to anon with check (true);

drop policy if exists "device inserts events" on public.events;
create policy "device inserts events" on public.events
  for insert to anon with check (true);

drop policy if exists "device reads settings" on public.device_settings;
create policy "device reads settings" on public.device_settings
  for select to anon using (true);

drop policy if exists "user reads readings" on public.readings;
create policy "user reads readings" on public.readings
  for select to authenticated using (true);

drop policy if exists "user reads events" on public.events;
create policy "user reads events" on public.events
  for select to authenticated using (true);

drop policy if exists "user reads settings" on public.device_settings;
create policy "user reads settings" on public.device_settings
  for select to authenticated using (true);

drop policy if exists "user updates settings" on public.device_settings;
create policy "user updates settings" on public.device_settings
  for update to authenticated using (true) with check (true);

drop policy if exists "user reads status" on public.device_status;
create policy "user reads status" on public.device_status
  for select to authenticated using (true);

-- 4. Realtime: the app is told about changes the moment they happen -------
-- (Row Level Security still applies, so only a logged-in user receives them.)

do $$
declare
  t text;
begin
  foreach t in array array['device_status', 'events', 'device_settings', 'readings'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- 5. Optional: delete readings older than 90 days, every night -----------
-- Enable the pg_cron extension first (Database > Extensions > pg_cron),
-- then run these two lines on their own:
--
-- select cron.schedule('plant-guard-trim-readings', '15 3 * * *',
--   $$delete from public.readings where created_at < now() - interval '90 days'$$);
