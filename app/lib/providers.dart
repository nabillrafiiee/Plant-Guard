import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'data/models.dart';
import 'data/plant_repository.dart';

final repositoryProvider = Provider<PlantRepository>(
  (ref) => PlantRepository(Supabase.instance.client, Env.deviceId),
);

// Live data. autoDispose: closed when you log out, reopened fresh on login.

final deviceStatusProvider = StreamProvider.autoDispose<DeviceStatus?>(
  (ref) => ref.watch(repositoryProvider).watchStatus(),
);

final deviceSettingsProvider = StreamProvider.autoDispose<DeviceSettings?>(
  (ref) => ref.watch(repositoryProvider).watchSettings(),
);

final eventsProvider = StreamProvider.autoDispose<List<PlantEvent>>(
  (ref) => ref.watch(repositoryProvider).watchEvents(),
);

final historyProvider =
    FutureProvider.autoDispose.family<History, HistoryRange>(
  (ref, range) => ref.watch(repositoryProvider).fetchHistory(range),
);

/// Ticks every 5 s so "updated 12 s ago" and the online dot stay current
/// even when no new data arrives.
final clockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 5), (_) => DateTime.now());
});

/// True while the device has sent a heartbeat in the last 30 s.
final isOnlineProvider = Provider.autoDispose<bool>((ref) {
  final status = ref.watch(deviceStatusProvider).value;
  final now = ref.watch(clockProvider).value ?? DateTime.now();
  return status != null && status.isOnlineAt(now, DeviceRules.offlineAfter);
});

/// Refetch everything, e.g. after the app comes back from the background.
void refreshAll(WidgetRef ref) {
  ref.invalidate(deviceStatusProvider);
  ref.invalidate(deviceSettingsProvider);
  ref.invalidate(eventsProvider);
  ref.invalidate(historyProvider);
}

// ---- Commands ----

enum Command { waterNow, resetFault }

class CommandResult {
  const CommandResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Runs a command and waits for the device to confirm it.
/// State = the command currently running (null = none).
class CommandController extends Notifier<Command?> {
  @override
  Command? build() => null;

  PlantRepository get _repo => ref.read(repositoryProvider);

  Future<CommandResult> waterNow() => _run(Command.waterNow, () async {
        final sentAt = await _repo.requestWaterNow();
        final reply = await _repo.waitForEvent(
          {'manual_shot', 'manual_blocked', 'manual_ignored'},
          after: sentAt.subtract(const Duration(seconds: 1)),
        );
        return switch (reply?.type) {
          'manual_shot' => const CommandResult(
              true, 'Watered: one ${DeviceRules.shotSeconds} s shot.'),
          'manual_blocked' =>
            const CommandResult(false, 'Blocked: the tank is low. Refill it first.'),
          'manual_ignored' => const CommandResult(
              false, 'Too soon after the last shot. Try again in a few seconds.'),
          _ => const CommandResult(
              false, "The device didn't answer. Is it online?"),
        };
      });

  Future<CommandResult> resetFault() => _run(Command.resetFault, () async {
        final sentAt = await _repo.requestResetFault();
        final reply = await _repo.waitForEvent(
          {'fault_cleared'},
          after: sentAt.subtract(const Duration(seconds: 1)),
        );
        return reply != null
            ? const CommandResult(true, 'Fault cleared. Auto watering resumes.')
            : const CommandResult(
                false, "The device didn't answer. Is it online?");
      });

  Future<CommandResult> _run(
    Command command,
    Future<CommandResult> Function() body,
  ) async {
    if (state != null) {
      return const CommandResult(false, 'Another command is still running.');
    }
    state = command;
    try {
      return await body();
    } on PostgrestException catch (e) {
      return CommandResult(false, "Couldn't send the command: ${e.message}");
    } catch (e) {
      return CommandResult(false, "Couldn't send the command: $e");
    } finally {
      if (ref.mounted) state = null;
    }
  }
}

final commandProvider =
    NotifierProvider<CommandController, Command?>(CommandController.new);
