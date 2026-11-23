import 'package:intl/intl.dart';

/// Format a number with comma separators: 1012405 → "1,012,405"
String formatNumber(dynamic value) {
  if (value == null) return '0';
  final num n;
  if (value is num) {
    n = value;
  } else {
    n = num.tryParse(value.toString().replaceAll(',', '')) ?? 0;
  }
  if (n == n.toInt()) {
    return NumberFormat('#,##0').format(n.toInt());
  }
  return NumberFormat('#,##0.##').format(n);
}

/// Format money: 1012405.0 → "1,012,405 EGP"
String formatMoney(dynamic value) {
  return '${formatNumber(value)} EGP';
}

/// Format period: "2026-06" → "June 2026"
String formatPeriod(String period) {
  try {
    final parts = period.split('-');
    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    return DateFormat('MMMM yyyy').format(dt);
  } catch (_) {
    return period;
  }
}

/// "5 minutes ago", "Today 14:05" or "21 Nov, 14:05" from an ISO string or a
/// Unix timestamp in seconds. Returns the input unchanged if it can't be read
/// (Postel's Law: accept either form, show one clean format).
String formatWhen(dynamic value) {
  if (value == null) return '';
  final raw = value.toString();
  DateTime? t = DateTime.tryParse(raw);
  if (t == null) {
    final seconds = double.tryParse(raw);
    if (seconds != null) {
      t = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true);
    }
  }
  if (t == null) return raw;
  t = t.toLocal();
  final now = DateTime.now();
  final diff = now.difference(t);
  if (!diff.isNegative && diff.inMinutes < 1) return 'Just now';
  if (!diff.isNegative && diff.inMinutes < 60) {
    return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? 'Today ${DateFormat('HH:mm').format(t)}' : DateFormat('d MMM, HH:mm').format(t);
}
