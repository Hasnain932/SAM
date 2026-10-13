part of '../main.dart';

// Small helpers for HH:mm times.

// ---- Time helpers ----
String hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? parseHhmm(String? s) {
  if (s == null) return null;
  final p = s.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String fmtHhmm(String? s) {
  final t = parseHhmm(s);
  if (t == null) return '';
  return DateFormat('hh:mm a').format(DateTime(2000, 1, 1, t.hour, t.minute));
}
