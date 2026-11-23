/// Settings passed in at build time from env.json:
///   flutter run --dart-define-from-file=env.json
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');
  static const deviceId =
      String.fromEnvironment('DEVICE_ID', defaultValue: 'plant-guard-1');

  static bool get isConfigured =>
      supabaseUrl.startsWith('https://') && supabaseKey.isNotEmpty;
}

/// Values that must match the firmware (PlantGuard.ino).
abstract final class DeviceRules {
  static const soilStartPct = 35; // starts watering below this
  static const soilStopPct = 60; // stops at or above this
  static const maxShots = 8;
  static const shotSeconds = 3;

  /// The ESP32 sends a heartbeat every 5 s. No heartbeat for this long = offline.
  static const offlineAfter = Duration(seconds: 30);
}
