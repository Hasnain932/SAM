part of 'main.dart';

// ===== Student access (read only) =====
// A student logs in with a username + password and can only look at their own
// attendance. Logins live at student_logins/{USERNAME}: dept, section, semester,
// roll, name, salt, hash. A login belongs to the whole degree: when students are
// copied to the next semester, only its semester field moves (same ID and key). The password itself is never stored, only its salted hash.
const String _kStudentPwChars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String _randomFrom(String chars, int n) {
  final r = Random.secure();
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}

String _studentHash(String username, String salt, String password) =>
    _sha256Hex('stu|$salt|$username|$password');

CollectionReference<Map<String, dynamic>> get _studentLoginsRef =>
    FirebaseFirestore.instance.collection('student_logins');

// 'Computer Science' -> 'CS', 'Software' -> 'SOF'
String deptInitials(String dept) {
  final words = dept
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'D';
  String out;
  if (words.length == 1) {
    final w = words.first;
    out = w.substring(0, w.length < 3 ? w.length : 3);
  } else {
    out = words.map((w) => w[0]).join();
    if (out.length > 5) out = out.substring(0, 5);
  }
  return out.toUpperCase();
}

class StudentCred {
  final String roll;
  final String name;
  final String username;
  final String password;
  const StudentCred(this.roll, this.name, this.username, this.password);
}

// Passwords made on this phone are kept in the phone's local storage only
// (never on the server), so the PDF can be exported again for any semester.
// Usernames stay the same for the whole degree, so username -> password works
// for every semester.
const _kSavedStudentPws = 'saved_student_passwords_v1';

Future<Map<String, String>> loadSavedStudentPws() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSavedStudentPws);
    if (raw == null || raw.isEmpty) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, v.toString()));
  } catch (e) {
    debugPrint('load saved student passwords failed: $e');
    return {};
  }
}

Future<void> saveStudentPws(List<StudentCred> creds) async {
  if (creds.isEmpty) return;
  try {
    final all = await loadSavedStudentPws();
    for (final c in creds) {
      all[c.username] = c.password;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSavedStudentPws, jsonEncode(all));
  } catch (e) {
    debugPrint('save student passwords failed: $e');
  }
}

// roll -> username, for the logins that already exist in this class (server read).
Future<Map<String, String>> loadStudentLoginNames(SemRef sem) async {
  final snap = await _studentLoginsRef
      .where('dept', isEqualTo: sem.deptId)
      .where('section', isEqualTo: sem.section)
      .where('semester', isEqualTo: sem.semester)
      .get(const GetOptions(source: Source.server))
      .timeout(const Duration(seconds: 12));
  final out = <String, String>{};
  for (final d in snap.docs) {
    final roll = (d.data()['roll'] ?? '').toString();
    if (roll.isNotEmpty) out[roll] = d.id;
  }
  return out;
}

Future<String> _pickStudentUsername(SemRef sem, String roll) async {
  // One login for the whole degree, so the semester is not part of the username.
  final base = '${deptInitials(sem.deptId)}-${sem.section}-$roll'
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9_-]'), '');
  for (var i = 1; i <= 30; i++) {
    final cand = i == 1 ? base : '$base-$i';
    final d = await _studentLoginsRef
        .doc(cand)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    if (!d.exists) return cand;
  }
  throw StateError('No free username for roll $roll');
}

// Creates logins (new random password each). With [onlyRolls] it (re)sets just
// those students; without it, it creates logins only for students that have none.
// Needs internet. The plain passwords are returned once and never stored.
Future<List<StudentCred>> generateStudentLogins(SemRef sem,
    {Set<String>? onlyRolls}) async {
  if (!await AppSession.ensureSignedIn()) {
    throw StateError('Not signed in to the server (${AppSession.lastAuthError}).');
  }
  final students = await loadSemesterStudents(sem);
  final existing = await loadStudentLoginNames(sem);
  final targets = students.where((st) {
    final roll = st['roll']!;
    return onlyRolls == null
        ? !existing.containsKey(roll)
        : onlyRolls.contains(roll);
  }).toList();

  final out = <StudentCred>[];
  var batch = FirebaseFirestore.instance.batch();
  var pending = 0;
  for (final st in targets) {
    final roll = st['roll']!;
    final name = st['name'] ?? '';
    final username = existing[roll] ?? await _pickStudentUsername(sem, roll);
    final password = _randomFrom(_kStudentPwChars, 8);
    final salt = _randomFrom('abcdef0123456789', 12);
    batch.set(_studentLoginsRef.doc(username), {
      'username': username,
      'dept': sem.deptId,
      'section': sem.section,
      'semester': sem.semester,
      'roll': roll,
      'name': name,
      'salt': salt,
      'hash': _studentHash(username, salt, password),
    });
    out.add(StudentCred(roll, name, username, password));
    pending++;
    if (pending >= 400) {
      await batch.commit().timeout(const Duration(seconds: 30));
      batch = FirebaseFirestore.instance.batch();
      pending = 0;
    }
  }
  if (pending > 0) {
    await batch.commit().timeout(const Duration(seconds: 30));
  }
  return out;
}

// Moves the logins of students copied from [from] to [to]: same username and
// password, only the semester (and the key, if it changed) is updated.
// [keyMap] is old key -> new key. Admin only, needs internet; never throws.
Future<int> moveStudentLogins(
    SemRef from, SemRef to, Map<String, String> keyMap) async {
  if (keyMap.isEmpty) return 0;
  try {
    if (!await AppSession.ensureSignedIn()) return 0;
    final src = await loadStudentLoginNames(from); // roll -> username
    final dest = await loadStudentLoginNames(to);
    var batch = FirebaseFirestore.instance.batch();
    var pending = 0;
    var moved = 0;
    for (final e in keyMap.entries) {
      final username = src[e.key];
      if (username == null || dest.containsKey(e.value)) continue;
      batch.update(_studentLoginsRef.doc(username),
          {'semester': to.semester, 'roll': e.value});
      moved++;
      if (++pending >= 400) {
        await batch.commit().timeout(const Duration(seconds: 30));
        batch = FirebaseFirestore.instance.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit().timeout(const Duration(seconds: 30));
    return moved;
  } catch (e) {
    debugPrint('move student logins failed: $e');
    return 0;
  }
}

// For students of [sem] that have no login yet: finds a login of the same
// section in another semester (same roll and same name) and moves it here.
// Used by the Sync button (old logins, or a copy done by a teacher).
Future<int> adoptStudentLogins(SemRef sem, {Set<String>? alreadyMoved}) async {
  if (!await AppSession.ensureSignedIn()) {
    throw StateError('Not signed in to the server (${AppSession.lastAuthError}).');
  }
  final students = await loadSemesterStudents(sem);
  final mine = await loadStudentLoginNames(sem);
  final snap = await _studentLoginsRef
      .where('dept', isEqualTo: sem.deptId)
      .where('section', isEqualTo: sem.section)
      .get(const GetOptions(source: Source.server))
      .timeout(const Duration(seconds: 12));
  String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final cands = snap.docs
      .where((d) =>
          (d.data()['semester'] ?? '').toString() != sem.semester &&
          !(alreadyMoved?.contains(d.id) ?? false))
      .toList();
  final used = <String>{};
  var batch = FirebaseFirestore.instance.batch();
  var pending = 0;
  var moved = 0;
  for (final st in students) {
    final key = st['roll']!;
    if (mine.containsKey(key)) continue;
    final name = norm(st['name'] ?? '');
    for (final d in cands) {
      if (used.contains(d.id)) continue;
      final data = d.data();
      if (rollOf((data['roll'] ?? '').toString()) != rollOf(key)) continue;
      if (norm((data['name'] ?? '').toString()) != name) continue;
      used.add(d.id);
      alreadyMoved?.add(d.id);
      batch.update(d.reference, {'semester': sem.semester, 'roll': key});
      moved++;
      if (++pending >= 400) {
        await batch.commit().timeout(const Duration(seconds: 30));
        batch = FirebaseFirestore.instance.batch();
        pending = 0;
      }
      break;
    }
  }
  if (pending > 0) await batch.commit().timeout(const Duration(seconds: 30));
  return moved;
}

// Sync for every semester of the section in one go (one tap for the admin).
Future<int> adoptStudentLoginsAllSemesters(SemRef current) async {
  final ids = <String>{
    ...await loadSemesterIds(current.deptId, current.section),
    current.semester,
  };
  final moved = <String>{};
  var total = 0;
  for (final id in ids) {
    total += await adoptStudentLogins(
        SemRef(current.deptId, current.section, id),
        alreadyMoved: moved);
  }
  return total;
}

// Sync for EVERY department, section and semester in one go (admin).
Future<int> adoptStudentLoginsEverywhere() async {
  var total = 0;
  final depts = await _safeQuery(
      FirebaseFirestore.instance.collection('departments'));
  for (final d in depts.docs) {
    if (d.id == kHiddenAdminDeptName) continue;
    for (final sec in sectionsFrom(d.data())) {
      try {
        final moved = <String>{};
        for (final id in await loadSemesterIds(d.id, sec)) {
          total += await adoptStudentLogins(SemRef(d.id, sec, id),
              alreadyMoved: moved);
        }
      } catch (e) {
        debugPrint('sync ${d.id}/$sec failed: $e');
      }
    }
  }
  return total;
}

// Deletes the logins (ID and key) of the given students of [sem]. Admin only.
Future<int> deleteStudentLoginsFor(SemRef sem, Set<String> keys) async {
  if (keys.isEmpty || !AppSession.isAdmin) return 0;
  if (!await AppSession.ensureSignedIn()) return 0;
  final logins = await loadStudentLoginNames(sem);
  var batch = FirebaseFirestore.instance.batch();
  var pending = 0;
  var n = 0;
  for (final k in keys) {
    final username = logins[k];
    if (username == null) continue;
    batch.delete(_studentLoginsRef.doc(username));
    n++;
    if (++pending >= 400) {
      await batch.commit().timeout(const Duration(seconds: 30));
      batch = FirebaseFirestore.instance.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit().timeout(const Duration(seconds: 30));
  return n;
}

// ---- QR code on the student card ----
// The QR holds 'SAM1|USERNAME|PASSWORD' (the same details as the printed text),
// so the card must be kept private, just like the password itself.
const String kStudentQrTag = 'SAM1';

String studentQrPayload(String username, String password) =>
    '$kStudentQrTag|$username|$password';

// Returns (username, password), or null when the text is not a SAM card QR.
(String, String)? parseStudentQr(String raw) {
  final parts = raw.trim().split('|');
  if (parts.length != 3 || parts[0] != kStudentQrTag) return null;
  final username = parts[1].trim().toUpperCase();
  final password = parts[2].trim().toUpperCase();
  if (!RegExp(r'^[A-Z0-9_-]+$').hasMatch(username)) return null;
  if (!RegExp(r'^[A-Z0-9]+$').hasMatch(password)) return null;
  return (username, password);
}

// ---- Student login screen ----
class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _userC = TextEditingController();
  final _passC = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userC.dispose();
    _passC.dispose();
    super.dispose();
  }

  void _fail(String msg) {
    if (mounted) setState(() => _error = msg);
  }

  // Typed login: reads the two fields.
  Future<void> _submit() => _login(
        _userC.text.trim().toUpperCase(),
        _passC.text.trim().toUpperCase(),
      );

  // QR login: opens the camera, reads the card's QR code, then logs in with it.
  Future<void> _scanQr() async {
    if (_busy) return;
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const StudentQrScanScreen()),
    );
    if (code == null || !mounted) return;
    final cred = parseStudentQr(code);
    if (cred == null) {
      _fail('This QR code is not a SAM student card.');
      return;
    }
    // Fill the fields too, so the student can retry by hand if needed.
    _userC.text = cred.$1;
    _passC.text = cred.$2;
    await _login(cred.$1, cred.$2);
  }

  // Shared by the typed login and the QR login.
  Future<void> _login(String username, String password) async {
    if (_busy) return;
    if (username.isEmpty || password.isEmpty) {
      _fail('Please fill in all fields');
      return;
    }
    const wrong = 'Incorrect username or password';
    if (!RegExp(r'^[A-Z0-9_-]+$').hasMatch(username)) {
      _fail(wrong);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _isOnline()) {
        _fail('Internet is required to log in.');
        return;
      }
      if (!await AppSession.ensureSignedIn()) {
        _fail(
            'Could not connect to the server (${AppSession.lastAuthError}). Please try again.');
        return;
      }
      final snap = await _studentLoginsRef
          .doc(username)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      final data = snap.data();
      if (!snap.exists || data == null) {
        _fail(wrong);
        return;
      }
      final salt = (data['salt'] ?? '').toString();
      if (_studentHash(username, salt, password) !=
          (data['hash'] ?? '').toString()) {
        _fail(wrong);
        return;
      }
      await AppSession.loginStudent({
        'u': username,
        'dept': (data['dept'] ?? '').toString(),
        'section': (data['section'] ?? '').toString(),
        'semester': (data['semester'] ?? '').toString(),
        'roll': (data['roll'] ?? '').toString(),
        'name': (data['name'] ?? '').toString(),
      });
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseException catch (e) {
      debugPrint('student login failed: ${e.code}');
      _fail(e.code == 'permission-denied'
          ? 'The server refused the request. Please try again later.'
          : 'Could not reach the server. Please check your internet and try again.');
    } on TimeoutException {
      _fail('The server took too long. Please check your internet and try again.');
    } catch (e) {
      debugPrint('student login failed: $e');
      _fail('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      icon: Icons.school_outlined,
      title: 'Student Login',
      subtitle: 'See your attendance',
      children: [
        AuthField(
          label: 'Username',
          hint: 'e.g. CS-A-3-15',
          icon: Icons.person_outline,
          controller: _userC,
          capitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: 'Password',
          hint: 'Enter your password',
          icon: Icons.lock_outline,
          controller: _passC,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kAbsent)),
          ),
        GradientButton(
          label: 'Login',
          loading: _busy,
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: 12),
        GradPill(
          label: 'Scan QR code',
          icon: Icons.qr_code_scanner,
          filled: false,
          enabled: !_busy,
          expand: true,
          height: 48,
          radius: 26,
          onTap: _busy ? null : _scanQr,
        ),
      ],
    );
  }
}

// ---- Student QR scanner: returns the scanned text, or nothing if closed ----
class StudentQrScanScreen extends StatefulWidget {
  const StudentQrScanScreen({super.key});

  @override
  State<StudentQrScanScreen> createState() => _StudentQrScanScreenState();
}

class _StudentQrScanScreenState extends State<StudentQrScanScreen> {
  final scanner.MobileScannerController _controller =
      scanner.MobileScannerController(
    formats: const [scanner.BarcodeFormat.qrCode],
    detectionSpeed: scanner.DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  void _onDetect(scanner.BarcodeCapture capture) {
    if (_done || !mounted) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        _done = true; // only the first code is used
        Navigator.of(context).pop(v.trim());
        return;
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
    unawaited(_controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan your card')),
      body: Stack(
        children: [
          Positioned.fill(
            child: scanner.MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
          Center(
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: kAccent, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Point the camera at the QR code on your SAM card.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Student home: own attendance, read only ----
class _SubjAtt {
  final String name;
  final int present;
  final int absent;
  final int total;
  final List<StatEntry> entries;
  final bool failed;
  const _SubjAtt(this.name, this.present, this.absent, this.total, this.entries,
      {this.failed = false});
}

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  bool _loading = true;
  String? _error;
  String _name = '';
  List<_SubjAtt> _subs = [];
  int _filter = 0; // 0 all, 1 on track, 2 needs attention

  Map<String, String> get _me => AppSession.student;
  SemRef get _sem =>
      SemRef(_me['dept'] ?? '', _me['section'] ?? '', _me['semester'] ?? '');

  @override
  void initState() {
    super.initState();
    _name = _me['name'] ?? '';
    _load();
  }

  String _label(DateRecord r) =>
      '${prettySession(r.id)}${r.isLab ? ' · Lab' : ''}';

  Future<_SubjAtt> _loadSubject(SemRef sem, String name, String roll) async {
    try {
      final recs = await loadDateRecords(sem, name);
      var p = 0, a = 0;
      final entries = <StatEntry>[];
      for (final r in recs) {
        final st = r.status[roll];
        if (st == 'P') {
          p++;
          entries.add(StatEntry(_label(r), true));
        } else if (st == 'A') {
          a++;
          entries.add(StatEntry(_label(r), false));
        }
      }
      return _SubjAtt(name, p, a, recs.length, entries.reversed.toList());
    } catch (_) {
      return _SubjAtt(name, 0, 0, 0, const [], failed: true);
    }
  }

  bool _syncedOk = false;

  // The login is for the whole degree: the admin moves it to the next semester
  // when students are copied. Read it again so the student sees the new semester.
  // Returns false when the login was deleted (the student is logged out).
  Future<bool> _syncLogin() async {
    final u = _me['u'] ?? '';
    if (u.isEmpty) return true;
    try {
      final snap = await _studentLoginsRef
          .doc(u)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      _syncedOk = true;
      if (!snap.exists) {
        await AppSession.logout();
        return false;
      }
      final d = snap.data() ?? {};
      final fresh = <String, String>{
        'u': u,
        'dept': (d['dept'] ?? '').toString(),
        'section': (d['section'] ?? '').toString(),
        'semester': (d['semester'] ?? '').toString(),
        'roll': (d['roll'] ?? '').toString(),
        'name': (d['name'] ?? '').toString(),
      };
      var changed = false;
      for (final e in fresh.entries) {
        if (e.value.isNotEmpty && _me[e.key] != e.value) changed = true;
      }
      if (changed) {
        await AppSession.updateStudent(fresh);
        _name = fresh['name'] ?? _name;
      }
    } catch (_) {
      // Offline or slow: keep the saved details.
    }
    return true;
  }

  // The server read of the login happens at most once a day (or on pull-to-refresh).
  Future<bool> _syncLoginDaily(bool force) async {
    final key = 'login_sync|${_me['u'] ?? ''}';
    SharedPreferences? p;
    try {
      p = await SharedPreferences.getInstance();
      final age = DateTime.now().millisecondsSinceEpoch - (p.getInt(key) ?? 0);
      if (!force && age >= 0 && age < 24 * 3600 * 1000) return true;
    } catch (_) {}
    _syncedOk = false;
    final ok = await _syncLogin();
    if (ok && _syncedOk) {
      try {
        await p?.setInt(key, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    }
    return ok;
  }

  // ---- 6 hour phone cache of the finished result (pull-to-refresh bypasses it) ----
  static const int _kCacheMinutes = 360;
  String get _cacheKey =>
      'att_cache|${_me['u']}|${_me['dept']}|${_me['section']}|${_me['semester']}|${_me['roll']}';

  List<StatEntry> _entriesFrom(List raw) => [
        for (final x in raw)
          if (x is String && x.length > 2) StatEntry(x.substring(2), x[0] == 'P')
      ];

  Future<bool> _loadFromCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cacheKey);
      if (raw == null) return false;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final age = DateTime.now().millisecondsSinceEpoch - (m['ts'] as int);
      if (age < 0 || age > _kCacheMinutes * 60 * 1000) return false;
      final list = <_SubjAtt>[];
      for (final x in (m['subs'] as List)) {
        final e = x as Map<String, dynamic>;
        list.add(_SubjAtt(
            e['n'] as String,
            e['p'] as int,
            e['a'] as int,
            e['t'] as int,
            _entriesFrom(e['e'] as List)));
      }
      _subs = list;
      final nm = (m['name'] ?? '').toString();
      if (nm.isNotEmpty) _name = nm;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveCache(List<_SubjAtt> list) async {
    if (list.any((e) => e.failed)) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _cacheKey,
          jsonEncode({
            'ts': DateTime.now().millisecondsSinceEpoch,
            'name': _name,
            'subs': [
              for (final e in list)
                {
                  'n': e.name,
                  'p': e.present,
                  'a': e.absent,
                  't': e.total,
                  'e': [
                    for (final x in e.entries)
                      '${x.present ? 'P' : 'A'}|${x.label}'
                  ],
                }
            ],
          }));
    } catch (_) {}
  }

  _SubjAtt _fromSummary(String name, Map s) {
    int i(Object? v) => v is num ? v.toInt() : 0;
    final raw = s['e'] is List ? List.from(s['e'] as List) : <dynamic>[];
    return _SubjAtt(name, i(s['p']), i(s['a']), i(s['t']),
        _entriesFrom(raw).reversed.toList());
  }

  Future<void> _load({bool force = false}) async {
    if (!force && await _loadFromCache()) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    if (!await _syncLoginDaily(force) || !mounted) return;
    final roll = _me['roll'] ?? '';
    if (roll.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Your login is incomplete. Please log out and log in again.';
        });
      }
      return;
    }
    try {
      final sem = _sem;
      final me = await safeGetDocOrNull(sem.students.doc(roll));
      if (me != null && me.exists) {
        _name = (me.data()?['name'] ?? _name).toString();
      } else if (me != null && !me.metadata.isFromCache) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Your record was not found. Please contact the admin.';
          });
        }
        return;
      }
      final subRes = await _safeQuery(sem.subjects);
      final names = subRes.docs.map((d) => d.id).toList()
        ..sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase()));

      // The one summary document of this student (1 read).
      var sums = <String, dynamic>{};
      try {
        final sd = await safeGetDocOrNull(summaryRef(sem, roll));
        final m = sd?.data()?['subjects'];
        if (m is Map) sums = Map<String, dynamic>.from(m);
      } catch (_) {}

      final list = <_SubjAtt>[];
      final futures = names.map((n) async {
        final sm = sums[n];
        if (sm is Map) return _fromSummary(n, sm);
        // Not in the summary yet: old way for this subject only.
        try {
          final ov = await loadOverrides(sem, n);
          if (ov[roll]?['kind'] == 'hidden') return null; // not in this subject
        } catch (_) {}
        return _loadSubject(sem, n, roll);
      }).toList();
      for (final r in await Future.wait(futures)) {
        if (r != null) list.add(r);
      }
      if (!mounted) return;
      setState(() {
        _subs = list;
        _loading = false;
        _error = null;
      });
      unawaited(_saveCache(list));
    } catch (e) {
      debugPrint('student load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your attendance. Please check your internet and try again.';
      });
    }
  }

  bool _isGood(_SubjAtt e) =>
      e.total > 0 && e.present / e.total * 100 >= _kNeed;

  Widget _filterChip(int id, String label, int count) {
    final sel = _filter == id;
    return GestureDetector(
      onTap: () => setState(() => _filter = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          gradient: sel ? kBlueGrad : null,
          color: sel ? null : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? Colors.transparent : kGlassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: kAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAccent.withValues(alpha: 0.4)),
        ),
        child: Text(t,
            style: const TextStyle(
                color: kLabelBlue, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _header(SemRef sem) {
    final nm = _name.trim();
    final words = nm.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? 'S'
        : words.take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x2E8B7CF6), Color(0x1A14B8E6)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kGlassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kViolet, kAccent2]),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: Text(initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('STUDENT ATTENDANCE',
                    style: TextStyle(
                        color: kMuted,
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(nm.isEmpty ? 'Student' : nm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _miniChip('Roll ${rollOf(_me['roll'] ?? '')}'),
                    _miniChip(defaultSemesterLabel(sem.semester)),
                    _miniChip('Section ${sem.section}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => confirmAndLogout(context),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: kBlueGrad,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: kAccent2.withValues(alpha: 0.35), blurRadius: 8),
                ],
              ),
              child: const Icon(Icons.logout_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sem = _sem;
    final totalP = _subs.fold<int>(0, (a, e) => a + e.present);
    final totalA = _subs.fold<int>(0, (a, e) => a + e.absent);
    final totalAll = _subs.fold<int>(0, (a, e) => a + e.total);
    final onTrack = _subs.where(_isGood).length;
    final needs = _subs.where((e) => e.total > 0 && !_isGood(e)).length;
    final shown = _subs.where((e) {
      if (_filter == 1) return _isGood(e);
      if (_filter == 2) return e.total > 0 && !_isGood(e);
      return true;
    }).toList();

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kAbsent, fontSize: 15)),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() => _loading = true);
                _load(force: true);
              },
              child: const Text('Try again'),
            ),
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 0, bottom: 24),
          children: [
            _header(sem),
            _OverallHero(present: totalP, absent: totalA, total: totalAll),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('SUBJECTS',
                      style: TextStyle(
                          color: kLabelBlue,
                          fontSize: 12,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 2, height: 10, color: Colors.white54),
                      const SizedBox(width: 5),
                      Text('${_kNeed.toStringAsFixed(0)}% required',
                          style:
                              const TextStyle(color: kMuted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip(0, 'All', _subs.length),
                  _filterChip(1, 'On track', onTrack),
                  _filterChip(2, 'Needs attention', needs),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    _subs.isEmpty ? 'No subjects yet.' : 'Nothing here.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kMuted)),
              ),
            for (var i = 0; i < shown.length; i++)
              _AttCard(
                key: ValueKey(shown[i].name),
                index: i,
                title: shown[i].name,
                present: shown[i].present,
                absent: shown[i].absent,
                total: shown[i].total,
                entries: shown[i].entries,
                failed: shown[i].failed,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: body),
    );
  }
}

// ---- Student home widgets: overall hero + subject cards ----
const double _kPi = 3.141592653589793;
const double _kNeed = 75; // minimum attendance percent
IconData _subjectIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('calc') || n.contains('math') || n.contains('algebra')) {
    return Icons.functions_rounded;
  }
  if (n.contains('data structure') || n.contains('algorithm')) {
    return Icons.account_tree_rounded;
  }
  if (n.contains('database') || n.contains('sql')) {
    return Icons.storage_rounded;
  }
  if (n.contains('program') || n.contains('code') || n.contains('software')) {
    return Icons.code_rounded;
  }
  if (n.contains('network')) return Icons.hub_rounded;
  if (n.contains('physics') || n.contains('science')) {
    return Icons.science_rounded;
  }
  if (n.contains('english') || n.contains('comm')) {
    return Icons.menu_book_rounded;
  }
  return Icons.auto_stories_rounded;
}

// Accent colors for subject cards (all from the app palette).
const List<Color> _kSubjectColors = [
  kAccent,
  kViolet,
  kLabelBlue,
  Color(0xFF5B8CFF),
];

class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final bool good;
  const _RingPainter(this.progress, this.good);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0x1FFFFFFF);
    canvas.drawCircle(c, r, track);
    if (progress > 0) {
      final colors = good
          ? const [kViolet, kAccent2, kAccent]
          : const [kAbsent2, kAbsent, kAbsent2];
      final sweep = progress.clamp(0.0, 1.0).toDouble();
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 2
        ..strokeCap = StrokeCap.round
        ..color = (good ? kAccent : kAbsent).withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawArc(rect, -_kPi / 2, 2 * _kPi * sweep, false, glow);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: colors,
          transform: const GradientRotation(-_kPi / 2),
        ).createShader(rect);
      canvas.drawArc(rect, -_kPi / 2, 2 * _kPi * sweep, false, arc);
    }
    // 75% marker
    final ang = -_kPi / 2 + 2 * _kPi * (_kNeed / 100);
    final p1 = Offset(c.dx + (r - stroke) * cos(ang), c.dy + (r - stroke) * sin(ang));
    final p2 = Offset(c.dx + (r + stroke) * cos(ang), c.dy + (r + stroke) * sin(ang));
    canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.good != good;
}

// Big "Overall" card: animated ring, three stats and a status banner.
class _OverallHero extends StatelessWidget {
  final int present;
  final int absent;
  final int total;
  const _OverallHero(
      {required this.present, required this.absent, required this.total});

  Widget _stat(String label, int value, Color c) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [c.withValues(alpha: 0.20), c.withValues(alpha: 0.06)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: kLabelBlue, fontSize: 12.5)),
          ),
          Text('$value',
              style: TextStyle(
                  color: c, fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? present / total * 100 : 0.0;
    final good = total == 0 || pct >= _kNeed;
    final diff = (pct - _kNeed).abs().toStringAsFixed(1);
    String msg;
    String sub = '';
    IconData icon;
    if (total == 0) {
      msg = 'No classes recorded yet';
      icon = Icons.hourglass_empty_rounded;
    } else if (absent == 0) {
      msg = 'Perfect record. Keep it going';
      icon = Icons.local_fire_department_rounded;
    } else if (good) {
      msg = "You're on track. Keep attending";
      sub = '$diff points above the ${_kNeed.toStringAsFixed(0)}% minimum';
      icon = Icons.verified_user_rounded;
    } else {
      msg = 'Below ${_kNeed.toStringAsFixed(0)}%. Attend regularly';
      sub = '$diff points below the ${_kNeed.toStringAsFixed(0)}% minimum';
      icon = Icons.warning_amber_rounded;
    }
    final tone = good ? kAccent : kAbsent;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0x268B7CF6),
            tone.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
            color: good ? kGlassBorder : kAbsent.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 126,
                height: 126,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => CustomPaint(
                    painter: _RingPainter(v / 100, good),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${v.toStringAsFixed(v >= 99.95 ? 0 : 1)}%',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  shadows: kGlowText)),
                          const Text('Overall',
                              style: TextStyle(color: kMuted, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    _stat('Present', present, kPresent),
                    _stat('Absent', absent, kAbsent),
                    _stat('Sessions', total, kViolet),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tone.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: good ? kBlueGrad : kRedGrad,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(msg,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800)),
                      if (sub.isNotEmpty)
                        Text(sub,
                            style: const TextStyle(
                                color: kLabelBlue, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// One read-only subject card.
class _AttCard extends StatefulWidget {
  final String title;
  final int present;
  final int absent;
  final int total;
  final List<StatEntry> entries;
  final bool failed;
  final int index;
  const _AttCard({
    super.key,
    required this.title,
    required this.present,
    required this.absent,
    required this.total,
    required this.entries,
    this.failed = false,
    this.index = 0,
  });

  @override
  State<_AttCard> createState() => _AttCardState();
}

class _AttCardState extends State<_AttCard> {
  bool _open = false;

  // How many classes can still be missed (or must be attended) at 75%.
  String? _hint(bool good) {
    final p = widget.present, t = widget.total;
    if (t == 0) return null;
    if (good) {
      final x = (4 * p - 3 * t) ~/ 3; // exact integer math for 75%
      if (x <= 0) return 'Do not miss the next class';
      return 'Can miss $x more ${x == 1 ? 'class' : 'classes'}';
    }
    final int y = (3 * t - 4 * p).clamp(1, 100000).toInt();
    return 'Attend next $y ${y == 1 ? 'class' : 'classes'} to reach 75%';
  }

  Widget _tile(String label, int v, Color c) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: kMuted, fontSize: 10.5)),
              Text('$v',
                  style: TextStyle(
                      color: c, fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );

  Widget _breakdown(Color accent) {
    final w = widget;
    final byEntries = w.entries.length == w.total;
    final dots = <bool>[
      if (byEntries)
        for (final e in w.entries.reversed) e.present
      else ...[
        for (var i = 0; i < w.present; i++) true,
        for (var i = 0; i < w.total - w.present; i++) false,
      ]
    ];
    final need = (3 * w.total + 3) ~/ 4; // ceil(75%)
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('CLASS BREAKDOWN',
                  style: TextStyle(
                      color: kMuted,
                      fontSize: 10.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700)),
              Text('${w.present} / ${w.total}',
                  style: const TextStyle(
                      color: kLabelBlue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final p in dots)
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: p ? accent : const Color(0x26FFFFFF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _tile('Attended', w.present, kAccent),
              _tile('Absent', w.absent, kAbsent),
              _tile('Total', w.total, kViolet),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: const TextStyle(color: kMuted, fontSize: 12),
              children: [
                const TextSpan(text: 'To stay at 75% you need at least '),
                TextSpan(
                    text: '$need',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const TextSpan(text: ' of '),
                TextSpan(
                    text: '${w.total}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const TextSpan(text: ' classes attended.'),
              ],
            ),
          ),
          if (byEntries) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in w.entries)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (e.present ? kPresent : kAbsent)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${e.label} · ${e.present ? 'P' : 'A'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: e.present ? kPresent : kAbsent,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final pct = w.total > 0 ? (w.present / w.total) * 100 : 0.0;
    final good = w.total == 0 || pct >= _kNeed;
    final accent = good
        ? _kSubjectColors[w.index % _kSubjectColors.length]
        : kAbsent;
    final hint = _hint(good);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: good
              ? const [Color(0x1FFFFFFF), Color(0x0DFFFFFF)]
              : [kAbsent.withValues(alpha: 0.16), kAbsent2.withValues(alpha: 0.06)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: good ? kGlassBorder : kAbsent.withValues(alpha: 0.45)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap:
              w.entries.isEmpty ? null : () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.35)),
                      ),
                      child: Icon(_subjectIcon(w.title),
                          color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.title.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  letterSpacing: 0.3,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            w.failed
                                ? 'Could not load. Pull down to refresh.'
                                : w.total == 0
                                    ? 'No classes recorded yet'
                                    : '${w.present} of ${w.total} classes attended',
                            style: TextStyle(
                                color: w.failed ? kAbsent : kMuted,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (!w.failed && w.total > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: good ? kBlueGrad : kRedGrad,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${pct.toStringAsFixed(pct == 100 ? 0 : 1)}%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5)),
                      ),
                    ],
                  ],
                ),
                if (!w.failed && w.total > 0) ...[
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, cons) {
                    final tickX = cons.maxWidth * (_kNeed / 100);
                    return SizedBox(
                      height: 10,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                  begin: 0.0,
                                  end: (pct / 100).clamp(0.0, 1.0).toDouble()),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutCubic,
                              builder: (context, v, _) =>
                                  LinearProgressIndicator(
                                value: v,
                                minHeight: 7,
                                backgroundColor: const Color(0x26FFFFFF),
                                color: accent,
                              ),
                            ),
                          ),
                          Positioned(
                            left: tickX - 1,
                            child: Container(
                                width: 2, height: 10, color: Colors.white70),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(
                          good
                              ? Icons.verified_user_outlined
                              : Icons.warning_amber_rounded,
                          size: 15,
                          color: good ? kLabelBlue : kAbsent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(hint ?? '',
                            style: TextStyle(
                                color: good ? kLabelBlue : kAbsent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (w.absent > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: kAbsent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${w.absent} absent',
                              style: const TextStyle(
                                  color: kAbsent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      if (w.entries.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0x14FFFFFF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: kGlassBorder),
                          ),
                          child: Icon(
                            _open
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: kLabelBlue,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ],
                if (_open && !w.failed && w.total > 0) _breakdown(accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
