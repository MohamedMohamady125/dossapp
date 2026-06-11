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
    return NumberFormat('#,###').format(n.toInt());
  }
  return NumberFormat('#,###.##').format(n);
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
