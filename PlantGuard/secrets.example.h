// Copy this file to "secrets.h" in the same folder and fill it in.
// secrets.h is listed in .gitignore, so your passwords never reach GitHub.

#pragma once

// Wi-Fi (2.4 GHz only, the ESP32 can't see 5 GHz)
#define WIFI_SSID     "your-wifi-name"
#define WIFI_PASS     "your-wifi-password"

// Supabase > Project Settings > Data API / API Keys
// URL with no "/" at the end. Use the PUBLISHABLE key (sb_publishable_...),
// never the secret key.
#define SUPABASE_URL  "https://your-project-ref.supabase.co"
#define SUPABASE_KEY  "sb_publishable_..."

// Telegram (from @BotFather and @userinfobot). Leave both "" to turn alerts off.
#define TG_BOT_TOKEN  ""
#define TG_CHAT_ID    ""
