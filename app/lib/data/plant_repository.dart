import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// The only place that talks to Supabase.
class PlantRepository {
  PlantRepository(this._db, this.deviceId);

  final SupabaseClient _db;
  final String deviceId;

  // ---- Live data (Realtime: first the current rows, then every change) ----

  Stream<DeviceStatus?> watchStatus() => _db
      .from('device_status')
      .stream(primaryKey: ['device_id'])
      .eq('device_id', deviceId)
      .map((rows) => rows.isEmpty ? null : DeviceStatus.fromMap(rows.first));

  Stream<DeviceSettings?> watchSettings() => _db
      .from('device_settings')
      .stream(primaryKey: ['device_id'])
      .eq('device_id', deviceId)
      .map((rows) => rows.isEmpty ? null : DeviceSettings.fromMap(rows.first));

  Stream<List<PlantEvent>> watchEvents({int limit = 100}) => _db
      .from('events')
      .stream(primaryKey: ['id'])
      .eq('device_id', deviceId)
      .order('created_at', ascending: false)
      .limit(limit)
      .map((rows) => rows.map(PlantEvent.fromMap).toList());

  // ---- History ----

  Future<History> fetchHistory(HistoryRange range) async {
    final since = DateTime.now().subtract(range.duration);
    final sinceUtc = since.toUtc().toIso8601String();

    final List<dynamic> pointRows = await _db.rpc('readings_history', params: {
      'p_device_id': deviceId,
      'p_since': sinceUtc,
      'p_bucket_minutes': range.bucketMinutes,
    });
    final shotRows = await _db
        .from('events')
        .select('id,created_at,type,message')
        .eq('device_id', deviceId)
        .inFilter('type', ['manual_shot', 'auto_shot'])
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: true)
        .limit(1000);

    final points = pointRows
        .cast<Map<String, dynamic>>()
        .map(HistoryPoint.fromMap)
        .toList();
    final shots = shotRows.map(PlantEvent.fromMap).toList();
    return History(since: since, points: points, shots: shots);
  }

  // ---- Commands ----
  // The server replaces the times below with its own clock (trigger
  // device_settings_stamp), so a wrong phone clock can't break them.

  Future<DateTime> requestWaterNow() =>
      _stampCommand('water_now_at');

  Future<DateTime> requestResetFault() =>
      _stampCommand('clear_fault_at');

  Future<void> setAuto(bool enabled) => _db
      .from('device_settings')
      .update({'auto_enabled': enabled})
      .eq('device_id', deviceId);

  Future<DateTime> _stampCommand(String column) async {
    final row = await _db
        .from('device_settings')
        .update({column: DateTime.now().toUtc().toIso8601String()})
        .eq('device_id', deviceId)
        .select(column)
        .single();
    return DateTime.parse(row[column] as String).toLocal();
  }

  /// Waits for the device to log one of [types] at or after [after].
  /// Returns null if nothing arrives within [timeout].
  Future<PlantEvent?> waitForEvent(
    Set<String> types, {
    required DateTime after,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    bool matches(PlantEvent e) =>
        types.contains(e.type) && !e.createdAt.isBefore(after);
    try {
      final events = await watchEvents(limit: 10)
          .firstWhere((list) => list.any(matches))
          .timeout(timeout);
      return events.firstWhere(matches);
    } on TimeoutException {
      return null;
    }
  }
}
