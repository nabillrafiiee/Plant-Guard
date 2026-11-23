import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../../ui/format.dart';
import '../../ui/widgets.dart';
import '../dashboard/dashboard_widgets.dart';

/// Full event log, newest first, grouped by day. New events appear live.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);
    ref.watch(clockProvider); // keep "x min ago" fresh

    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: events.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(eventsProvider)),
        data: (list) => RefreshIndicator.adaptive(
          onRefresh: () async {
            ref.invalidate(eventsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 600));
          },
          child: list.isEmpty ? const _Empty() : _List(events: list),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.events});

  final List<PlantEvent> events;

  @override
  Widget build(BuildContext context) {
    // Build a flat list of day headings and events.
    final items = <Object>[];
    String? lastDay;
    for (final e in events) {
      final day = dayHeading(e.createdAt);
      if (day != lastDay) {
        items.add(day);
        lastDay = day;
      }
      items.add(e);
    }

    final text = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == items.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Showing the latest ${events.length} events',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          );
        }
        final item = items[i];
        return PageBody(
          maxWidth: 800,
          child: item is String
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(item, style: text.titleSmall?.copyWith(color: c.primary)),
                )
              : EventTile(event: item as PlantEvent),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.notifications_none, size: 56, color: c.outline),
        const SizedBox(height: 12),
        Text('No events yet',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Watering, tank and fault events from the device will show up here.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
      ],
    );
  }
}
