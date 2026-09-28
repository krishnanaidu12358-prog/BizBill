import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);
final _date = DateFormat('dd MMM yyyy');
final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');

String money(num? v) => _money.format(v ?? 0);
String moneyShort(num? v) => (v ?? 0) >= 100000 ? _compact.format(v) : _money.format(v ?? 0);

String qty(num? v) {
  final d = (v ?? 0).toDouble();
  return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(3);
}

DateTime? _parse(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

String dateOf(String? iso) {
  final d = _parse(iso);
  return d == null ? '-' : _date.format(d);
}

String dateTimeOf(String? iso) {
  final d = _parse(iso);
  return d == null ? '-' : _dateTime.format(d);
}

String relative(String? iso) {
  final d = _parse(iso);
  if (d == null) return '-';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return _date.format(d);
}
