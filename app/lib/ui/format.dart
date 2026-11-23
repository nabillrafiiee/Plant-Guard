import 'package:intl/intl.dart';

/// "just now", "12 s ago", "5 min ago", "3 h ago", "Yesterday 14:05", "21 Nov 14:05"
String timeAgo(DateTime time, {DateTime? now}) {
  now ??= DateTime.now();
  final diff = now.difference(time);
  if (diff.inSeconds < 5) return 'just now';
  if (diff.inSeconds < 60) return '${diff.inSeconds} s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 12) return '${diff.inHours} h ago';
  return dayAndTime(time, now: now);
}

String dayAndTime(DateTime time, {DateTime? now}) {
  now ??= DateTime.now();
  final hm = DateFormat.Hm().format(time);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) return 'Today $hm';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $hm';
  return '${DateFormat('d MMM').format(time)} $hm';
}

String dayHeading(DateTime time, {DateTime? now}) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('EEEE, d MMM').format(time);
}

String duration(int seconds) {
  final d = Duration(seconds: seconds);
  if (d.inDays > 0) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '$seconds s';
}

String wifiQuality(int rssi) {
  if (rssi >= -55) return 'Excellent ($rssi dBm)';
  if (rssi >= -67) return 'Good ($rssi dBm)';
  if (rssi >= -75) return 'Fair ($rssi dBm)';
  return 'Weak ($rssi dBm)';
}
