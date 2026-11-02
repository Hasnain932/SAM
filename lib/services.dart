part of 'main.dart';

// Firestore path helpers
// departments/{dept}/sections/{A-D}/semesters/{1-8}/
//     students/{key}      key = roll; duplicate rolls become roll__2, roll__3 ...
//     subjects/{name}                    (claimed_by, claimed_by_name)
//     subjects/{name}/overrides/{roll}   (subject-level add / soft-remove)
//     attendance/{subject}/dates/{date_Session_n}
class SemRef {
  final String deptId;
  final String section;
  final String semester;
  const SemRef(this.deptId, this.section, this.semester);

  DocumentReference<Map<String, dynamic>> get doc => FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .collection('sections')
      .doc(section)
      .collection('semesters')
      .doc(semester);

  CollectionReference<Map<String, dynamic>> get students =>
      doc.collection('students');
  CollectionReference<Map<String, dynamic>> get subjects =>
      doc.collection('subjects');
  DocumentReference<Map<String, dynamic>> subjectDoc(String subject) =>
      subjects.doc(subject);
  CollectionReference<Map<String, dynamic>> overrides(String subject) =>
      subjectDoc(subject).collection('overrides');
  CollectionReference<Map<String, dynamic>> dates(String subject) =>
      doc.collection('attendance').doc(subject).collection('dates');

  String claimKey(String subject) => '$deptId|$section|$semester|$subject';
}

String defaultSemesterLabel(String semesterId) => 'Semester $semesterId';

// ---- Sections / semesters added by the admin ----
// Both lists live on the department document itself (the same document the
// admin already edits when renaming), so no new Firestore path is needed:
//   departments/{dept}.extra_sections  = ['E', ...]
//   departments/{dept}.extra_semesters = ['E|9', ...]   (section|semester)
// The built-in ones (A-D and 1-8) always stay.
DocumentReference<Map<String, dynamic>> deptDocRef(String deptId) =>
    FirebaseFirestore.instance.collection('departments').doc(deptId);

DocumentReference<Map<String, dynamic>> sectionDocRef(
        String deptId, String section) =>
    deptDocRef(deptId).collection('sections').doc(section);

List<String> _mergeIds(List<String> base, dynamic extra) {
  final out = <String>[...base];
  if (extra is Iterable) {
    final more = extra
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty && !out.contains(e))
        .toList();
    more.sort((a, b) {
      final na = int.tryParse(a), nb = int.tryParse(b);
      if (na != null && nb != null) return na.compareTo(nb);
      return a.compareTo(b);
    });
    out.addAll(more);
  }
  return out;
}

List<String> sectionsFrom(Map<String, dynamic>? deptData) =>
    _mergeIds(kSections, deptData?['extra_sections']);

List<String> semestersFrom(Map<String, dynamic>? deptData, String section) {
  final raw = deptData?['extra_semesters'];
  final mine = <String>[];
  if (raw is Iterable) {
    final prefix = '$section|';
    for (final e in raw) {
      final v = e.toString();
      if (v.startsWith(prefix) && v.length > prefix.length) {
        mine.add(v.substring(prefix.length));
      }
    }
  }
  return _mergeIds(kSemesterIds, mine);
}

Future<List<String>> loadSemesterIds(String deptId, String section) async {
  final snap = await safeGetDocOrNull(deptDocRef(deptId));
  return semestersFrom(snap?.data(), section);
}

CollectionReference<Map<String, dynamic>> teacherClaimsRef(String teacherId) =>
    FirebaseFirestore.instance
        .collection('teachers')
        .doc(teacherId)
        .collection('claims');

DocumentReference<Map<String, dynamic>> permissionsRef() =>
    FirebaseFirestore.instance.collection('settings').doc('permissions');

// ---- Teacher permissions (settings/permissions) ----
// kPermMaster ON: teachers can do everything. OFF: each permission below applies
// on its own. A missing field means "not allowed".
const String kPermMaster = 'teachers_unrestricted';
const String kPermAnytime = 'perm_anytime'; // mark outside the 20-minute window
const String kPermChangeTime = 'perm_change_time'; // pick the class time
const String kPermChangeDate = 'perm_change_date'; // pick other / past dates
// Edit also covers deleting records. Class <-> Lab and Mid <-> Final conversion
// are always allowed (admin and teachers), so they have no permission.
const String kPermEdit = 'perm_edit'; // edit AND delete existing records
const List<String> kDetailedPerms = [
  kPermAnytime,
  kPermChangeTime,
  kPermChangeDate,
  kPermEdit,
];

class TeacherPerms {
  final bool master;
  final bool anytime;
  final bool changeTime;
  final bool changeDate;
  final bool edit; // edit and delete existing records
  const TeacherPerms({
    this.master = false,
    this.anytime = false,
    this.changeTime = false,
    this.changeDate = false,
    this.edit = false,
  });

  static const TeacherPerms none = TeacherPerms();

  factory TeacherPerms.from(Map<String, dynamic>? d) {
    if (d == null) return none;
    return TeacherPerms(
      master: d[kPermMaster] == true,
      anytime: d[kPermAnytime] == true,
      changeTime: d[kPermChangeTime] == true,
      changeDate: d[kPermChangeDate] == true,
      edit: d[kPermEdit] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TeacherPerms &&
      other.master == master &&
      other.anytime == anytime &&
      other.changeTime == changeTime &&
      other.changeDate == changeDate &&
      other.edit == edit;

  @override
  int get hashCode =>
      Object.hash(master, anytime, changeTime, changeDate, edit);
}

// ---- Old paths (from before sections existed), used only for migration and
// delete ----
CollectionReference<Map<String, dynamic>> legacyStudentsRef(String deptId) =>
    FirebaseFirestore.instance
        .collection('departments')
        .doc(deptId)
        .collection('students');

CollectionReference<Map<String, dynamic>> legacySubjectsRef(String deptId) =>
    FirebaseFirestore.instance
        .collection('departments')
        .doc(deptId)
        .collection('subjects');

CollectionReference<Map<String, dynamic>> legacyDatesRef(
    String deptId, String subjectName) {
  if (deptId == kSoftwareEngineeringDeptId) {
    return FirebaseFirestore.instance
        .collection('attendance')
        .doc(subjectName)
        .collection('dates');
  }
  return FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .collection('attendance')
      .doc(subjectName)
      .collection('dates');
}

// Offline-safe read helpers
const Duration _kNetworkTimeout = Duration(seconds: 2);
// Web: don't make screens wait for the server. After this time, show the cache
// (the server read keeps running and refreshes it).
const Duration _kReadTimeout =
    kIsWeb ? Duration(milliseconds: 900) : _kNetworkTimeout;

// Wi-Fi connected doesn't always mean the internet works. _netState() adds a quick
// DNS check (cached for a few seconds). When offline, go straight to the cache
// instead of waiting for a timeout, which caused endless loading.
enum _Net { none, unreachable, reachable }

_Net? _netCache;
DateTime _netCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

void resetNetCache() {
  _netCache = null;
}

Future<_Net> _netState() async {
  bool linked = true;
  try {
    final r = await Connectivity().checkConnectivity();
    linked = !r.contains(ConnectivityResult.none);
  } catch (e) {
    debugPrint('services.dart:213: $e');
  }
  if (!linked) {
    _netCache = _Net.none;
    _netCacheAt = DateTime.now();
    return _Net.none;
  }
  final cached = _netCache;
  if (cached != null && cached != _Net.none) {
    final ttl = cached == _Net.reachable
        ? const Duration(seconds: 10)
        : const Duration(seconds: 4);
    if (DateTime.now().difference(_netCacheAt) < ttl) return cached;
  }
  // InternetAddress.lookup isn't available on web; the check above is enough.
  if (kIsWeb) {
    _netCache = _Net.reachable;
    _netCacheAt = DateTime.now();
    return _Net.reachable;
  }
  _Net result;
  try {
    final res = await InternetAddress.lookup('firestore.googleapis.com')
        .timeout(const Duration(seconds: 3));
    result = res.isNotEmpty ? _Net.reachable : _Net.unreachable;
  } catch (_) {
    result = _Net.unreachable;
  }
  _netCache = result;
  _netCacheAt = DateTime.now();
  return result;
}

Future<bool> _isOnline() async {
  try {
    final r = await Connectivity().checkConnectivity();
    return !r.contains(ConnectivityResult.none);
  } catch (_) {
    return true;
  }
}

Future<DocumentSnapshot<Map<String, dynamic>>> safeGetDoc(
    DocumentReference<Map<String, dynamic>> ref) async {
  const cacheOnly = GetOptions(source: Source.cache);
  final net = await _netState();
  if (net == _Net.reachable && FirebaseAuth.instance.currentUser == null) {
    await AppSession.ensureSignedIn();
  }
  if (net == _Net.reachable) {
    final server = ref.get();
    server.ignore();
    try {
      return await server.timeout(_kReadTimeout);
    } catch (e) {
      debugPrint('services.dart:266: $e');
    }
    try {
      return await ref.get(cacheOnly);
    } catch (_) {
      // Not cached yet: give the server a little more time.
      return server.timeout(const Duration(seconds: 8));
    }
  }
  try {
    final c = await ref.get(cacheOnly);
    if (c.exists || net == _Net.none) return c;
  } catch (_) {
    if (net == _Net.none) rethrow;
  }
  return ref.get().timeout(_kNetworkTimeout);
}

Future<DocumentSnapshot<Map<String, dynamic>>?> safeGetDocOrNull(
    DocumentReference<Map<String, dynamic>> ref) async {
  try {
    return await safeGetDoc(ref);
  } catch (_) {
    return null;
  }
}

Future<QuerySnapshot<Map<String, dynamic>>> safeGetQuery(
    Query<Map<String, dynamic>> query) async {
  const cacheOnly = GetOptions(source: Source.cache);
  final net = await _netState();
  if (net == _Net.reachable && FirebaseAuth.instance.currentUser == null) {
    await AppSession.ensureSignedIn();
  }
  if (net == _Net.reachable) {
    final server = query.get();
    server.ignore();
    try {
      return await server.timeout(_kReadTimeout);
    } catch (e) {
      debugPrint('services.dart:304: $e');
    }
    final cached = await query.get(cacheOnly);
    if (cached.docs.isNotEmpty) return cached;
    // Nothing cached: wait a bit longer for the server instead of showing an empty list.
    try {
      return await server.timeout(const Duration(seconds: 8));
    } catch (_) {
      return cached;
    }
  }
  final cached = await query.get(cacheOnly);
  if (cached.docs.isNotEmpty || net == _Net.none) return cached;
  try {
    return await query.get().timeout(_kNetworkTimeout);
  } catch (_) {
    return cached;
  }
}

class _QRes {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool fromCache;
  const _QRes(this.docs, this.fromCache);
}

// Never throws. On any failure it returns an empty result marked as from cache.
Future<_QRes> _safeQuery(Query<Map<String, dynamic>> query) async {
  try {
    final snap = await safeGetQuery(query);
    return _QRes(snap.docs, snap.metadata.isFromCache);
  } catch (_) {
    return const _QRes([], true);
  }
}

// ---- Reliable writes ----
// saved  = server confirmed the write (online)
// queued = offline or slow: Firestore keeps it on the device and sends it later
// failed = server refused it (for example Firestore rules)
enum SaveResult { saved, queued, failed }

Future<SaveResult> fsWrite(Future<void> write, {String what = 'write'}) async {
  write.ignore(); // errors are handled below, never left unhandled
  final net = await _netState();
  if (net != _Net.reachable) {
    unawaited(write.then((_) {},
        onError: (Object e) => debugPrint('Firestore $what error: $e')));
    return SaveResult.queued;
  }
  try {
    await write.timeout(const Duration(seconds: 10));
    return SaveResult.saved;
  } on TimeoutException {
    debugPrint('Firestore $what: slow, still sending in the background');
    return SaveResult.queued;
  } catch (e) {
    debugPrint('Firestore $what error: $e');
    return SaveResult.failed;
  }
}

Future<SaveResult> fsWriteAll(List<Future<void>> writes,
    {String what = 'write'}) {
  if (writes.isEmpty) return Future.value(SaveResult.saved);
  return fsWrite(Future.wait(writes).then((_) {}), what: what);
}

// After a student write: when the server confirmed it, refresh the SQLite copy
// from the server right away; when it failed, tell the user.
Future<void> finishStudentWrite(
    BuildContext? context, SemRef sem, SaveResult res,
    {String? subject}) async {
  if (res == SaveResult.saved) {
    await LocalDb.refreshSemesterStudents(sem);
    if (subject != null) await LocalDb.refreshSubjectOverrides(sem, subject);
  } else if (res == SaveResult.failed && context != null && context.mounted) {
    showSnack(context,
        'Could not save to the server. Check Firestore rules and try again.',
        color: kAbsent);
  }
}

// Cache-first live query for StreamBuilders: device cache first, then live updates.
// A live-listener error (for example "permission-denied" right after login,
// before the anonymous sign-in has finished) is never passed to the screen:
// that used to wipe the list. The last good data stays visible and the
// listener is simply started again after a short delay.
Stream<QuerySnapshot<Map<String, dynamic>>> liveQuery(
    Query<Map<String, dynamic>> q) {
  late final StreamController<QuerySnapshot<Map<String, dynamic>>> ctrl;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
  Timer? retryTimer;
  bool gotLive = false;
  bool cancelled = false;
  int retries = 0;

  void listen() {
    if (cancelled) return;
    sub?.cancel();
    sub = q.snapshots().listen(
      (snap) {
        gotLive = true;
        retries = 0;
        if (!cancelled && !ctrl.isClosed) ctrl.add(snap);
      },
      onError: (Object e, StackTrace st) {
        debugPrint('liveQuery error (will retry): $e');
        if (cancelled || retries >= 12) return;
        retries++;
        final wait = Duration(seconds: retries < 5 ? retries : 5);
        retryTimer?.cancel();
        retryTimer = Timer(wait, listen);
      },
      cancelOnError: true,
    );
  }

  ctrl = StreamController<QuerySnapshot<Map<String, dynamic>>>(
    onListen: () {
      listen();
      unawaited(() async {
        try {
          final cached = await q.get(const GetOptions(source: Source.cache));
          if (gotLive || cancelled) return;
          if (cached.docs.isNotEmpty) {
            ctrl.add(cached);
            return;
          }
          // Empty cache: give the live stream a moment, then show the empty result.
          await Future.delayed(const Duration(milliseconds: 1500));
          if (!gotLive && !cancelled) ctrl.add(cached);
        } catch (e) {
          debugPrint('services.dart:435: $e');
        }
      }());
    },
    onCancel: () async {
      cancelled = true;
      retryTimer?.cancel();
      await sub?.cancel();
    },
  );
  return ctrl.stream;
}

// An attendance doc is {roll: 'P'/'A', ...} plus meta keys that start with '_':
// _time (HH:mm), _marked_by, _marked_by_name, _type ('class' / 'lab').
class ParsedAttendance {
  final Map<String, String> status;
  final Map<String, String> meta;
  ParsedAttendance(this.status, this.meta);
}

// Every write to an attendance document ('dates' collection) also stores the server
// time in this field. The local database uses it to download only the sessions that
// changed since the last sync (delta sync). parseAttendance ignores it (not a String).
const String kUpdatedField = '_updated';

Map<String, dynamic> stamped(Map<String, dynamic> data) =>
    {...data, kUpdatedField: FieldValue.serverTimestamp()};

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

List<Map<String, String>> _sortedStudents(Map<String, String> m,
    [Map<String, String>? fathers]) {
  final list = m.entries
      .map((e) => {
            'roll': e.key,
            'name': e.value,
            'father': fathers?[e.key] ?? '',
          })
      .toList();
  list.sort((a, b) => compareStudentKeys(a['roll'] ?? '', (b['roll'] ?? '')));
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
// When the admin copies, the students' logins (ID and key) move along to [to].
Future<({int copied, int logins})> copyStudentsToSemester(
    SemRef from, SemRef to) async {
  final src = await loadSemesterStudents(from);
  if (src.isEmpty) return (copied: 0, logins: 0);
  final dest = await loadSemesterStudents(to);
  final taken = dest.map((s) => (s['roll'] ?? '')).toSet();
  final keyMap = <String, String>{};
  for (final s in src) {
    final key = uniqueStudentKey(rollOf(s['roll'] ?? ''), taken);
    taken.add(key);
    keyMap[s['roll'] ?? ''] = key;
    final name = (s['name'] ?? '');
    final father = s['father'] ?? '';
    unawaited(to.students
        .doc(key)
        .set({'roll': key, 'name': name, 'father': father}).catchError(
            (Object e) => debugPrint('Copy student error: $e')));
    unawaited(LocalDb.upsertStudent(to, key, name, father));
  }
  var moved = await moveStudentLogins(from, to, keyMap);
  // Safety net: if some logins did not move (e.g. a weak connection), try to
  // bring them over by roll + name, so the admin never needs a manual sync.
  if (moved < keyMap.length) {
    try {
      moved += await adoptStudentLogins(to);
    } catch (e) {
      debugPrint('auto sync after copy failed: $e');
    }
  }
  return (copied: src.length, logins: moved);
}

// Master list of a semester (admin-managed). Reads Firestore first and falls back
// to the SQLite copy when nothing is cached.
Future<List<Map<String, String>>> loadSemesterStudents(SemRef sem) async {
  final res = await _safeQuery(sem.students);
  final m = <String, String>{};
  final f = <String, String>{};
  for (final d in res.docs) {
    final data = d.data();
    final k = (data['roll'] ?? d.id).toString();
    m[k] = (data['name'] ?? '').toString();
    f[k] = (data['father'] ?? '').toString();
  }
  if (m.isEmpty && res.fromCache) {
    m.addAll(await LocalDb.students(sem));
    f.addAll(await LocalDb.fathers(sem));
  }
  return _sortedStudents(m, f);
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
      'father': (data['father'] ?? '').toString(),
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
  final m = {for (final s in master) (s['roll'] ?? ''): (s['name'] ?? '')};
  final f = {for (final s in master) (s['roll'] ?? ''): s['father'] ?? ''};
  ov.forEach((roll, o) {
    if (o['kind'] == 'hidden') {
      m.remove(roll);
      f.remove(roll);
    } else if (o['kind'] == 'extra') {
      m[roll] = o['name'] ?? '';
      f[roll] = o['father'] ?? '';
    }
  });
  return _sortedStudents(m, f);
}

// One attendance record (one date and session) of a subject.
class DateRecord {
  final String id; // yyyy-MM-dd_Session_n
  final Map<String, String> status; // roll -> 'P' / 'A'
  final Map<String, String> meta; // _time, _marked_by, _marked_by_name, _type
  DateRecord(this.id, this.status, this.meta);

  // Session type: 'class' or 'lab'. Old records have no _type, so they count as class.
  bool get isLab => meta['_type'] == kTypeLab;

  // Exam phase: 'mid' or 'final'. Old records have no _phase, so they count as Mid.
  bool get isFinal => meta['_phase'] == kPhaseFinal;
  bool get isMid => !isFinal;
}

// Exam phases stored in the '_phase' meta field of an attendance record.
const String kPhaseMid = 'mid';
const String kPhaseFinal = 'final';
String phaseLabel(String phase) => phase == kPhaseFinal ? 'Final' : 'Mid';

// ---- Current exam phase of a subject (Mid / Final button) ----
// Stored on the subject document (field exam_phase) and also locally, so it
// works offline and survives app restarts. Missing = Mid.
String _phasePrefKey(SemRef s, String subject) =>
    'exam_phase|${s.deptId}|${s.section}|${s.semester}|$subject';

Future<String> readLocalSubjectPhase(SemRef s, String subject) async {
  try {
    final p = await SharedPreferences.getInstance();
    return p.getString(_phasePrefKey(s, subject)) == kPhaseFinal
        ? kPhaseFinal
        : kPhaseMid;
  } catch (_) {
    return kPhaseMid;
  }
}

Future<void> cacheSubjectPhase(SemRef s, String subject, String phase) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_phasePrefKey(s, subject), phase);
  } catch (e) {
    debugPrint('services.dart:688: $e');
  }
}

// Server value of the subject phase (null if offline / not set).
Future<String?> fetchServerSubjectPhase(SemRef s, String subject) async {
  try {
    final d =
        await s.subjectDoc(subject).get().timeout(const Duration(seconds: 4));
    final v = d.data()?['exam_phase'];
    if (v == kPhaseFinal || v == kPhaseMid) return v as String;
  } catch (e) {
    debugPrint('services.dart:698: $e');
  }
  return null;
}

Future<void> saveSubjectPhase(SemRef s, String subject, String phase) async {
  await cacheSubjectPhase(s, subject, phase);
  // Not awaited: this never completes while offline.
  unawaited(s
      .subjectDoc(subject)
      .set({'exam_phase': phase}, SetOptions(merge: true))
      .catchError((_) {}));
}

// ---- Admin's Mid / Final announcement ----
// The admin can announce either phase. Teachers whose subject is NOT in the
// announced phase see a reminder and cannot take new attendance until they switch.
// Stored as the field 'announced_phase_v2' of settings/permissions (the document
// every teacher screen already listens to) and mirrored locally, so the reminder
// also shows offline and after an app restart. Missing = nothing announced (null).
// (A new field name is used on purpose: the old 'announced_phase' field meant
// "Mid = nothing to do", and must not trigger "switch back to Mid" reminders.)
const String kAnnouncedPhaseField = 'announced_phase_v2';
const String _kAnnouncedPrefKey = 'announced_exam_phase_v2';

String? announcedPhaseFrom(Map<String, dynamic>? d) {
  final v = d?[kAnnouncedPhaseField];
  return (v == kPhaseFinal || v == kPhaseMid) ? v as String : null;
}

Future<String?> readLocalAnnouncedPhase() async {
  try {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kAnnouncedPrefKey);
    return (v == kPhaseFinal || v == kPhaseMid) ? v : null;
  } catch (_) {
    return null;
  }
}

Future<void> cacheAnnouncedPhase(String? phase) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (phase == null) {
      await p.remove(_kAnnouncedPrefKey);
    } else {
      await p.setString(_kAnnouncedPrefKey, phase);
    }
  } catch (e) {
    debugPrint('services.dart:745: $e');
  }
}

Future<void> saveAnnouncedPhase(String phase) async {
  await cacheAnnouncedPhase(phase);
  // Not awaited: this never completes while offline.
  unawaited(permissionsRef()
      .set({kAnnouncedPhaseField: phase}, SetOptions(merge: true))
      .catchError((_) {}));
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

// ---- Attendance summary: one small document per student ----
// attendance_summary/{dept_section_sem_roll}
//   subjects: { SUBJECT: { p, a, t, e: ['P|01 Oct · S2', 'A|02 Oct · S1 · Lab', ...] } }
// Students read only this one document. Teachers/admin keep it updated whenever
// attendance is saved, edited or deleted. A subject missing from the summary is
// loaded the old way by the student app, so nothing breaks before a rebuild.
String attLabel(DateRecord r) =>
    '${prettySession(r.id)}${r.isLab ? ' · Lab' : ''}';

DocumentReference<Map<String, dynamic>> summaryRef(SemRef sem, String roll) =>
    FirebaseFirestore.instance.collection('attendance_summary').doc(
        '${sem.deptId}_${sem.section}_${sem.semester}_$roll'
            .replaceAll('/', '-'));

Map<String, dynamic> _summaryOf(List<DateRecord> recs, String roll) {
  var p = 0, a = 0;
  final e = <String>[];
  for (final r in recs) {
    final st = r.status[roll];
    if (st == 'P') {
      p++;
      e.add('P|${attLabel(r)}');
    } else if (st == 'A') {
      a++;
      e.add('A|${attLabel(r)}');
    }
  }
  return {'p': p, 'a': a, 't': recs.length, 'e': e};
}

// Counts failures during a summary rebuild, so the button can show an error.
int summaryRebuildFails = 0;

// Writes the subject's summary for every given student (rolls), 400 per batch.
// Uses only data already in memory: no reads. Wrap in unawaited() when offline-safe.
Future<void> pushAttendanceSummaries(SemRef sem, String subject,
    List<DateRecord> recs, Iterable<String> rolls) async {
  try {
    final list = rolls.where((r) => r.isNotEmpty).toList();
    final commits = <Future<void>>[];
    for (var i = 0; i < list.length; i += 400) {
      final b = FirebaseFirestore.instance.batch();
      for (final roll in list.skip(i).take(400)) {
        b.set(
            summaryRef(sem, roll),
            {
              'subjects': {subject: _summaryOf(recs, roll)}
            },
            SetOptions(merge: true));
      }
      commits.add(b.commit().catchError((_) {
        summaryRebuildFails++;
      }));
    }
    await Future.wait(commits);
  } catch (e) {
    summaryRebuildFails++;
    debugPrint('summary push failed: $e');
  }
}

// A student removed from a subject: drop that subject from their summary.
void dropSubjectFromSummary(SemRef sem, String subject, String roll) {
  unawaited(summaryRef(sem, roll)
      .set({
        'subjects': {subject: FieldValue.delete()}
      }, SetOptions(merge: true))
      .catchError((_) {}));
}

// Removes one subject from the summaries of many students (batched, no reads).
Future<void> dropSubjectFromSummaries(
    SemRef sem, String subject, Iterable<String> rolls) async {
  try {
    final list = rolls.where((r) => r.isNotEmpty).toList();
    for (var i = 0; i < list.length; i += 400) {
      final b = FirebaseFirestore.instance.batch();
      for (final roll in list.skip(i).take(400)) {
        b.set(
            summaryRef(sem, roll),
            {
              'subjects': {subject: FieldValue.delete()}
            },
            SetOptions(merge: true));
      }
      unawaited(b.commit().catchError((_) {}));
    }
  } catch (e) {
    debugPrint('summary drop failed: $e');
  }
}

// For admin screens that change records without having them all in memory.
// `tweak` applies the just-made change to the freshly read list.
Future<void> refreshSubjectSummary(SemRef sem, String subject,
    {void Function(List<DateRecord> recs)? tweak}) async {
  try {
    final recs = await loadDateRecords(sem, subject);
    final hadRecords = recs.isNotEmpty;
    tweak?.call(recs);
    // No attendance records at all (for example after "Delete all attendance"):
    // keep the saved summaries as they are. Writing now would reset every
    // student's summary of this subject to zero.
    if (!hadRecords && recs.isEmpty) return;
    final st = await loadSubjectStudents(sem, subject);
    await pushAttendanceSummaries(
        sem, subject, recs, st.map((x) => x['roll'] ?? ''));
  } catch (e) {
    debugPrint('summary refresh failed: $e');
  }
}

// One-time rebuild for old data (admin button on the Subjects screen).
Future<int> rebuildSemesterSummaries(SemRef sem) async {
  final subs = await _safeQuery(sem.subjects);
  final master = await loadSemesterStudents(sem);
  var n = 0;
  for (final d in subs.docs) {
    try {
      final recs = await loadDateRecords(sem, d.id);
      // No raw attendance (deleted after summarizing): keep the existing
      // summaries, do not overwrite them with zeros.
      if (recs.isEmpty) continue;
      final ov = await loadOverrides(sem, d.id);
      final rolls = <String>{for (final m in master) m['roll'] ?? ''};
      ov.forEach((roll, o) {
        if (o['kind'] == 'hidden') {
          rolls.remove(roll);
        } else if (o['kind'] == 'extra') {
          rolls.add(roll);
        }
      });
      await pushAttendanceSummaries(sem, d.id, recs, rolls)
          .timeout(const Duration(seconds: 30));
      n++;
    } catch (e) {
      summaryRebuildFails++;
      debugPrint('rebuild ${d.id} failed: $e');
    }
  }
  return n;
}

// After "Delete all attendance": removes every student's attendance summary too,
// so a new semester starts clean and new students (who may get the roll numbers
// of old students) never see old attendance. Reads each summary document once.
// Safe to run again if it stops halfway.
Future<void> deleteAllSummaries() async {
  final fs = FirebaseFirestore.instance;
  final snap = await fs
      .collection('attendance_summary')
      .get()
      .timeout(const Duration(seconds: 60));
  if (snap.metadata.isFromCache) throw Exception('Server not reachable');
  final docs = snap.docs;
  for (var i = 0; i < docs.length; i += 400) {
    final b = fs.batch();
    for (final d in docs.skip(i).take(400)) {
      b.delete(d.reference);
    }
    await b.commit().timeout(const Duration(seconds: 30));
  }
}

// Rebuild for EVERY department, section and semester in one tap (admin).
// Returns the number of subjects rebuilt in total.
Future<int> rebuildAllSummaries() async {
  var total = 0;
  try {
    final depts = await _safeQuery(
        FirebaseFirestore.instance.collection('departments'));
    for (final d in depts.docs) {
      if (d.id == kHiddenAdminDeptName) continue;
      final data = d.data();
      for (final sec in sectionsFrom(data)) {
        for (final sid in semestersFrom(data, sec)) {
          try {
            total += await rebuildSemesterSummaries(SemRef(d.id, sec, sid));
          } catch (e) {
            summaryRebuildFails++;
            debugPrint('rebuild ${d.id}/$sec/$sid failed: $e');
          }
        }
      }
    }
  } catch (e) {
    summaryRebuildFails++;
    debugPrint('rebuild all failed: $e');
  }
  return total;
}

// Claim / unclaim a subject (teacher)
class ClaimException implements Exception {
  final String message;
  ClaimException(this.message);
}

Future<void> claimSubject(
    BuildContext context, SemRef sem, String subject) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Claim this subject?'),
      content: Text(
          "'$subject' will be assigned to you. No other teacher can claim it until you release it."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Claim')),
      ],
    ),
  );
  if (confirm != true) return;
  if (!context.mounted) return;

  // Needs internet so the server can stop two teachers claiming the same subject.
  if ((await _netState()) != _Net.reachable) {
    if (context.mounted) {
      showSnack(context, 'An internet connection is required to claim a subject.');
    }
    return;
  }

  // The rules need request.auth != null. Make sure a user exists first.
  if (!await AppSession.ensureSignedIn()) {
    if (context.mounted) {
      showSnack(context,
          'Could not sign in to the server (${AppSession.lastAuthError}). Check that Anonymous sign-in is enabled in Firebase Authentication.');
    }
    return;
  }

  try {
    final subRef = sem.subjectDoc(subject);
    final claimRef =
        teacherClaimsRef(AppSession.teacherId).doc(sem.claimKey(subject));
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(subRef);
      if (!snap.exists) throw ClaimException('This subject no longer exists.');
      final cb = (snap.data()?['claimed_by'] ?? '').toString();
      if (cb.isNotEmpty && cb != AppSession.teacherId) {
        throw ClaimException(
            'This subject has already been claimed by ${(snap.data()?['claimed_by_name'] ?? 'another teacher').toString()}.');
      }
      tx.update(subRef, {
        'claimed_by': AppSession.teacherId,
        'claimed_by_name': AppSession.teacherName,
      });
      tx.set(claimRef, {
        'dept': sem.deptId,
        'section': sem.section,
        'semester': sem.semester,
        'subject': subject,
      });
    }).timeout(const Duration(seconds: 15));

    unawaited(LocalDb.setSubjectClaim(
        sem, subject, AppSession.teacherId, AppSession.teacherName));
    unawaited(LocalDb.upsertClaim(AppSession.teacherId, sem, subject));
    if (context.mounted) showSnack(context, "You claimed '$subject'");
  } on ClaimException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  } on FirebaseException catch (e) {
    debugPrint('claimSubject failed: ${e.code} ${e.message}');
    String msg;
    switch (e.code) {
      case 'permission-denied':
      case 'unauthenticated':
        msg =
            'The server refused this action (${e.code}). Please log out, log in again and retry. If it continues, check the Firestore rules.';
        break;
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        msg = 'Could not reach the server. Please check your internet and try again.';
        break;
      case 'aborted':
      case 'failed-precondition':
        msg = 'Someone else changed this subject at the same time. Please try again.';
        break;
      default:
        msg = 'Could not claim the subject (${e.code}). Please try again.';
    }
    if (context.mounted) showSnack(context, msg);
  } on TimeoutException {
    if (context.mounted) {
      showSnack(context, 'The server took too long. Please check your internet and try again.');
    }
  } catch (e) {
    debugPrint('claimSubject failed: $e');
    if (context.mounted) {
      showSnack(context, 'Could not claim the subject (${e.runtimeType}). Please try again.');
    }
  }
}

Future<void> unclaimSubject(
    BuildContext context, SemRef sem, String subject) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Leave this subject?'),
      content: Text(
          "'$subject' will become available to all teachers again. Existing attendance history will not be deleted."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: kAbsent))),
      ],
    ),
  );
  if (confirm != true) return;

  unawaited(sem.subjectDoc(subject).update({
    'claimed_by': FieldValue.delete(),
    'claimed_by_name': FieldValue.delete(),
  }).catchError((_) {}));
  unawaited(teacherClaimsRef(AppSession.teacherId)
      .doc(sem.claimKey(subject))
      .delete()
      .catchError((_) {}));
  unawaited(LocalDb.setSubjectClaim(sem, subject, '', ''));
  unawaited(LocalDb.deleteClaim(AppSession.teacherId, sem, subject));
  if (context.mounted) showSnack(context, "You left '$subject'");
}

// Admin deletes a teacher: free every subject that teacher had claimed, so the
// subject list no longer shows "Taken by <deleted teacher>". Call this BEFORE the
// teacher document is deleted. Subjects are found from the teacher's claims list
// (Firestore) and from the local database, so a missing claim record on one side
// does not leave a name behind.
Future<void> releaseAllClaimsOfTeacher(String teacherId) async {
  if (teacherId.isEmpty) return;
  // dept|section|semester|subject -> entry
  final found = <String, Map<String, String>>{};
  void add(String dept, String section, String semester, String subject) {
    if (dept.isEmpty || section.isEmpty || semester.isEmpty || subject.isEmpty) {
      return;
    }
    found['$dept|$section|$semester|$subject'] = {
      'dept': dept,
      'section': section,
      'semester': semester,
      'subject': subject,
    };
  }

  final claimRefs = <DocumentReference<Map<String, dynamic>>>[];
  try {
    final snap = await safeGetQuery(teacherClaimsRef(teacherId))
        .timeout(const Duration(seconds: 10));
    for (final d in snap.docs) {
      claimRefs.add(d.reference);
      final c = d.data();
      add(
        (c['dept'] ?? '').toString(),
        (c['section'] ?? '').toString(),
        (c['semester'] ?? '').toString(),
        (c['subject'] ?? '').toString(),
      );
    }
  } catch (e) {
    debugPrint('services.dart:1146: $e');
  }
  try {
    for (final c in await LocalDb.claimsOf(teacherId)) {
      add(c['dept'] ?? '', c['section'] ?? '', c['semester'] ?? '',
          c['subject'] ?? '');
    }
  } catch (e) {
    debugPrint('services.dart:1152: $e');
  }

  for (final e in found.values) {
    final sem = SemRef(e['dept']!, e['section']!, e['semester']!);
    final subject = e['subject']!;
    final snap = await safeGetDocOrNull(sem.subjectDoc(subject));
    // Subject deleted already, or now claimed by someone else: leave it alone.
    if (snap != null) {
      if (!snap.exists) continue;
      final cb = (snap.data()?['claimed_by'] ?? '').toString();
      if (cb.isNotEmpty && cb != teacherId) continue;
    }
    // Not awaited: updates never complete offline; they sync when back online.
    unawaited(sem.subjectDoc(subject).update({
      'claimed_by': FieldValue.delete(),
      'claimed_by_name': FieldValue.delete(),
    }).catchError((_) {}));
  }

  // The teacher's own claims list (a subcollection is NOT removed when the
  // teacher document is deleted).
  for (final r in claimRefs) {
    unawaited(r.delete().catchError((_) {}));
  }
}

// Firestore delete helpers
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getDocsForDelete(
    Query<Map<String, dynamic>> query) async {
  try {
    if (await _isOnline()) {
      final snap = await query.get().timeout(const Duration(seconds: 10));
      return snap.docs;
    }
  } catch (e) {
    debugPrint('services.dart:1186: $e');
  }
  try {
    final snap = await query.get(const GetOptions(source: Source.cache));
    return snap.docs;
  } catch (_) {
    return [];
  }
}

void _deleteDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  for (int i = 0; i < docs.length; i += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs.skip(i).take(400)) {
      batch.delete(d.reference);
    }
    unawaited(batch.commit().catchError((_) {}));
  }
}

// When a subject is deleted, also remove the teacher's claim on it.
Future<void> _cleanupClaimOfSubject(
    SemRef sem, String subject, Map<String, dynamic>? subjectData) async {
  final cb = (subjectData?['claimed_by'] ?? '').toString();
  if (cb.isEmpty) return;
  unawaited(teacherClaimsRef(cb)
      .doc(sem.claimKey(subject))
      .delete()
      .catchError((_) {}));
  await LocalDb.deleteClaim(cb, sem, subject);
}

Future<void> deleteSubjectEverywhere(SemRef sem, String subject) async {
  // Students of this subject, read BEFORE the data is deleted, so the subject
  // can be removed from their attendance summaries (a re-created subject with
  // the same name then starts clean).
  List<String> summaryRolls = [];
  try {
    summaryRolls = (await loadSubjectStudents(sem, subject))
        .map((x) => x['roll'] ?? '')
        .toList();
  } catch (e) {
    debugPrint('services.dart:1226: $e');
  }
  final subSnap = await safeGetDocOrNull(sem.subjectDoc(subject));
  await _cleanupClaimOfSubject(sem, subject, subSnap?.data());
  _deleteDocs(await _getDocsForDelete(sem.dates(subject)));
  _deleteDocs(await _getDocsForDelete(sem.overrides(subject)));
  unawaited(sem.subjectDoc(subject).delete().catchError((_) {}));
  await LocalDb.deleteSubject(sem, subject);
  unawaited(dropSubjectFromSummaries(sem, subject, summaryRolls));
}


// ---------------------------------------------------------------------------
// Rename helpers (admin). A department's display name is its `name` field, so
// renaming it is a single update. A subject's name is its document ID, and a
// student's roll is the document ID too (and the field name inside every
// attendance record), so those two move the data to the new ID and then delete
// the old one. Both need the internet so nothing is left half-moved.
// ---------------------------------------------------------------------------
class RenameException implements Exception {
  final String message;
  RenameException(this.message);
  @override
  String toString() => message;
}


// Small "type a new name" dialog used for departments and subjects. [onSave]
// does the real work; a RenameException message is shown inside the dialog.
// Returns true when the rename went through.
Future<bool> showRenameDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  required Future<void> Function(String value) onSave,
  String? note,
  TextCapitalization caps = TextCapitalization.words,
}) async {
  final controller = TextEditingController(text: initial);
  String? error;
  bool busy = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(note,
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
              ),
            TextField(
              controller: controller,
              enabled: !busy,
              autofocus: true,
              textCapitalization: caps,
              decoration: InputDecoration(labelText: label, errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final v = controller.text.trim();
                    if (v.isEmpty) {
                      setLocal(() => error = 'Please enter a name');
                      return;
                    }
                    if (v == initial) {
                      Navigator.pop(dialogContext, false);
                      return;
                    }
                    setLocal(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await onSave(v);
                      if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                    } on RenameException catch (e) {
                      setLocal(() {
                        busy = false;
                        error = e.message;
                      });
                    } catch (_) {
                      setLocal(() {
                        busy = false;
                        error =
                            'Could not rename. Please check your internet and try again.';
                      });
                    }
                  },
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

Future<void> _requireServer() async {
  if ((await _netState()) != _Net.reachable) {
    throw RenameException('An internet connection is required to rename this.');
  }
}

Future<QuerySnapshot<Map<String, dynamic>>> _serverQuery(
    Query<Map<String, dynamic>> q) async {
  final snap = await q.get().timeout(const Duration(seconds: 30));
  if (snap.metadata.isFromCache) {
    throw RenameException('Could not reach the server. Please try again.');
  }
  return snap;
}

Future<void> _commitInChunks(
    List<void Function(WriteBatch b)> ops) async {
  for (int i = 0; i < ops.length; i += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final op in ops.skip(i).take(400)) {
      op(batch);
    }
    await batch.commit().timeout(const Duration(seconds: 30));
  }
}

Future<void> renameDepartment(String deptId, String newName) async {
  final name = newName.trim();
  if (name.isEmpty || name.contains('/')) {
    throw RenameException('Please enter a valid name.');
  }
  final res = await _safeQuery(FirebaseFirestore.instance.collection('departments'));
  for (final d in res.docs) {
    if (d.id != deptId &&
        (d.data()['name'] ?? d.id).toString().toLowerCase() ==
            name.toLowerCase()) {
      throw RenameException('This department name already exists');
    }
  }
  unawaited(FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .set({'name': name}, SetOptions(merge: true)).catchError((_) {}));
  await LocalDb.upsertDepartment(deptId, name);
  unawaited(syncLocalDbIfStale(force: true));
}

Future<void> renameSubjectEverywhere(
    SemRef sem, String oldName, String newNameRaw) async {
  final newName = newNameRaw.trim().toUpperCase();
  if (newName.isEmpty || newName.contains('/')) {
    throw RenameException('Please enter a valid name.');
  }
  if (newName == oldName) return;
  await _requireServer();

  final oldRef = sem.subjectDoc(oldName);
  final newRef = sem.subjectDoc(newName);
  final oldSnap = await oldRef.get().timeout(const Duration(seconds: 15));
  if (oldSnap.metadata.isFromCache) {
    throw RenameException('Could not reach the server. Please try again.');
  }
  if (!oldSnap.exists) throw RenameException('This subject no longer exists.');
  final newSnap = await newRef.get().timeout(const Duration(seconds: 15));
  if (newSnap.exists) {
    throw RenameException('A subject with this name already exists.');
  }

  // Students of the old subject, for the summary move at the end.
  List<String> summaryRolls = [];
  try {
    summaryRolls = (await loadSubjectStudents(sem, oldName))
        .map((x) => x['roll'] ?? '')
        .toList();
  } catch (e) {
    debugPrint('services.dart:1419: $e');
  }

  final data = Map<String, dynamic>.from(oldSnap.data() ?? {});
  data['name'] = newName;
  final overrides = await _serverQuery(sem.overrides(oldName));
  final dates = await _serverQuery(sem.dates(oldName));

  // 1) copy everything under the new name
  final copyOps = <void Function(WriteBatch b)>[
    (b) => b.set(newRef, data),
    for (final d in overrides.docs)
      (b) => b.set(sem.overrides(newName).doc(d.id), d.data()),
    for (final d in dates.docs)
      (b) => b.set(sem.dates(newName).doc(d.id), stamped(d.data())),
  ];
  await _commitInChunks(copyOps);

  // 2) the teacher's claim points at the new name
  final cb = (data['claimed_by'] ?? '').toString();
  if (cb.isNotEmpty) {
    await teacherClaimsRef(cb).doc(sem.claimKey(newName)).set({
      'dept': sem.deptId,
      'section': sem.section,
      'semester': sem.semester,
      'subject': newName,
    });
    await teacherClaimsRef(cb).doc(sem.claimKey(oldName)).delete();
  }

  // 3) only now remove the old copy
  final delOps = <void Function(WriteBatch b)>[
    for (final d in overrides.docs) (b) => b.delete(d.reference),
    for (final d in dates.docs) (b) => b.delete(d.reference),
    (b) => b.delete(oldRef),
  ];
  await _commitInChunks(delOps);

  await LocalDb.renameSubject(sem, oldName, newName);
  unawaited(syncLocalDbIfStale(force: true));

  // Move the attendance summary: drop the old name, build the new one.
  unawaited(dropSubjectFromSummaries(sem, oldName, summaryRolls));
  unawaited(refreshSubjectSummary(sem, newName));
}

// Changes a student's roll number. Returns the new internal key.
Future<String> changeStudentRoll(
    SemRef sem, String oldKey, String newRollRaw, String name,
    [String father = '']) async {
  final newRoll = newRollRaw.trim();
  if (newRoll.isEmpty) throw RenameException('Please enter a roll number.');
  if (newRoll.contains('/') || newRoll.contains('__')) {
    throw RenameException('Roll number cannot contain "/" or "__".');
  }
  if (rollOf(oldKey) == newRoll) return oldKey; // roll unchanged
  await _requireServer();

  final existing = await _serverQuery(sem.students);
  final keys = existing.docs
      .map((d) => (d.data()['roll'] ?? d.id).toString())
      .where((k) => k != oldKey);
  final newKey = uniqueStudentKey(newRoll, keys);

  final subjects = await _serverQuery(sem.subjects);
  final oldField = FieldPath([oldKey]);
  final newField = FieldPath([newKey]);
  final ops = <void Function(WriteBatch b)>[];

  for (final sub in subjects.docs) {
    // attendance records: move the student's P/A under the new key
    final dates = await _serverQuery(sem.dates(sub.id));
    for (final d in dates.docs) {
      final m = d.data();
      if (!m.containsKey(oldKey)) continue;
      final v = m[oldKey];
      ops.add((b) => b.update(d.reference, <Object, Object?>{
            newField: v,
            oldField: FieldValue.delete(),
            kUpdatedField: FieldValue.serverTimestamp(),
          }));
    }
    // subject-level override of this student
    final ov = await sem.overrides(sub.id).doc(oldKey).get();
    if (ov.exists) {
      final od = Map<String, dynamic>.from(ov.data() ?? {});
      od['roll'] = newKey;
      ops.add((b) => b.set(sem.overrides(sub.id).doc(newKey), od));
      ops.add((b) => b.delete(ov.reference));
    }
  }
  ops.add((b) => b.set(sem.students.doc(newKey),
      {'roll': newKey, 'name': name, 'father': father}));
  ops.add((b) => b.delete(sem.students.doc(oldKey)));

  // Attendance moves come first and the student record last. If something fails
  // halfway, just try again: the retry finishes the remaining moves.
  await _commitInChunks(ops);

  await LocalDb.renameStudentKey(sem, oldKey, newKey, name, father);
  // The student's login follows the new roll (never throws).
  try {
    final logins = await loadStudentLoginNames(sem);
    final u = logins[oldKey];
    if (u != null) {
      await _studentLoginsRef
          .doc(u)
          .update({'roll': newKey}).timeout(const Duration(seconds: 15));
    }
  } catch (e) {
    debugPrint('login roll update failed: $e');
  }
  unawaited(syncLocalDbIfStale(force: true));
  unawaited(summaryRef(sem, oldKey).delete().catchError((_) {}));
  unawaited(rebuildSemesterSummaries(sem));
  return newKey;
}

// Deletes a whole department (all sections, semesters and old data).
Future<void> deleteDepartmentEverywhere(String deptId) async {
  unawaited(FirebaseFirestore.instance
      .collection('meta')
      .doc('seed')
      .set({'done': true}, SetOptions(merge: true)).catchError((_) {}));

  // Built-in sections/semesters plus the ones the admin added (found from the
  // saved list AND from the documents that exist, so nothing is left behind).
  final deptSnap = await safeGetDocOrNull(deptDocRef(deptId));
  final allSections = <String>{...sectionsFrom(deptSnap?.data())};
  for (final d
      in await _getDocsForDelete(deptDocRef(deptId).collection('sections'))) {
    allSections.add(d.id);
  }
  for (final sec in allSections) {
    final allSems = <String>{...semestersFrom(deptSnap?.data(), sec)};
    for (final d in await _getDocsForDelete(
        sectionDocRef(deptId, sec).collection('semesters'))) {
      allSems.add(d.id);
    }
    for (final sid in allSems) {
      final sem = SemRef(deptId, sec, sid);
      final subjects = await _getDocsForDelete(sem.subjects);
      for (final sub in subjects) {
        await _cleanupClaimOfSubject(sem, sub.id, sub.data());
        _deleteDocs(await _getDocsForDelete(sem.dates(sub.id)));
        _deleteDocs(await _getDocsForDelete(sem.overrides(sub.id)));
      }
      _deleteDocs(subjects);
      _deleteDocs(await _getDocsForDelete(sem.students));
      unawaited(sem.doc.delete().catchError((_) {}));
    }
    unawaited(sectionDocRef(deptId, sec).delete().catchError((_) {}));
  }

  // Old data from before sections existed, if any is left
  final oldSubjects = await _getDocsForDelete(legacySubjectsRef(deptId));
  for (final sub in oldSubjects) {
    _deleteDocs(await _getDocsForDelete(legacyDatesRef(deptId, sub.id)));
  }
  _deleteDocs(oldSubjects);
  _deleteDocs(await _getDocsForDelete(legacyStudentsRef(deptId)));

  unawaited(FirebaseFirestore.instance
      .collection('departments')
      .doc(deptId)
      .delete()
      .catchError((_) {}));

  await LocalDb.deleteDepartment(deptId);
}

// Admin only: deletes all attendance records from Firestore, SQLite and the device
// cache. Departments, subjects and students stay. Needs internet (throws otherwise).
Future<void> deleteAllAttendanceEverywhere() async {
  final fs = FirebaseFirestore.instance;
  final snap =
      await fs.collectionGroup('dates').get().timeout(const Duration(seconds: 30));
  if (snap.metadata.isFromCache) {
    throw Exception('Server not reachable');
  }
  final docs = snap.docs;
  for (int i = 0; i < docs.length; i += 400) {
    final batch = fs.batch();
    for (final d in docs.skip(i).take(400)) {
      batch.delete(d.reference);
    }
    await batch.commit().timeout(const Duration(seconds: 30));
  }
  // Summaries go too: a new semester starts clean. If this fails, press Delete
  // again: it is safe.
  await deleteAllSummaries();
  await LocalDb.deleteAllAttendance();
}
