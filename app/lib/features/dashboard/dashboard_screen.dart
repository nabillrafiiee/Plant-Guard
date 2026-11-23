import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../../ui/format.dart';
import '../../ui/widgets.dart';
import 'dashboard_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(deviceStatusProvider);
    final online = ref.watch(isOnlineProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final status = statusAsync.value;

    final subtitle = switch (status) {
      null when statusAsync.isLoading => 'Connecting…',
      null => 'Waiting for the device',
      DeviceStatus s when online => 'Online · updated ${timeAgo(s.updatedAt, now: now)}',
      DeviceStatus s => 'Offline · last seen ${timeAgo(s.updatedAt, now: now)}',
    };

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Plant Guard'),
            const SizedBox(height: 4),
            OnlineDot(online: online, label: subtitle),
          ],
        ),
      ),
      body: statusAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(deviceStatusProvider),
        ),
        data: (status) => RefreshIndicator.adaptive(
          onRefresh: () async {
            refreshAll(ref);
            await Future<void>.delayed(const Duration(milliseconds: 600));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              PageBody(child: _Content(status: status, online: online)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.status, required this.online});

  final DeviceStatus? status;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final banners = <Widget>[
      if (s == null)
        const AlertBanner(
          icon: Icons.hourglass_empty,
          title: 'No data from the device yet',
          message: 'Power on the ESP32 and check that it is connected to Wi-Fi.',
        )
      else if (!online)
        const AlertBanner(
          icon: Icons.cloud_off,
          title: 'Device offline',
          message: 'The values below may be old. Watering still runs on the device.',
        ),
      if (s != null && s.fault)
        const AlertBanner(
          icon: Icons.error_outline,
          error: true,
          title: 'Watering stopped: soil stayed dry',
          message: 'Check that the soil sensor is in the pot and the tube is attached, '
              'then tap Reset fault below.',
        ),
      if (s != null && s.waterOk == false)
        const AlertBanner(
          icon: Icons.water_drop_outlined,
          error: true,
          title: 'Tank is low',
          message: 'Refill the tank. Watering is paused until then.',
        ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final twoColumns = constraints.maxWidth >= 720;
      const gap = SizedBox(height: 16);

      final left = [
        SoilCard(status: s),
        gap,
        StatsGrid(status: s),
      ];
      final right = [
        ControlsCard(status: s, online: online),
        gap,
        const RecentEventsCard(),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in banners) ...[b, const SizedBox(height: 12)],
          if (twoColumns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: left)),
                const SizedBox(width: 16),
                Expanded(child: Column(children: right)),
              ],
            )
          else ...[
            ...left,
            gap,
            ...right,
          ],
        ],
      );
    });
  }
}
