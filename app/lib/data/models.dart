// Data from Supabase. Field names match the columns in schema.sql.

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;
double? _double(Object? v) => v is num ? v.toDouble() : null;
int? _int(Object? v) => v is num ? v.round() : null;
bool? _bool(Object? v) => v is bool ? v : null;

/// Live state of the device (table device_status, updated every 5 s).
class DeviceStatus {
  const DeviceStatus({
    required this.updatedAt,
    this.tempC,
    this.humidity,
    this.soilPct,
    this.soilRaw,
    this.waterOk,
    this.waterRaw,
    this.pumpOn = false,
    this.autoEnabled,
    this.fault = false,
    this.rssi,
    this.uptimeS,
    this.firmware,
  });

  factory DeviceStatus.fromMap(Map<String, dynamic> m) => DeviceStatus(
        updatedAt: _date(m['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        tempC: _double(m['temp_c']),
        humidity: _double(m['humidity']),
        soilPct: _int(m['soil_pct']),
        soilRaw: _int(m['soil_raw']),
        waterOk: _bool(m['water_ok']),
        waterRaw: _int(m['water_raw']),
        pumpOn: _bool(m['pump_on']) ?? false,
        autoEnabled: _bool(m['auto_enabled']),
        fault: _bool(m['fault']) ?? false,
        rssi: _int(m['rssi']),
        uptimeS: _int(m['uptime_s']),
        firmware: m['fw'] as String?,
      );

  final DateTime updatedAt;
  final double? tempC;
  final double? humidity;
  final int? soilPct;
  final int? soilRaw;
  final bool? waterOk;
  final int? waterRaw;
  final bool pumpOn;
  final bool? autoEnabled;
  final bool fault;
  final int? rssi;
  final int? uptimeS;
  final String? firmware;

  bool isOnlineAt(DateTime now, Duration offlineAfter) =>
      now.difference(updatedAt) < offlineAfter;
}

/// What the app controls (table device_settings).
class DeviceSettings {
  const DeviceSettings({
    required this.autoEnabled,
    this.waterNowAt,
    this.clearFaultAt,
    this.updatedAt,
  });

  factory DeviceSettings.fromMap(Map<String, dynamic> m) => DeviceSettings(
        autoEnabled: _bool(m['auto_enabled']) ?? true,
        waterNowAt: _date(m['water_now_at']),
        clearFaultAt: _date(m['clear_fault_at']),
        updatedAt: _date(m['updated_at']),
      );

  final bool autoEnabled;
  final DateTime? waterNowAt;
  final DateTime? clearFaultAt;
  final DateTime? updatedAt;
}

/// One entry in the event log (table events).
class PlantEvent {
  const PlantEvent({
    required this.id,
    required this.createdAt,
    required this.type,
    this.message,
  });

  factory PlantEvent.fromMap(Map<String, dynamic> m) => PlantEvent(
        id: _int(m['id']) ?? 0,
        createdAt: _date(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        type: m['type'] as String? ?? 'unknown',
        message: m['message'] as String?,
      );

  final int id;
  final DateTime createdAt;
  final String type;
  final String? message;

  bool get isPumpShot => type == 'manual_shot' || type == 'auto_shot';
}

/// One averaged point for the history charts (function readings_history).
class HistoryPoint {
  const HistoryPoint({
    required this.time,
    this.soilPct,
    this.tempC,
    this.humidity,
    this.waterLow = false,
  });

  factory HistoryPoint.fromMap(Map<String, dynamic> m) => HistoryPoint(
        time: _date(m['bucket']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        soilPct: _double(m['soil_pct']),
        tempC: _double(m['temp_c']),
        humidity: _double(m['humidity']),
        waterLow: _bool(m['water_low']) ?? false,
      );

  final DateTime time;
  final double? soilPct;
  final double? tempC;
  final double? humidity;
  final bool waterLow;
}

enum HistoryRange {
  day('24 h', Duration(hours: 24), 5),
  week('7 d', Duration(days: 7), 30),
  month('30 d', Duration(days: 30), 120);

  const HistoryRange(this.label, this.duration, this.bucketMinutes);

  final String label;
  final Duration duration;
  final int bucketMinutes;
}

/// History for one range: averaged readings plus the times the pump ran.
class History {
  const History({required this.since, required this.points, required this.shots});

  final DateTime since;
  final List<HistoryPoint> points;
  final List<PlantEvent> shots;
}
