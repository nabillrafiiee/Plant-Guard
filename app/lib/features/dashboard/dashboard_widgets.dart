import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/env.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../ui/event_style.dart';
import '../../ui/format.dart';
import '../../ui/widgets.dart';

// ---------------------------------------------------------------------------
// Soil moisture: big gauge with the start / stop thresholds marked.

class SoilCard extends StatelessWidget {
  const SoilCard({super.key, required this.status});

  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pct = status?.soilPct;

    final (label, color) = switch (pct) {
      null => ('No reading', c.outline),
      < DeviceRules.soilStartPct => ('Dry', const Color(0xFFE0892B)),
      < DeviceRules.soilStopPct => ('OK', c.primary),
      _ => ('Moist', const Color(0xFF2F80ED)),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.grass, color: c.primary),
                const SizedBox(width: 8),
                Text('Soil moisture', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label: pct == null ? 'Soil moisture unknown' : 'Soil moisture $pct percent, $label',
              child: SizedBox.square(
                dimension: 190,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: (pct ?? 0) / 100),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => CustomPaint(
                    painter: _GaugePainter(
                      value: value,
                      color: color,
                      track: c.surfaceContainerHighest,
                      tick: c.onSurfaceVariant,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pct == null ? '--' : '$pct%',
                            style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(label, style: text.titleSmall?.copyWith(color: color)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Waters below ${DeviceRules.soilStartPct}% · stops at ${DeviceRules.soilStopPct}%',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.color,
    required this.track,
    required this.tick,
  });

  final double value; // 0..1
  final Color color;
  final Color track;
  final Color tick;

  static const _start = math.pi * 0.75; // 135°
  static const _sweep = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, _start, _sweep, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(arcRect, _start, _sweep * value.clamp(0, 1), false, paint..color = color);
    }

    // Threshold ticks just outside the arc.
    final center = rect.center;
    final r = arcRect.width / 2;
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final pct in [DeviceRules.soilStartPct, DeviceRules.soilStopPct]) {
      final a = _start + _sweep * pct / 100;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (r + stroke / 2 + 1), center + dir * (r + stroke / 2 + 6), tickPaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color || old.track != track;
}

// ---------------------------------------------------------------------------
// Small tiles: tank, temperature, humidity, last watered.

class StatsGrid extends ConsumerWidget {
  const StatsGrid({super.key, required this.status});

  final DeviceStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).colorScheme;
    final s = status;
    final events = ref.watch(eventsProvider).value ?? const [];
    final lastShot = events.where((e) => e.isPumpShot).firstOrNull;
    final watering = ref.watch(commandProvider) == Command.waterNow;

    final tiles = [
      _StatTile(
        icon: s?.waterOk == false ? Icons.water_drop_outlined : Icons.water_drop,
        label: 'Tank',
        value: switch (s?.waterOk) { true => 'OK', false => 'LOW', null => '--' },
        color: s?.waterOk == false ? c.error : const Color(0xFF2F80ED),
      ),
      _StatTile(
        icon: Icons.thermostat,
        label: 'Temperature',
        value: s?.tempC == null ? '--' : '${s!.tempC!.toStringAsFixed(1)} °C',
        color: const Color(0xFFE0892B),
      ),
      _StatTile(
        icon: Icons.cloud_outlined,
        label: 'Humidity',
        value: s?.humidity == null ? '--' : '${s!.humidity!.round()} %',
        color: c.secondary,
      ),
      _StatTile(
        icon: Icons.shower_outlined,
        label: 'Last watered',
        value: watering
            ? 'Watering…'
            : lastShot == null
                ? '--'
                : timeAgo(lastShot.createdAt),
        color: c.primary,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 12.0;
      final perRow = constraints.maxWidth >= 560 ? 4 : 2;
      final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final t in tiles) SizedBox(width: width, child: t)],
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(label, style: text.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                value,
                key: ValueKey(value),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls: Auto switch, Water now, Reset fault.

class ControlsCard extends ConsumerStatefulWidget {
  const ControlsCard({super.key, required this.status, required this.online});

  final DeviceStatus? status;
  final bool online;

  @override
  ConsumerState<ControlsCard> createState() => _ControlsCardState();
}

class _ControlsCardState extends ConsumerState<ControlsCard> {
  bool? _pendingAuto; // shown straight away while saving

  Future<void> _setAuto(bool value) async {
    setState(() => _pendingAuto = value);
    try {
      await ref.read(repositoryProvider).setAuto(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingAuto = null);
      showResult(context, ok: false, message: "Couldn't change Auto: $e");
    }
  }

  Future<void> _waterNow() async {
    final result = await ref.read(commandProvider.notifier).waterNow();
    if (mounted) showResult(context, ok: result.ok, message: result.message);
  }

  Future<void> _resetFault() async {
    final yes = await confirmDialog(
      context,
      title: 'Reset fault?',
      message: 'Only do this after checking that the soil sensor is in the pot '
          'and the tube is attached. Auto watering will start again.',
      confirmLabel: 'Reset',
    );
    if (!yes || !mounted) return;
    final result = await ref.read(commandProvider.notifier).resetFault();
    if (mounted) showResult(context, ok: result.ok, message: result.message);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(deviceSettingsProvider).value;
    final running = ref.watch(commandProvider);
    final status = widget.status;
    final online = widget.online;

    // Clear the optimistic value once the saved setting matches it.
    ref.listen(deviceSettingsProvider, (_, next) {
      if (next.value?.autoEnabled == _pendingAuto) setState(() => _pendingAuto = null);
    });

    final autoOn = _pendingAuto ?? settings?.autoEnabled ?? true;
    final autoHint = switch (status) {
      _ when _pendingAuto != null => 'Saving…',
      null => 'Saved. The device will use it when it connects.',
      _ when !online => 'Saved. The device will use it when it is back online.',
      DeviceStatus s when s.autoEnabled != autoOn => 'Waiting for the device…',
      _ when autoOn => 'Waters by itself below ${DeviceRules.soilStartPct}% soil moisture.',
      _ => 'Off: the plant is only watered when you tap Water now.',
    };

    final tankLow = status?.waterOk == false;
    final String? waterBlockedReason = !online
        ? 'The device is offline.'
        : tankLow
            ? 'The tank is low. Refill it first.'
            : null;
    final watering = running == Command.waterNow;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.tune, color: c.primary),
                  const SizedBox(width: 8),
                  Text('Controls', style: text.titleMedium),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              value: autoOn,
              onChanged: settings == null || _pendingAuto != null ? null : _setAuto,
              title: const Text('Auto watering'),
              subtitle: Text(autoHint),
              secondary: const Icon(Icons.autorenew),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: waterBlockedReason == null && running == null ? _waterNow : null,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    icon: watering
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator.adaptive(strokeWidth: 2.5),
                          )
                        : const Icon(Icons.shower_outlined),
                    label: Text(watering ? 'Waiting for the device…' : 'Water now'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    waterBlockedReason ??
                        'One ${DeviceRules.shotSeconds} s shot. Reaches the device within about 5 s.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: waterBlockedReason == null ? c.onSurfaceVariant : c.error,
                    ),
                  ),
                  if (status?.fault ?? false) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: online && running == null ? _resetFault : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: c.error,
                      ),
                      icon: running == Command.resetFault
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                            )
                          : const Icon(Icons.restart_alt),
                      label: const Text('Reset fault'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Last few events, with a link to the full list.

class RecentEventsCard extends ConsumerWidget {
  const RecentEventsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final events = ref.watch(eventsProvider);
    ref.watch(clockProvider); // keep "x min ago" fresh

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Icon(Icons.notifications_outlined, color: c.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Recent events', style: text.titleMedium)),
                  TextButton(
                    onPressed: () => context.go('/events'),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            ...events.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              ],
              error: (e, _) => [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text("Couldn't load events.", style: text.bodySmall),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('No events yet.',
                            style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                      ),
                    ]
                  : [for (final e in list.take(4)) EventTile(event: e, dense: true)],
            ),
          ],
        ),
      ),
    );
  }
}

/// One event row, used here and on the Events screen.
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.dense = false, this.showDay = false});

  final PlantEvent event;
  final bool dense;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final style = EventStyle.of(event.type);
    return ListTile(
      dense: dense,
      leading: CircleAvatar(
        radius: dense ? 18 : 20,
        backgroundColor: style.background(c),
        child: Icon(style.icon, size: dense ? 18 : 20, color: style.color(c)),
      ),
      title: Text(style.label),
      subtitle: event.message == null
          ? null
          : Text(event.message!, maxLines: dense ? 1 : 3, overflow: TextOverflow.ellipsis),
      trailing: Text(
        showDay ? dayAndTime(event.createdAt) : timeAgo(event.createdAt),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
      ),
    );
  }
}
