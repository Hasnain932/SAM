part of '../main.dart';

// Reads one attendance document.

// An attendance doc is {roll: 'P'/'A', ...} plus meta keys that start with '_':
// _time (HH:mm), _marked_by, _marked_by_name, _type ('class' / 'lab').
class ParsedAttendance {
  final Map<String, String> status;
  final Map<String, String> meta;
  ParsedAttendance(this.status, this.meta);
}

ParsedAttendance parseAttendance(Map<String, dynamic> data) {
  final status = <String, String>{};
  final meta = <String, String>{};
  data.forEach((k, v) {
    if (v is! String) return;
    if (k.startsWith('_')) {
      meta[k] = v;
    } else {
      status[k] = v;
    }
  });
  return ParsedAttendance(status, meta);
}
