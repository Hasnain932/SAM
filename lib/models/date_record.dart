part of '../main.dart';

// One attendance record (one date + session).

// One attendance record (one date and session) of a subject.
class DateRecord {
  final String id; // yyyy-MM-dd_Session_n
  final Map<String, String> status; // roll -> 'P' / 'A'
  final Map<String, String> meta; // _time, _marked_by, _marked_by_name, _type
  DateRecord(this.id, this.status, this.meta);

  // Session type: 'class' or 'lab'. Old records have no _type, so they count as class.
  bool get isLab => meta['_type'] == kTypeLab;
}

// Session types stored in the '_type' meta field of an attendance record.
const String kTypeClass = 'class';
const String kTypeLab = 'lab';
String typeLabel(String type) => type == kTypeLab ? 'Lab Class' : 'Class';

// All attendance records of a subject in one read (sorted by id). Falls back to SQLite.
Future<List<DateRecord>> loadDateRecords(SemRef sem, String subject) async {
  final res = await _safeQuery(sem.dates(subject));
  List<DateRecord> out;
  if (res.docs.isNotEmpty || !res.fromCache) {
    out = res.docs.map((d) {
      final p = parseAttendance(d.data());
      return DateRecord(d.id, p.status, p.meta);
    }).toList();
  } else {
    out = await LocalDb.dateRecords(sem, subject);
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}
