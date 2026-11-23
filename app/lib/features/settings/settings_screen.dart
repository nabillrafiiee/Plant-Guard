import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';
import '../../providers.dart';
import '../../ui/format.dart';
import '../../ui/widgets.dart';

const appVersion = '1.0.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final yes = await confirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need your email and password to log in again.',
      confirmLabel: 'Log out',
    );
    if (yes) await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(deviceStatusProvider).value;
    final online = ref.watch(isOnlineProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          PageBody(
            maxWidth: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Heading('Device'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.memory),
                        title: const Text('Device'),
                        subtitle: Text(Env.deviceId),
                        trailing: OnlineDot(online: online),
                      ),
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('Last seen'),
                        subtitle: Text(status == null ? 'Never' : timeAgo(status.updatedAt, now: now)),
                      ),
                      ListTile(
                        leading: const Icon(Icons.wifi),
                        title: const Text('Wi-Fi signal'),
                        subtitle: Text(status?.rssi == null ? '--' : wifiQuality(status!.rssi!)),
                      ),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined),
                        title: const Text('Running for'),
                        subtitle: Text(status?.uptimeS == null ? '--' : duration(status!.uptimeS!)),
                      ),
                      ListTile(
                        leading: const Icon(Icons.system_update_alt),
                        title: const Text('Firmware'),
                        subtitle: Text(status?.firmware ?? '--'),
                      ),
                    ],
                  ),
                ),
                const _Heading('Watering rules (set in the firmware)'),
                const Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.water_drop_outlined),
                        title: Text('Starts watering'),
                        subtitle: Text('Below ${DeviceRules.soilStartPct}% soil moisture'),
                      ),
                      ListTile(
                        leading: Icon(Icons.check_circle_outline),
                        title: Text('Stops watering'),
                        subtitle: Text('At ${DeviceRules.soilStopPct}% soil moisture'),
                      ),
                      ListTile(
                        leading: Icon(Icons.shield_outlined),
                        title: Text('Safety limit'),
                        subtitle: Text(
                            '${DeviceRules.shotSeconds} s shots, 1 min apart, at most ${DeviceRules.maxShots} per cycle'),
                      ),
                    ],
                  ),
                ),
                const _Heading('Account'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Logged in as'),
                        subtitle: Text(email),
                      ),
                      ListTile(
                        leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                        title: Text('Log out',
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        onTap: () => _logout(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Plant Guard $appVersion',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
