/*
  Plant Guard - main firmware (Supabase + Telegram)
  -----------------------------------------------------------------
  Board   : ESP32 Dev Module (ESP32 DevKit, ESP-WROOM-32)
  Core    : esp32 by Espressif Systems, 3.x (Arduino IDE Boards Manager)
  Libraries (Arduino IDE Library Manager):
            ArduinoJson by Benoit Blanchon, 7.x
            DHT sensor library by Adafruit, 1.4.x (+ Adafruit Unified Sensor)
  Setup   : copy secrets.example.h to secrets.h and fill it in.

  What it does
  - Reads soil moisture, air temp/humidity and a low-water sensor every 2 s
  - Waters in short shots with a soak wait between them (never long runs)
  - Stops and alerts if the tank is low or the soil won't get wet
  - Keeps watering on its own when Wi-Fi or Supabase is down
  - Every 5 s: sends live status to Supabase and picks up app commands
    (Auto on/off, Water now, Reset fault) in the same request
  - Every 5 min (and right after anything changes): saves a history reading
  - Events go to the Supabase event log; important ones also to Telegram
  - Never talks to the internet while the pump runs, so a slow network
    can't stretch a shot
*/

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <stdarg.h>
#include "secrets.h"

// ===== 1. Device =====
const char DEVICE_ID[]  = "plant-guard-1";   // must match the row in device_settings
const char FW_VERSION[] = "2.0.0";

// ===== 2. Pins =====
const int PIN_SOIL      = 34;  // capacitive soil sensor AOUT
const int PIN_WATER_SIG = 35;  // water level sensor S
const int PIN_WATER_PWR = 26;  // water level sensor +  (powered only while reading)
const int PIN_DHT       = 4;   // DHT22 DAT
const int PIN_RELAY     = 27;  // relay IN

// Mike's relay: VCC on 3V3, IN LOW = ON, IN HIGH = OFF.
const bool RELAY_ACTIVE_LOW = true;

// ===== 3. Calibration =====
const int SOIL_RAW_DRY  = 2440;  // capacitive sensor in air (measured)
const int SOIL_RAW_WET  = 1060;  // capacitive sensor in water up to the line (measured)
const int WATER_OK_RAW  = 600;   // strip needs ~1 cm+ in water to count as OK (measured)
const int WATER_HYST    = 100;   // must rise this much above WATER_OK_RAW to count as refilled

// ===== 4. Watering rules =====
const int SOIL_START_PCT = 35;               // start watering below this
const int SOIL_STOP_PCT  = 60;               // stop the cycle at or above this
const unsigned long PUMP_SHOT_MS   = 3000;   // one shot of water
const unsigned long SOAK_MS        = 60000;  // wait after each shot before deciding again
const int MAX_SHOTS                = 8;      // shots per cycle before giving up (fault)
const unsigned long MANUAL_GAP_MS  = 10000;  // minimum time between "Water now" shots

// ===== 5. Timing =====
const unsigned long READ_INTERVAL_MS     = 2000;    // DHT22 needs at least 2 s
const unsigned long HEARTBEAT_MS         = 5000;    // live status + check for app commands
const unsigned long READING_INTERVAL_MS  = 300000;  // history row every 5 min
const unsigned long READING_MIN_GAP_MS   = 10000;   // extra rows after a change: at most every 10 s
const unsigned long NET_BACKOFF_MS       = 15000;   // pause network work after a failure
const double        WATER_NOW_MAX_AGE_S  = 60;      // ignore "Water now" taps older than this
const uint16_t      HTTP_TIMEOUT_MS      = 5000;

// ------------------------------------------------------------------
DHT dht(PIN_DHT, DHT22);

float tempC = NAN;
float humidity = NAN;
int   soilRaw = 0;
int   soilPct = 0;
int   waterRaw = 0;
bool  waterOk = true;       // start "OK" so an empty tank at boot still raises the alert
bool  soilSensorOk = true;

bool autoEnabled = true;      // replaced by the app's setting on the first heartbeat
bool needsWater = false;      // latched between START and STOP thresholds
int  shotsThisCycle = 0;
bool faultLocked = false;     // set when MAX_SHOTS reached; cleared from the app

bool pumpOn = false;
unsigned long pumpStartedAt = 0;
unsigned long lastShotEndedAt = 0;   // 0 at boot = wait one soak before first auto shot
unsigned long lastManualShotAt = 0;
bool manualShotDone = false;         // false until the first manual shot since boot

unsigned long lastReadAt = 0;
unsigned long lastHeartbeatAt = 0;
unsigned long lastReadingAt = 0;
bool readingSentOnce = false;
bool stateChanged = false;           // send an extra history row soon
unsigned long netBackoffUntil = 0;
bool netBackoff = false;
bool wifiWasConnected = false;

// Settings from the app
bool   settingsSynced = false;       // false until the first good heartbeat
String lastWaterNowSeen;
String lastClearFaultSeen;

// HTTPS to Supabase: one connection, kept open between requests.
// setInsecure(): encrypted, but the server certificate isn't checked.
WiFiClientSecure sbClient;
HTTPClient sbHttp;

// ------------------------------------------------------------------
// Event queue: kept in memory until it reaches Supabase (and Telegram).
// If Wi-Fi is down for long, the oldest events are dropped.
struct PendingEvent {
  char type[20];
  char message[160];
  bool toDb;
  bool toTelegram;
};
const int EVENT_QUEUE_SIZE = 8;
PendingEvent eventQueue[EVENT_QUEUE_SIZE];
int eventHead = 0;
int eventCount = 0;

bool telegramConfigured() {
  return strlen(TG_BOT_TOKEN) > 0 && strlen(TG_CHAT_ID) > 0;
}

// False while secrets.h still has the example URL: the board then runs
// offline (sensors + watering only) without trying to reach Supabase.
bool supabaseConfigured() {
  return strstr(SUPABASE_URL, "your-project-ref") == nullptr
         && strstr(SUPABASE_KEY, "...") == nullptr;
}

// notify = also send it to Telegram
void queueEvent(const char *type, bool notify, const char *fmt, ...) {
  char msg[160];
  va_list args;
  va_start(args, fmt);
  vsnprintf(msg, sizeof(msg), fmt, args);
  va_end(args);

  Serial.printf("EVENT %s: %s\n", type, msg);

  bool toDb = supabaseConfigured();
  bool toTelegram = notify && telegramConfigured();
  if (!toDb && !toTelegram) return;   // nowhere to send it (offline mode)

  if (eventCount == EVENT_QUEUE_SIZE) {   // full: drop the oldest
    Serial.printf("Event queue full, dropped: %s\n", eventQueue[eventHead].type);
    eventHead = (eventHead + 1) % EVENT_QUEUE_SIZE;
    eventCount--;
  }
  PendingEvent &e = eventQueue[(eventHead + eventCount) % EVENT_QUEUE_SIZE];
  strlcpy(e.type, type, sizeof(e.type));
  strlcpy(e.message, msg, sizeof(e.message));
  e.toDb = toDb;
  e.toTelegram = toTelegram;
  eventCount++;
}

// ------------------------------------------------------------------
// Relay / pump
void relayWrite(bool on) {
  bool levelHigh = RELAY_ACTIVE_LOW ? !on : on;
  digitalWrite(PIN_RELAY, levelHigh ? HIGH : LOW);
}

bool startShot(const char *reason) {
  if (pumpOn) return false;
  if (!waterOk) {
    Serial.printf("Shot (%s) blocked: tank low\n", reason);
    return false;
  }
  relayWrite(true);
  pumpOn = true;
  pumpStartedAt = millis();
  stateChanged = true;
  Serial.printf("Pump ON (%s)\n", reason);
  return true;
}

void stopPump(const char *reason) {
  relayWrite(false);
  if (!pumpOn) return;
  pumpOn = false;
  lastShotEndedAt = millis();
  stateChanged = true;
  Serial.printf("Pump OFF (%s)\n", reason);
}

// ------------------------------------------------------------------
// Sensors
int readAnalogAvg(int pin, int samples) {
  long sum = 0;
  for (int i = 0; i < samples; i++) {
    sum += analogRead(pin);
    delay(2);
  }
  return (int)(sum / samples);
}

void readSensors() {
  // Soil (capacitive: higher raw = drier)
  soilRaw = readAnalogAvg(PIN_SOIL, 16);
  bool wasSoilOk = soilSensorOk;
  soilSensorOk = (soilRaw > 300 && soilRaw < 3900);  // outside = unplugged / shorted
  long pct = (long)(SOIL_RAW_DRY - soilRaw) * 100L / (SOIL_RAW_DRY - SOIL_RAW_WET);
  soilPct = (int)constrain(pct, 0L, 100L);
  if (wasSoilOk && !soilSensorOk) {
    queueEvent("sensor_fault", true,
               "Soil sensor reading looks wrong (raw %d). Auto watering paused - check the wiring.", soilRaw);
    stateChanged = true;
  } else if (!wasSoilOk && soilSensorOk) {
    queueEvent("sensor_ok", false, "Soil sensor reading back to normal.");
    stateChanged = true;
  }

  // Water level: power the strip only while reading (stops corrosion)
  digitalWrite(PIN_WATER_PWR, HIGH);
  delay(20);
  waterRaw = readAnalogAvg(PIN_WATER_SIG, 8);
  digitalWrite(PIN_WATER_PWR, LOW);

  bool wasOk = waterOk;
  if (waterOk && waterRaw <= WATER_OK_RAW) waterOk = false;
  else if (!waterOk && waterRaw > WATER_OK_RAW + WATER_HYST) waterOk = true;

  if (wasOk && !waterOk) {
    if (pumpOn) stopPump("tank went low");
    queueEvent("low_water", true, "Tank is low. Refill it - watering is paused.");
    stateChanged = true;
  } else if (!wasOk && waterOk) {
    queueEvent("refilled", true, "Tank refilled. Watering can continue.");
    stateChanged = true;
  }

  // Air (DHT22 returns NAN on a failed read; we just keep NAN)
  tempC = dht.readTemperature();
  humidity = dht.readHumidity();

  Serial.printf("soil raw=%d (%d%%)%s | water raw=%d %s | T=%.1fC RH=%.1f%% | pump=%d auto=%d fault=%d | wifi=%d\n",
                soilRaw, soilPct, soilSensorOk ? "" : " SENSOR?", waterRaw,
                waterOk ? "OK" : "LOW", tempC, humidity, pumpOn, autoEnabled, faultLocked,
                WiFi.status() == WL_CONNECTED);
}

// ------------------------------------------------------------------
// Automatic watering: short shots, soak, re-check, give up after MAX_SHOTS
void autoWater() {
  if (!autoEnabled || faultLocked || pumpOn || !soilSensorOk) return;

  if (soilPct < SOIL_START_PCT) needsWater = true;
  if (soilPct >= SOIL_STOP_PCT) {
    if (needsWater && shotsThisCycle > 0) {
      queueEvent("watering_done", true, "Watering done. Soil %d%% after %d shot(s).",
                 soilPct, shotsThisCycle);
    }
    needsWater = false;
    shotsThisCycle = 0;
  }
  if (!needsWater) return;
  if (millis() - lastShotEndedAt < SOAK_MS) return;  // let the water soak in first
  if (!waterOk) return;                                // low-water event already raised

  if (shotsThisCycle >= MAX_SHOTS) {
    faultLocked = true;   // soil not getting wet: sensor out of soil, tube off, etc.
    stateChanged = true;
    queueEvent("fault", true,
               "Soil still dry after %d shots. Auto watering stopped. Check the sensor and tube, then press Reset fault in the app.",
               MAX_SHOTS);
    return;
  }
  shotsThisCycle++;
  if (startShot("auto")) {
    queueEvent("auto_shot", false, "Auto watering: shot %d of %d (soil %d%%).",
               shotsThisCycle, MAX_SHOTS, soilPct);
  }
}

void clearFault(const char *how) {
  if (!faultLocked) return;
  faultLocked = false;
  shotsThisCycle = 0;
  needsWater = false;
  stateChanged = true;
  queueEvent("fault_cleared", false, "Fault cleared (%s). Auto watering resumes.", how);
}

void manualShot() {
  if (!waterOk) {
    queueEvent("manual_blocked", false, "Water now blocked: tank is low.");
    return;
  }
  if (manualShotDone && millis() - lastManualShotAt < MANUAL_GAP_MS) {
    queueEvent("manual_ignored", false, "Water now ignored: too soon after the last shot.");
    return;
  }
  if (startShot("manual")) {
    manualShotDone = true;
    lastManualShotAt = millis();
    queueEvent("manual_shot", false, "Water now: one %lu s shot.", PUMP_SHOT_MS / 1000);
  }
}

// ------------------------------------------------------------------
// Serial Monitor commands (for bench testing). Same safety rules as the app.
// Note: once Supabase is set up, the app's Auto setting wins within ~5 s.
void printHelp() {
  Serial.println("Commands: w = water now (one 3 s shot) | a = auto on/off | r = reset fault | s = status | h = help");
}

void printStatus() {
  Serial.printf("> soil %d%% (raw %d)%s | tank %s (raw %d) | T=%.1fC RH=%.1f%%\n",
                soilPct, soilRaw, soilSensorOk ? "" : " SENSOR?", waterOk ? "OK" : "LOW", waterRaw,
                tempC, humidity);
  Serial.printf("> pump %s | auto %s | fault %s | shots this cycle %d/%d | wifi %s | supabase %s\n",
                pumpOn ? "ON" : "off", autoEnabled ? "on" : "off", faultLocked ? "YES" : "no",
                shotsThisCycle, MAX_SHOTS, WiFi.status() == WL_CONNECTED ? "connected" : "not connected",
                supabaseConfigured() ? "set up" : "not set up");
}

void handleSerialCommands() {
  while (Serial.available()) {
    char c = tolower(Serial.read());
    switch (c) {
      case 'w':
        Serial.println("> Water now");
        if (pumpOn) Serial.println("> Pump is already running");
        else manualShot();
        break;
      case 'a':
        autoEnabled = !autoEnabled;
        stateChanged = true;
        Serial.printf("> Auto watering %s\n", autoEnabled ? "ON" : "OFF");
        if (autoEnabled) clearFault("Auto switched on");
        break;
      case 'r':
        if (faultLocked) clearFault("reset from Serial Monitor");
        else Serial.println("> No fault to reset");
        break;
      case 's':
        printStatus();
        break;
      case 'h':
      case '?':
        printHelp();
        break;
      case '\r':
      case '\n':
      case ' ':
        break;
      default:
        Serial.printf("> Unknown command '%c'. Type h for help.\n", c);
    }
  }
}

// ------------------------------------------------------------------
// App settings (returned by every heartbeat)
void applySettings(JsonVariantConst s) {
  bool newAuto = s["auto_enabled"] | autoEnabled;
  const char *waterNowAt = s["water_now_at"] | "";
  double waterNowAge = s["water_now_age_s"] | 1e9;
  const char *clearFaultAt = s["clear_fault_at"] | "";

  if (newAuto != autoEnabled) {
    autoEnabled = newAuto;
    stateChanged = true;
    Serial.printf("Auto watering %s\n", autoEnabled ? "ON" : "OFF");
    if (settingsSynced) {
      queueEvent(autoEnabled ? "auto_on" : "auto_off", false,
                 "Auto watering %s.", autoEnabled ? "on" : "off");
    }
    if (autoEnabled) clearFault("Auto switched on");
  }

  // First heartbeat after boot: remember the commands already there, don't act
  // on them, so a restart never triggers a surprise shot.
  if (!settingsSynced) {
    lastWaterNowSeen = waterNowAt;
    lastClearFaultSeen = clearFaultAt;
    settingsSynced = true;
    Serial.println("Settings synced");
    return;
  }

  if (lastClearFaultSeen != clearFaultAt) {
    lastClearFaultSeen = clearFaultAt;
    if (clearFaultAt[0]) clearFault("reset from the app");
  }

  if (lastWaterNowSeen != waterNowAt) {
    lastWaterNowSeen = waterNowAt;
    if (waterNowAt[0]) {
      if (waterNowAge <= WATER_NOW_MAX_AGE_S) manualShot();
      else Serial.println("Water now ignored: request too old");
    }
  }
}

// ------------------------------------------------------------------
// Network helpers
void fillStatus(JsonObject o) {
  if (isnan(tempC)) o["temp_c"] = nullptr;   else o["temp_c"] = roundf(tempC * 10) / 10.0f;
  if (isnan(humidity)) o["humidity"] = nullptr; else o["humidity"] = roundf(humidity * 10) / 10.0f;
  o["soil_pct"]     = soilPct;
  o["soil_raw"]     = soilRaw;
  o["water_ok"]     = waterOk;
  o["water_raw"]    = waterRaw;
  o["pump_on"]      = pumpOn;
  o["auto_enabled"] = autoEnabled;
  o["fault"]        = faultLocked;
}

// POST to Supabase. Returns the HTTP code (negative = no connection).
int supabasePost(const char *path, const String &body, String *response) {
  String url = String(SUPABASE_URL) + path;
  if (!sbHttp.begin(sbClient, url)) return -1;
  sbHttp.setConnectTimeout(HTTP_TIMEOUT_MS);
  sbHttp.setTimeout(HTTP_TIMEOUT_MS);
  sbHttp.addHeader("apikey", SUPABASE_KEY);
  sbHttp.addHeader("Content-Type", "application/json");
  if (!response) sbHttp.addHeader("Prefer", "return=minimal");

  int code = sbHttp.POST(body);
  String reply = (code > 0) ? sbHttp.getString() : String();
  sbHttp.end();

  if (response) *response = reply;
  if (code < 200 || code >= 300) {
    Serial.printf("Supabase %s failed: %d %s\n", path, code, reply.c_str());
  }
  return code;
}

int telegramSend(const char *text) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  String url = String("https://api.telegram.org/bot") + TG_BOT_TOKEN + "/sendMessage";
  if (!http.begin(client, url)) return -1;
  http.setConnectTimeout(HTTP_TIMEOUT_MS);
  http.setTimeout(HTTP_TIMEOUT_MS);
  http.addHeader("Content-Type", "application/json");

  JsonDocument doc;
  doc["chat_id"] = TG_CHAT_ID;
  doc["text"] = String("Plant Guard: ") + text;
  String body;
  serializeJson(doc, body);

  int code = http.POST(body);
  if (code != 200) {
    Serial.printf("Telegram failed: %d %s\n", code, code > 0 ? http.getString().c_str() : "");
  }
  http.end();
  return code;
}

// 4xx (except 408/429) means the request itself is wrong: retrying won't help.
bool isPermanentError(int code) {
  return code >= 400 && code < 500 && code != 408 && code != 429;
}

void startBackoff() {
  netBackoff = true;
  netBackoffUntil = millis() + NET_BACKOFF_MS;
}

// Sends (part of) the oldest event. Returns false on a temporary failure.
bool sendNextEvent() {
  PendingEvent &e = eventQueue[eventHead];

  if (e.toDb) {
    JsonDocument doc;
    doc["device_id"] = DEVICE_ID;
    doc["type"] = e.type;
    doc["message"] = e.message;
    String body;
    serializeJson(doc, body);
    int code = supabasePost("/rest/v1/events", body, nullptr);
    if (code == 201 || isPermanentError(code)) e.toDb = false;
    else return false;
  }

  if (e.toTelegram) {
    int code = telegramSend(e.message);
    if (code == 200 || isPermanentError(code)) e.toTelegram = false;
    else return false;
  }

  eventHead = (eventHead + 1) % EVENT_QUEUE_SIZE;
  eventCount--;
  return true;
}

bool doHeartbeat() {
  JsonDocument doc;
  doc["p_device_id"] = DEVICE_ID;
  JsonObject s = doc["p_status"].to<JsonObject>();
  fillStatus(s);
  s["rssi"] = WiFi.RSSI();
  s["uptime_s"] = millis() / 1000;
  s["fw"] = FW_VERSION;
  String body;
  serializeJson(doc, body);

  String reply;
  int code = supabasePost("/rest/v1/rpc/heartbeat", body, &reply);
  if (code != 200) return false;

  JsonDocument r;
  if (deserializeJson(r, reply)) {
    Serial.println("Heartbeat: couldn't read the reply");
    return true;   // the server answered; not a network problem
  }
  if (r.isNull()) {
    Serial.println("Settings: no row for this device_id");
    return true;
  }
  applySettings(r.as<JsonVariantConst>());
  return true;
}

bool sendReading() {
  JsonDocument doc;
  JsonObject o = doc.to<JsonObject>();
  o["device_id"] = DEVICE_ID;
  fillStatus(o);
  String body;
  serializeJson(doc, body);
  int code = supabasePost("/rest/v1/readings", body, nullptr);
  if (code == 201) {
    Serial.println("Reading saved");
    return true;
  }
  return isPermanentError(code);   // don't retry a request Supabase rejected
}

// One network job per loop pass, never while the pump runs.
void networkTasks() {
  if (pumpOn) return;

  bool connected = WiFi.status() == WL_CONNECTED;
  if (connected != wifiWasConnected) {
    wifiWasConnected = connected;
    Serial.println(connected ? "Wi-Fi connected" : "Wi-Fi lost, watering carries on");
  }
  if (!connected) return;
  if (netBackoff && (long)(millis() - netBackoffUntil) < 0) return;
  netBackoff = false;

  unsigned long now = millis();

  if (eventCount > 0) {
    if (!sendNextEvent()) startBackoff();
    return;
  }

  if (!supabaseConfigured()) return;   // offline mode until secrets.h is filled in

  if (!settingsSynced || now - lastHeartbeatAt >= HEARTBEAT_MS) {
    lastHeartbeatAt = now;
    if (!doHeartbeat()) startBackoff();
    return;
  }

  bool readingDue = !readingSentOnce
                    || now - lastReadingAt >= READING_INTERVAL_MS
                    || (stateChanged && now - lastReadingAt >= READING_MIN_GAP_MS);
  if (readingDue) {
    if (sendReading()) {
      readingSentOnce = true;
      lastReadingAt = now;
      stateChanged = false;
    } else {
      startBackoff();
    }
  }
}

// ------------------------------------------------------------------
void setup() {
  pinMode(PIN_RELAY, OUTPUT);
  relayWrite(false);                 // pump off before anything else
  pinMode(PIN_WATER_PWR, OUTPUT);
  digitalWrite(PIN_WATER_PWR, LOW);

  Serial.begin(115200);
  delay(200);
  Serial.println("\nPlant Guard starting (Supabase + Telegram)");
  if (!supabaseConfigured()) {
    Serial.println("Supabase not set up in secrets.h: running offline (sensors + watering only)");
  }

  analogReadResolution(12);          // 0..4095
  dht.begin();

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);  // doesn't block; watering works without Wi-Fi

  sbClient.setInsecure();
  sbHttp.setReuse(true);

  delay(2000);                       // let the DHT22 settle before the first read
  readSensors();
  lastReadAt = millis();
  queueEvent("boot", true, "Online. Soil %d%%, tank %s.", soilPct, waterOk ? "OK" : "LOW");
  printHelp();
}

void loop() {
  unsigned long now = millis();

  // Safety first: end the shot on time, whatever else is happening
  if (pumpOn && now - pumpStartedAt >= PUMP_SHOT_MS) stopPump("shot done");

  if (now - lastReadAt >= READ_INTERVAL_MS) {
    lastReadAt = now;
    readSensors();
    autoWater();
  }

  handleSerialCommands();
  networkTasks();
}
