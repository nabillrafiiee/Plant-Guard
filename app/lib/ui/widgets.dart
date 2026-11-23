import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Yes/no dialog: Material on Android, Cupertino-style on iOS.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final isApple = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };
  Widget action(String label, bool result, {bool primary = false}) => isApple
      ? CupertinoDialogAction(
          isDefaultAction: primary,
          onPressed: () => Navigator.of(context).pop(result),
          child: Text(label),
        )
      : TextButton(
          onPressed: () => Navigator.of(context).pop(result),
          child: Text(label),
        );

  final result = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(message),
      actions: [
        action('Cancel', false),
        action(confirmLabel, true, primary: true),
      ],
    ),
  );
  return result ?? false;
}

/// Centers page content and keeps it from getting too wide on tablets.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1100});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Green / grey dot with a label: device online or offline.
class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key, required this.online, this.label});

  final bool online;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final color = online ? const Color(0xFF2EB85C) : c.outline;
    return Semantics(
      label: online ? 'Device online' : 'Device offline',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: online
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label ?? (online ? 'Online' : 'Offline'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Coloured banner for warnings (offline, fault, tank low).
class AlertBanner extends StatelessWidget {
  const AlertBanner({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final bg = error ? c.errorContainer : c.secondaryContainer;
    final fg = error ? c.onErrorContainer : c.onSecondaryContainer;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall?.copyWith(color: fg)),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: text.bodySmall?.copyWith(color: fg)),
                ],
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Error message with a retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text("Couldn't load data", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

void showResult(BuildContext context, {required bool ok, required String message}) {
  final c = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.info, color: ok ? c.inversePrimary : c.onInverseSurface),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ));
}
