# Plant Guard: Supabase + Telegram Setup

Nov 21, 2026 · @Mike

## How it fits together

The ESP32 still does all the watering decisions itself. Supabase stores the readings and holds two settings you control from your phone; Telegram sends you alerts. If Wi-Fi or the internet drops, watering carries on and the alerts are sent when it reconnects.

| Part | Job | Talks to |
| --- | --- | --- |
| ESP32 | Reads sensors, waters with the safety limits, sends a reading every 5 minutes and right after anything changes | Supabase (save readings, read settings), Telegram (alerts) |
| Supabase | Database: `readings`, `events`, `device_settings` | ESP32 and the dashboard |
| Dashboard web page | Opens on your phone: latest readings, 24 h soil and temperature chart, event log, Auto switch, Water now button | Supabase, behind a login |
| Telegram bot | Pushes alerts to your phone: tank low, refilled, watering done, fault, board online | Sent by the ESP32 |

How a phone command reaches the pump: you tap **Water now** → the dashboard writes the time into `device_settings` → the ESP32 checks settings every 15 s, sees a new time, and gives one safe 3 s shot (still blocked if the tank is low). Expect up to about 15 s delay.

Who can do what: the ESP32 uses the publishable key, which can only add readings/events and read settings. Changing settings or seeing data needs you to log in to the dashboard. Anyone who finds the key can't turn your pump on.

Do the steps in order: Supabase → Telegram → firmware → dashboard → full test. About 45–60 minutes in total.

## Step 1 — Supabase (about 15 min)

You end this step with a project URL, a publishable key, three tables, and one login for the dashboard.

### 1.1 Create the project

1. Go to supabase.com, sign in (GitHub login is fine), click **New project**.
2. Name: `plant-guard`. Set a database password and save it somewhere (you won't need it day to day). Region: **Southeast Asia (Singapore)** for the lowest delay from KL.
3. Wait about 2 minutes for it to finish setting up.

### 1.2 Create the tables and security rules

1. Left sidebar → **SQL Editor** → **New query**.
2. Paste the whole SQL below and click **Run**. It should say *Success. No rows returned*. It's safe to run again if you're unsure.
3. Check: left sidebar → **Table Editor**. You should see `readings`, `events` and `device_settings`, and `device_settings` should have one row: `plant-guard-1`, auto\_enabled `true`.

```sql
-- Plant Guard: Supabase schema

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

create table if not exists public.events (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  device_id   text        not null,
  type        text        not null,
  message     text
);
create index if not exists events_device_time
  on public.events (device_id, created_at desc);

create table if not exists public.device_settings (
  device_id     text primary key,
  auto_enabled  boolean     not null default true,
  water_now_at  timestamptz,
  updated_at    timestamptz not null default now()
);
insert into public.device_settings (device_id)
values ('plant-guard-1')
on conflict (device_id) do nothing;

-- Security: device (publishable key = anon) adds data and reads settings;
-- you (logged in = authenticated) read everything and change settings.
alter table public.readings        enable row level security;
alter table public.events          enable row level security;
alter table public.device_settings enable row level security;

grant insert on public.readings, public.events to anon;
grant select on public.device_settings         to anon;
grant select on public.readings, public.events, public.device_settings to authenticated;
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
```

I ran this on a local Postgres 16 and tested it: the device role can add readings/events and read settings but can't read readings or change settings; a logged-in user can read everything and change settings.

### 1.3 Create your dashboard login

1. Left sidebar → **Authentication** → **Users** → **Add user** → **Create new user**.
2. Your email and a password. Tick **Auto Confirm User** so you don't need a confirmation email.
3. Then turn off public sign-ups so nobody else can make an account: **Authentication** → **Sign In / Providers** → switch off **Allow new users to sign up**. (Menu names move around in Supabase now and then; look for the sign-up toggle under Authentication settings.)

### 1.4 Copy your two values

Left sidebar → **Project Settings** → **API Keys** (and **Data API** for the URL). Copy:

| Value | Looks like | Used in |
| --- | --- | --- |
| Project URL | `https://abcdefgh.supabase.co` | firmware and dashboard |
| Publishable key | `sb_publishable_...` | firmware and dashboard |

Only ever use the **publishable** key. Never put the **secret** key (`sb_secret_...`) in the firmware or the web page: it bypasses all the security rules above. If your project only shows legacy keys, click **Create new API keys** to get a publishable one; the legacy `anon` key would also work.

The firmware sends the key in an `apikey` header only. Supabase's newer keys aren't JWTs, so they can't go in the `Authorization: Bearer` header ([Supabase changelog](https://supabase.com/changelog/29260-upcoming-changes-to-supabase-api-keys)).

## Step 2 — Telegram bot (about 5 min)

You end this step with a bot token and your chat ID. The ESP32 only sends messages to the bot; you don't need any extra library.

1. In Telegram, search for **@BotFather** (blue tick) and press Start.
2. Send `/newbot`. Give it a display name (e.g. `Plant Guard`) and a username that ends in `bot` (e.g. `mike_plantguard_bot`).
3. BotFather replies with a **token** like `7123456789:AAH...`. Copy it. Treat it like a password: anyone with it can send messages as your bot.
4. Search for **@userinfobot**, press Start. It replies with your **Id**, a number like `123456789`. That's your chat ID.
5. Open your new bot (BotFather gives you the link `t.me/<username>`) and press **Start**. A bot can't message you until you've done this.

Quick test before touching the ESP32: paste this into your PC browser with your values filled in, and press Enter. You should get "test" on your phone.

```
https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<CHAT_ID>&text=test
```

If it says `chat not found`, you skipped point 5 or the chat ID is wrong.

## Step 3 — Firmware (about 10 min)

The firmware file is **PlantGuard.ino** (Supabase + Telegram version), sent in the chat. Sensor reading, watering logic and failsafes are the same as before; the Blynk parts are replaced. Your relay setting and calibration (soil 2440 / 1060, water 600) are already filled in.

### 3.1 Libraries

Arduino IDE → **Tools → Manage Libraries**, install:

- **ArduinoJson** by Benoit Blanchon, version 7.x
- **DHT sensor library** by Adafruit (already installed)

You can uninstall Blynk; it's no longer used. WiFi, HTTPClient and WiFiClientSecure come with the ESP32 board package.

### 3.2 Fill in the top of the file

| Line | Put in |
| --- | --- |
| `WIFI_SSID`, `WIFI_PASS` | Your Wi-Fi (2.4 GHz) |
| `SUPABASE_URL` | Project URL from step 1.4, no `/` at the end |
| `SUPABASE_KEY` | Publishable key from step 1.4 |
| `DEVICE_ID` | Leave as `plant-guard-1` (matches the row in `device_settings`) |
| `TG_BOT_TOKEN` | Bot token from step 2 |
| `TG_CHAT_ID` | Your chat ID from step 2 |

Save it in a folder called `PlantGuard` (Arduino needs the folder and file names to match).

### 3.3 Upload and check the Serial Monitor

Pump and water strip in the same cup of water, soil sensor in air. Upload, open Serial Monitor at 115200, press EN. Within about 30 seconds you should see:

```
Plant Guard starting (Supabase + Telegram)
EVENT boot: Online. Soil 0%, tank OK.
soil raw=2438 (0%) | water raw=1702 OK | T=29.4C RH=66.1% | pump=0 auto=1 fault=0 | wifi=1
Reading saved
```

...and a Telegram message: **"Plant Guard: Online. Soil 0%, tank OK."** In Supabase → Table Editor → `readings`, a new row appears.

With the soil sensor in air (0%), it starts a watering cycle: first shot about 60 s after boot, then one shot every 60 s. After 8 shots it stops with a fault message on Telegram. That's the failsafe working; it's what would happen if the sensor got pulled out of the pot.

### 3.4 How it behaves

- Readings go up every 5 minutes, plus straight after anything changes (pump stops, tank goes low, Auto switched), at most every 10 s.
- It checks the dashboard settings every 15 s.
- It never talks to the internet while the pump is running, so a slow connection can't stretch a 3 s shot.
- If Wi-Fi is down, watering still runs and up to 8 events wait in memory until it reconnects.
- After a reboot it ignores any old Water now request, so a restart never triggers a surprise shot.
- HTTPS is encrypted but uses `setInsecure()`, so it doesn't check Supabase's certificate. Fine for a home project; for a hardened version you'd add the root certificate.

## Step 4 — Phone dashboard (about 15 min)

The dashboard is one file, **index.html**, sent in the chat. It shows soil %, tank, temperature and humidity, an online/offline dot, a 24-hour chart (soil, temperature, and blue marks when the pump ran), the last 15 events, the Auto switch and the Water now button. It refreshes every 30 s.

### 4.1 Fill in and test on your PC

1. Open `index.html` in a text editor (VS Code or Notepad). Near the top of the `<script>` part, fill in `SUPABASE_URL` and `SUPABASE_KEY` (same values as the firmware). Leave `DEVICE_ID` as `plant-guard-1`.
2. Double-click the file to open it in Chrome. Log in with the email and password from step 1.3.
3. You should see the latest reading and the online dot. Try the Auto switch: within about 15 s the Serial Monitor shows the change, and the event appears.

### 4.2 Put it online with GitHub Pages (free)

This gives you a link you can open on your phone from anywhere, and the repo doubles as your portfolio piece.

1. On github.com (your personal account), click **New repository**. Name: `plant-guard`. Public. Tick **Add a README**.
2. In the repo: **Add file → Upload files**, drag in `index.html`, click **Commit changes**.
3. **Settings → Pages**. Under *Build and deployment*: Source **Deploy from a branch**, Branch **main**, folder **/(root)**, **Save**.
4. Wait 1–2 minutes. The page lives at `https://<your-username>.github.io/plant-guard/`.

Is it safe to put the key in a public repo? Yes: the publishable key is meant to be public, and the security rules from step 1.2 mean it can only add readings and read settings. Seeing data or pressing buttons needs your login. Never commit the **secret** key or the **Telegram token** (the token is only in the firmware, which you don't need to upload, or upload with the token blanked out).

### 4.3 Add it to your phone's home screen

- **Android (Chrome):** open the link → ⋮ menu → **Add to Home screen**.
- **iPhone (Safari):** open the link → Share → **Add to Home Screen**.

It then opens like an app. You stay logged in until you tap Log out.

## Step 5 — Full test and common problems

Tick these off with the pump and water strip in a cup over the sink.

- [ ] Telegram "Online" message arrives after power-up
- [ ] Dashboard shows the dot as Online and the latest values
- [ ] Pump stays off at power-up
- [ ] Water now on the dashboard → one 3 s shot within about 15 s, `manual_shot` in events
- [ ] Strip out of the water → Telegram "Tank is low", dashboard tank shows LOW, Water now gives "blocked" instead of running
- [ ] Strip back in → Telegram "Tank refilled"
- [ ] Soil sensor in air with Auto on → a shot every 60 s, then after 8 shots a fault message on Telegram and the dashboard
- [ ] Switch Auto off and on on the dashboard → fault clears
- [ ] Soil sensor into a glass of water mid-cycle → "Watering done" on Telegram
- [ ] Turn your router or hotspot off for a few minutes → watering still works; dashboard dot goes Offline after 11 min; queued events arrive when Wi-Fi is back

### Common problems

| Serial Monitor / symptom | Likely cause | Fix |
| --- | --- | --- |
| `wifi=0` the whole time | Wrong Wi-Fi name/password, or 5 GHz network | Use a 2.4 GHz network; check spelling and capitals |
| `Supabase insert readings failed: 401` | Wrong key, or the secret key used | Paste the **publishable** key exactly |
| `failed: 404` | Wrong URL, or tables not created | URL with no trailing `/`; rerun the SQL from step 1.2 |
| `failed: 401` with `permission denied` / `42501` | Security rules or grants missing | Rerun the SQL from step 1.2 |
| `failed: -1` or other negative number | No internet, or HTTPS couldn't connect | Check the router; it retries by itself |
| `Settings: no row for this device_id` | `device_settings` row missing or DEVICE\_ID changed | Rerun the SQL, or make `DEVICE_ID` match the row |
| `Telegram failed: 400 ... chat not found` | You didn't press Start on your bot, or wrong chat ID | Open the bot, press Start; recheck the ID |
| `Telegram failed: 401` | Wrong bot token | Copy it again from BotFather |
| Dashboard says "Login failed" | Wrong email/password, or user not confirmed | Recreate the user in step 1.3 with Auto Confirm ticked |
| Dashboard loads but shows nothing / "Couldn't load data" | Wrong URL or key in index.html | Same values as the firmware |
| Dashboard dot Offline while the board runs | No readings saved | Check the Serial Monitor for insert errors |

Storage: one reading every 5 minutes is about 290 rows a day, roughly 100,000 a year: tiny for Supabase's free tier. If you want to trim later, delete readings older than 90 days from the SQL Editor.

Note that Supabase pauses free projects after a period of inactivity; since the ESP32 writes every 5 minutes, this project stays active. If it ever gets paused, restore it from the Supabase dashboard.
