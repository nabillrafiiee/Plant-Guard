import 'package:flutter/material.dart';

enum EventTone { good, bad, info, neutral }

/// How each event type from the firmware looks in the app.
class EventStyle {
  const EventStyle(this.label, this.icon, this.tone);

  final String label;
  final IconData icon;
  final EventTone tone;

  static EventStyle of(String type) => _styles[type] ??
      EventStyle(type.replaceAll('_', ' '), Icons.info_outline, EventTone.neutral);

  static const _styles = {
    'boot': EventStyle('Device online', Icons.power_settings_new, EventTone.info),
    'low_water': EventStyle('Tank low', Icons.water_drop_outlined, EventTone.bad),
    'refilled': EventStyle('Tank refilled', Icons.water_drop, EventTone.good),
    'watering_done': EventStyle('Watering done', Icons.check_circle_outline, EventTone.good),
    'auto_shot': EventStyle('Auto watering', Icons.opacity, EventTone.info),
    'manual_shot': EventStyle('Water now', Icons.shower_outlined, EventTone.info),
    'manual_blocked': EventStyle('Water now blocked', Icons.block, EventTone.bad),
    'manual_ignored': EventStyle('Water now ignored', Icons.timer_outlined, EventTone.neutral),
    'fault': EventStyle('Watering fault', Icons.error_outline, EventTone.bad),
    'fault_cleared': EventStyle('Fault cleared', Icons.restart_alt, EventTone.good),
    'auto_on': EventStyle('Auto watering on', Icons.autorenew, EventTone.neutral),
    'auto_off': EventStyle('Auto watering off', Icons.pause_circle_outline, EventTone.neutral),
    'sensor_fault': EventStyle('Soil sensor problem', Icons.sensors_off, EventTone.bad),
    'sensor_ok': EventStyle('Soil sensor OK', Icons.sensors, EventTone.good),
  };

  Color color(ColorScheme c) => switch (tone) {
        EventTone.good => c.tertiary,
        EventTone.bad => c.error,
        EventTone.info => c.primary,
        EventTone.neutral => c.onSurfaceVariant,
      };

  Color background(ColorScheme c) => switch (tone) {
        EventTone.good => c.tertiaryContainer,
        EventTone.bad => c.errorContainer,
        EventTone.info => c.primaryContainer,
        EventTone.neutral => c.surfaceContainerHighest,
      };
}
