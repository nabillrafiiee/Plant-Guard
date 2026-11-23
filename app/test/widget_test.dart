import 'package:flutter_test/flutter_test.dart';
import 'package:plant_guard/config/env.dart';
import 'package:plant_guard/data/models.dart';
import 'package:plant_guard/ui/event_style.dart';
import 'package:plant_guard/ui/format.dart';

void main() {
  group('DeviceStatus.fromMap', () {
    test('reads a full heartbeat row', () {
      final s = DeviceStatus.fromMap({
        'device_id': 'plant-guard-1',
        'updated_at': '2026-11-22T08:07:34.366042+00:00',
        'temp_c': 29.1,
        'humidity': 67,
        'soil_pct': 42,
        'soil_raw': 1900,
        'water_ok': true,
        'water_raw': 1700,
        'pump_on': false,
        'auto_enabled': true,
        'fault': false,
        'rssi': -61,
        'uptime_s': 3600,
        'fw': '2.0.0',
      });
      expect(s.updatedAt.toUtc(), DateTime.utc(2026, 11, 22, 8, 7, 34, 366, 42));
      expect(s.tempC, 29.1);
      expect(s.humidity, 67.0); // int in JSON becomes double
      expect(s.soilPct, 42);
      expect(s.waterOk, isTrue);
      expect(s.rssi, -61);
      expect(s.firmware, '2.0.0');
    });

    test('handles nulls (failed DHT22 read)', () {
      final s = DeviceStatus.fromMap({
        'updated_at': '2026-11-22T08:00:00+00:00',
        'temp_c': null,
        'humidity': null,
        'pump_on': null,
        'fault': null,
      });
      expect(s.tempC, isNull);
      expect(s.humidity, isNull);
      expect(s.pumpOn, isFalse);
      expect(s.fault, isFalse);
    });
  });

  test('online when the last heartbeat is newer than 30 s', () {
    final t = DateTime(2026, 11, 22, 12);
    final s = DeviceStatus(updatedAt: t);
    expect(s.isOnlineAt(t.add(const Duration(seconds: 29)), DeviceRules.offlineAfter), isTrue);
    expect(s.isOnlineAt(t.add(const Duration(seconds: 30)), DeviceRules.offlineAfter), isFalse);
  });

  test('DeviceSettings defaults Auto to on when missing', () {
    final s = DeviceSettings.fromMap({'water_now_at': null});
    expect(s.autoEnabled, isTrue);
    expect(s.waterNowAt, isNull);
  });

  test('HistoryPoint reads the readings_history row', () {
    final p = HistoryPoint.fromMap({
      'bucket': '2026-11-22T08:05:00+00:00',
      'soil_pct': 41.5,
      'temp_c': 29,
      'humidity': null,
      'water_low': true,
      'samples': 2,
    });
    expect(p.soilPct, 41.5);
    expect(p.tempC, 29.0);
    expect(p.humidity, isNull);
    expect(p.waterLow, isTrue);
  });

  test('pump shot events are recognised', () {
    PlantEvent e(String type) =>
        PlantEvent(id: 1, createdAt: DateTime(2026), type: type);
    expect(e('manual_shot').isPumpShot, isTrue);
    expect(e('auto_shot').isPumpShot, isTrue);
    expect(e('watering_done').isPumpShot, isFalse);
  });

  test('every firmware event type has its own label', () {
    const types = [
      'boot', 'low_water', 'refilled', 'watering_done', 'auto_shot',
      'manual_shot', 'manual_blocked', 'manual_ignored', 'fault',
      'fault_cleared', 'auto_on', 'auto_off', 'sensor_fault', 'sensor_ok',
    ];
    for (final t in types) {
      expect(EventStyle.of(t).label, isNot(t.replaceAll('_', ' ')), reason: t);
    }
    expect(EventStyle.of('something_new').label, 'something new');
  });

  group('timeAgo', () {
    final now = DateTime(2026, 11, 22, 15, 30);
    test('short times', () {
      expect(timeAgo(now.subtract(const Duration(seconds: 2)), now: now), 'just now');
      expect(timeAgo(now.subtract(const Duration(seconds: 12)), now: now), '12 s ago');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
    });
    test('older times show the day', () {
      expect(timeAgo(DateTime(2026, 11, 21, 14, 5), now: now), 'Yesterday 14:05');
      expect(timeAgo(DateTime(2026, 11, 18, 9, 0), now: now), '18 Nov 09:00');
    });
  });

  test('uptime and Wi-Fi formatting', () {
    expect(duration(45), '45 s');
    expect(duration(3 * 3600 + 25 * 60), '3 h 25 min');
    expect(duration(2 * 86400 + 5 * 3600), '2 d 5 h');
    expect(wifiQuality(-50), startsWith('Excellent'));
    expect(wifiQuality(-80), startsWith('Weak'));
  });
}
