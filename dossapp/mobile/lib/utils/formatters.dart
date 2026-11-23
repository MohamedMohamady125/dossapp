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
    return NumberFormat('#,##0', 'en').format(n.toInt());
  }
  return NumberFormat('#,##0.##', 'en').format(n);
}

/// The app's language follows `Intl.defaultLocale`, which main.dart keeps in
/// step with the language switch. Formatters have no BuildContext, so this
/// is how they know which words to use.
/// Arabic date formats come out with Arabic-Indic digits (٢٠٢٦). Egyptian
/// apps show 2026, and money is already in Western digits, so every date in
/// the app goes through this to keep one digit style on screen.
String westernDigits(String text) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  final out = StringBuffer();
  for (final ch in text.split('')) {
    final i = eastern.indexOf(ch);
    out.write(i >= 0 ? '$i' : ch);
  }
  return out.toString();
}

bool get _arabic => (Intl.defaultLocale ?? 'en').startsWith('ar');

/// Format money: 1012405.0 → "1,012,405 EGP", or "1,012,405 جنيه" in Arabic
String formatMoney(dynamic value) {
  return '${formatNumber(value)} ${_arabic ? 'جنيه' : 'EGP'}';
}

/// Format period: "2026-06" → "June 2026"
String formatPeriod(String period) {
  try {
    final parts = period.split('-');
    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    return westernDigits(DateFormat('MMMM yyyy').format(dt));
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
  if (!diff.isNegative && diff.inMinutes < 1) return _arabic ? 'دلوقتي' : 'Just now';
  if (!diff.isNegative && diff.inMinutes < 60) {
    final m = diff.inMinutes;
    if (_arabic) {
      return m == 1 ? 'من دقيقة' : m == 2 ? 'من دقيقتين' : m <= 10 ? 'من $m دقايق' : 'من $m دقيقة';
    }
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  final clock = westernDigits(DateFormat('HH:mm').format(t));
  if (sameDay) return _arabic ? 'النهارده $clock' : 'Today $clock';
  return westernDigits(DateFormat('d MMM, HH:mm').format(t));
}
