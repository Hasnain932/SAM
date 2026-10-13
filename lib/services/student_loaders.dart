part of '../main.dart';

// Loads student lists.

// ---- Student loaders ----
// Internal key of a student (called "roll" in the app). The first roll "12" gets
// "12", then "12__2", "12__3" and so on, so duplicates never overwrite each other.
// Screens and Excel show rollOf(key), i.e. "12".
String rollOf(String key) {
  final i = key.indexOf('__');
  return i < 0 ? key : key.substring(0, i);
}

String uniqueStudentKey(String roll, Iterable<String> existingKeys) {
  final taken = existingKeys.toSet();
  if (!taken.contains(roll)) return roll;
  var n = 2;
  while (taken.contains('${roll}__$n')) {
    n++;
  }
  return '${roll}__$n';
}

int compareStudentKeys(String a, String b) {
  final c = (int.tryParse(rollOf(a)) ?? 0).compareTo(int.tryParse(rollOf(b)) ?? 0);
  if (c != 0) return c;
  if (a.length != b.length) return a.length.compareTo(b.length);
  return a.compareTo(b);
}

List<Map<String, String>> _sortedStudents(Map<String, String> m) {
  final list = m.entries.map((e) => {'roll': e.key, 'name': e.value}).toList();
  list.sort((a, b) => compareStudentKeys(a['roll']!, b['roll']!));
  return list;
}

// Semester labels (custom names), used by the copy dialog.
Future<Map<String, String>> loadSemesterLabels(
    String deptId, String section) async {
  final res = await _safeQuery(FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .collection('sections')
      .doc(section)
      .collection('semesters'));
  final out = <String, String>{};
  for (final d in res.docs) {
    final l = (d.data()['label'] ?? '').toString();
    if (l.isNotEmpty) out[d.id] = l;
  }
  return out;
}

// Copies all students of semester [from] to [to] (same department and section).
// Nothing is overwritten: a clashing roll gets a new unique key. Returns the count.
Future<int> copyStudentsToSemester(SemRef from, SemRef to) async {
  final src = await loadSemesterStudents(from);
  if (src.isEmpty) return 0;
  final dest = await loadSemesterStudents(to);
  final taken = dest.map((s) => s['roll']!).toSet();
  for (final s in src) {
    final key = uniqueStudentKey(rollOf(s['roll']!), taken);
    taken.add(key);
    final name = s['name']!;
    unawaited(to.students
        .doc(key)
        .set({'roll': key, 'name': name}).catchError((_) {}));
    unawaited(LocalDb.upsertStudent(to, key, name));
  }
  return src.length;
}

// Master list of a semester (admin-managed). Reads Firestore first and falls back
// to the SQLite copy when nothing is cached.
Future<List<Map<String, String>>> loadSemesterStudents(SemRef sem) async {
  final res = await _safeQuery(sem.students);
  final m = <String, String>{};
  for (final d in res.docs) {
    final data = d.data();
    m[(data['roll'] ?? d.id).toString()] = (data['name'] ?? '').toString();
  }
  if (m.isEmpty && res.fromCache) {
    m.addAll(await LocalDb.students(sem));
  }
  return _sortedStudents(m);
}

// Subject-level overrides: roll -> {'name': ..., 'kind': 'extra' | 'hidden'}
Future<Map<String, Map<String, String>>> loadOverrides(
    SemRef sem, String subject) async {
  final res = await _safeQuery(sem.overrides(subject));
  final out = <String, Map<String, String>>{};
  for (final d in res.docs) {
    final data = d.data();
    out[(data['roll'] ?? d.id).toString()] = {
      'name': (data['name'] ?? '').toString(),
      'kind': (data['kind'] ?? '').toString(),
    };
  }
  if (out.isEmpty && res.fromCache) {
    out.addAll(await LocalDb.overrides(sem, subject));
  }
  return out;
}

// Actual student list of a subject = master list - hidden + extra.
Future<List<Map<String, String>>> loadSubjectStudents(
    SemRef sem, String subject) async {
  final masterF = loadSemesterStudents(sem);
  final ovF = loadOverrides(sem, subject);
  final master = await masterF;
  final ov = await ovF;
  final m = {for (final s in master) s['roll']!: s['name']!};
  ov.forEach((roll, o) {
    if (o['kind'] == 'hidden') {
      m.remove(roll);
    } else if (o['kind'] == 'extra') {
      m[roll] = o['name'] ?? '';
    }
  });
  return _sortedStudents(m);
}
