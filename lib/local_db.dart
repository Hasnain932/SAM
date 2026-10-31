part of 'main.dart';

// ---------------------------------------------------------------------------
// Backup & restore
// Backup: reads every Firestore document into one JSON file (saved on the phone
// or downloaded on web). Restore: writes each document back to its path. It never
// deletes anything, and running it twice is harmless.
//---------------------------------------------------------------------------
const String kBackupFormat = 'attendance_backup_v1';
const List<String> _kBackupRoots = ['departments', 'teachers', 'settings', 'meta'];
const List<String> _kBackupGroups = [
  'sections',
  'semesters',
  'students',
  'subjects',
  'overrides',
  'dates',
  'claims',
];

dynamic _bkEncode(dynamic v) {
  if (v is Timestamp) {
    return {'__t': 'ts', 's': v.seconds, 'n': v.nanoseconds};
  }
  if (v is GeoPoint) {
    return {'__t': 'geo', 'lat': v.latitude, 'lng': v.longitude};
  }
  if (v is DocumentReference) return {'__t': 'ref', 'p': v.path};
  if (v is Blob) return {'__t': 'bytes', 'b': base64Encode(v.bytes)};
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _bkEncode(val)));
  }
  if (v is Iterable) return v.map(_bkEncode).toList();
  return v;
}

dynamic _bkDecode(dynamic v) {
  if (v is Map) {
    final t = v['__t'];
    if (t == 'ts') return Timestamp(v['s'] as int, v['n'] as int);
    if (t == 'geo') {
      return GeoPoint((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble());
    }
    if (t == 'ref') return FirebaseFirestore.instance.doc(v['p'] as String);
    if (t == 'bytes') return Blob(base64Decode(v['b'] as String));
    return v.map((k, val) => MapEntry(k.toString(), _bkDecode(val)));
  }
  if (v is List) return v.map(_bkDecode).toList();
  return v;
}

// Result of a backup run: the finished JSON file and how many records it holds.
class _BackupResult {
  final Uint8List bytes;
  final int count;
  _BackupResult(this.bytes, this.count);
}

// Builds the backup JSON piece by piece. Every document is encoded and appended to
// one byte buffer right away, so there is never a second full copy (map + string +
// bytes) in memory. Big collection groups are read in pages of 500 documents; if
// the server refuses paging for a group, that group is read in one go instead.
// The file layout is the same as before, so old backups still restore.
Future<_BackupResult> _collectBackupBytes() async {
  final fs = FirebaseFirestore.instance;
  const t = Duration(seconds: 60);
  const pageSize = 500;
  final out = BytesBuilder(copy: false);
  final seen = <String>{};
  var count = 0;
  var first = true;

  void put(String path, Map<String, dynamic> data) {
    if (!seen.add(path)) return; // the same document can come from two queries
    out.add(utf8.encode(
        '${first ? '' : ','}${jsonEncode(path)}:${jsonEncode(_bkEncode(data))}'));
    first = false;
    count++;
  }

  void addSnap(QuerySnapshot<Map<String, dynamic>> snap) {
    // A cached answer would give an incomplete backup, so refuse it.
    if (snap.metadata.isFromCache) throw Exception('Server not reachable');
    for (final d in snap.docs) {
      put(d.reference.path, d.data());
    }
  }

  // Header is written first; the final count is not known yet, so it is written at
  // the end (a "count" key after "docs" is fine for JSON readers).
  out.add(utf8.encode('{"format":${jsonEncode(kBackupFormat)},'
      '"created":${jsonEncode(DateTime.now().toIso8601String())},"docs":{'));

  for (final c in _kBackupRoots) {
    addSnap(await fs.collection(c).get().timeout(t));
  }
  for (final g in _kBackupGroups) {
    var paged = true;
    try {
      QueryDocumentSnapshot<Map<String, dynamic>>? last;
      while (true) {
        var q = fs
            .collectionGroup(g)
            .orderBy(FieldPath.documentId)
            .limit(pageSize);
        if (last != null) q = q.startAfterDocument(last);
        final snap = await q.get().timeout(t);
        addSnap(snap);
        if (snap.docs.length < pageSize) break;
        last = snap.docs.last;
      }
    } catch (e) {
      if (e.toString().contains('Server not reachable')) rethrow;
      paged = false;
    }
    if (!paged) {
      addSnap(await fs.collectionGroup(g).get().timeout(t));
    }
  }
  out.add(utf8.encode('},"count":$count}'));
  return _BackupResult(out.takeBytes(), count);
}

// Web: opens the share sheet. Browsers only allow sharing within a few
// seconds of a tap, so if that time ran out while the file was being prepared
// we show a small dialog whose "Share" button gives a fresh tap.
Future<void> webShareOrDownload(
    BuildContext context, List<int> bytes, String name,
    {String? text}) async {
  // Android Chrome blocks sharing Excel/JSON files, so just download there.
  // iPhone / iPad keep the share sheet.
  if (isAndroidBrowser()) {
    downloadBytes(bytes, name);
    if (context.mounted) {
      showSnack(context, 'File downloaded. Find it in your Downloads folder.');
    }
    return;
  }
  final r = await shareBytesNow(bytes, name, text: text);
  if (r == 'shared') return;
  if (r == 'unsupported') {
    if (context.mounted) {
      showSnack(context, 'Share not available ($lastShareError). Downloaded instead.');
    }
    downloadBytes(bytes, name);
    return;
  }
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('File ready'),
      content: Text(name),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            downloadBytes(bytes, name);
          },
          child: const Text('Download'),
        ),
        FilledButton(
          onPressed: () async {
            // Start the share FIRST (inside the tap), then close the dialog.
            final pending = shareBytesNow(bytes, name, text: text);
            Navigator.pop(ctx);
            final r2 = await pending;
            if (r2 != 'shared') {
              if (context.mounted) {
                showSnack(context, 'Could not open share: $lastShareError');
              }
              downloadBytes(bytes, name);
            }
          },
          child: const Text('Share'),
        ),
      ],
    ),
  );
}

// Creates the backup file and saves/shares it. Returns the number of records.
Future<int> createBackupFile([BuildContext? context]) async {
  final result = await _collectBackupBytes();
  final bytes = result.bytes;
  final name =
      'attendance_backup_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.json';
  if (kIsWeb) {
    if (context != null && context.mounted) {
      await webShareOrDownload(context, bytes, name,
          text: 'Attendance backup');
    } else {
      await saveOrShareBytes(bytes, name, text: 'Attendance backup');
    }
    return result.count;
  }
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(path)],
    text: 'Attendance backup',
  ));
  return result.count;
}

Future<void> runBackupWithUi(BuildContext context) async {
  if ((await _netState()) != _Net.reachable) {
    if (!context.mounted) return;
    showSnack(context, 'Internet is required to take a backup.',
        color: kAbsent);
    return;
  }
  if (context.mounted) showSnack(context, 'Preparing backup...');
  try {
    final n = await createBackupFile(context.mounted ? context : null);
    if (context.mounted) showSnack(context, 'Backup ready ($n records)');
  } catch (e) {
    debugPrint('Backup error: $e');
    if (context.mounted) {
      showSnack(context, 'Backup failed. Check your internet and try again.',
          color: kAbsent);
    }
  }
}

bool _bkPathOk(String path) {
  final parts = path.split('/');
  return parts.length.isEven &&
      parts.every((p) => p.isNotEmpty) &&
      _kBackupRoots.contains(parts.first);
}

Future<void> restoreFromBackupUi(BuildContext context) async {
  PlatformFile? f;
  try {
    f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
  } catch (e) {
    debugPrint('File picker error: $e');
    if (context.mounted) {
      showSnack(context, 'Could not open the file picker.', color: kAbsent);
    }
    return;
  }
  if (f == null) return;

  Map<String, dynamic> docs;
  String created = '';
  try {
    final bytes = await f.readAsBytes();
    final m = jsonDecode(utf8.decode(bytes));
    if (m is! Map || m['format'] != kBackupFormat || m['docs'] is! Map) {
      throw const FormatException('not a backup');
    }
    docs = Map<String, dynamic>.from(m['docs'] as Map);
    created = (m['created'] ?? '').toString();
    if (docs.keys.any((p) => !_bkPathOk(p))) {
      throw const FormatException('bad path');
    }
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'This is not a valid backup file.', color: kAbsent);
    }
    return;
  }
  if (!context.mounted) return;

  String when = created;
  try {
    when = DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(created));
  } catch (_) {}

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(
        'Backup taken: $when\nRecords in file: ${docs.length}\n\n'
        'Every record in the file is written back to the server and replaces the current version of that record. '
        'Records that are not in the file are not deleted. Internet is required.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  if ((await _netState()) != _Net.reachable) {
    if (context.mounted) {
      showSnack(context, 'Internet is required to restore.', color: kAbsent);
    }
    return;
  }
  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Text('Restoring...'),
        ],
      ),
    ),
  );

  bool success = false;
  try {
    final fs = FirebaseFirestore.instance;
    final entries = docs.entries.toList();
    for (int i = 0; i < entries.length; i += 400) {
      final batch = fs.batch();
      for (final e in entries.skip(i).take(400)) {
        var m = Map<String, dynamic>.from(_bkDecode(e.value) as Map);
        // Restored attendance gets a fresh update time, so other devices (delta
        // sync) notice that it changed.
        if (e.key.contains('/dates/')) m = stamped(m);
        batch.set(fs.doc(e.key), m);
      }
      await batch.commit().timeout(const Duration(seconds: 30));
    }
    success = true;
    await syncLocalDbIfStale(force: true);
  } catch (e) {
    debugPrint('Restore error: $e');
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  showSnack(
    context,
    success
        ? 'Restore complete'
        : 'Restore did not finish. Check your internet and run it again.',
    color: success ? null : kAbsent,
  );
}

// One-time migration of the old Software Engineering data
//   -> Software Engineering / Section A / Semester 3
// Data is copied, not deleted, so running it again is safe.
Future<void> _copyDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  DocumentReference<Map<String, dynamic>> Function(
          QueryDocumentSnapshot<Map<String, dynamic>> d)
      target,
) async {
  for (int i = 0; i < docs.length; i += 400) {
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs.skip(i).take(400)) {
      batch.set(target(d), d.data(), SetOptions(merge: true));
    }
    await batch.commit().timeout(const Duration(seconds: 30));
  }
}

Future<bool> migrateSoftwareEngineeringLegacy() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('migr_se_a3_v1') == true) return false;
  if (!await _isOnline()) return false;

  final fs = FirebaseFirestore.instance;
  final metaRef = fs.collection('meta').doc('migration_se_a3_v1');
  try {
    const t = Duration(seconds: 20);
    final meta = await metaRef.get().timeout(const Duration(seconds: 10));
    if (meta.exists && meta.data()?['done'] == true) {
      await prefs.setBool('migr_se_a3_v1', true);
      return false;
    }

    final target = SemRef(kSoftwareEngineeringDeptId, 'A', '3');

    final students =
        await legacyStudentsRef(kSoftwareEngineeringDeptId).get().timeout(t);
    await _copyDocs(students.docs, (d) => target.students.doc(d.id));

    final subjects =
        await legacySubjectsRef(kSoftwareEngineeringDeptId).get().timeout(t);
    await _copyDocs(subjects.docs, (d) => target.subjects.doc(d.id));

    for (final sub in subjects.docs) {
      final dates = await legacyDatesRef(kSoftwareEngineeringDeptId, sub.id)
          .get()
          .timeout(t);
      await _copyDocs(dates.docs, (d) => target.dates(sub.id).doc(d.id));
    }

    await metaRef.set({'done': true}).timeout(const Duration(seconds: 10));
    await prefs.setBool('migr_se_a3_v1', true);
    await LocalDb.replaceAllFromFirestore();
    return true;
  } catch (e) {
    debugPrint('Migration failed (will retry next time): $e');
    return false;
  }
}

// Create the second admin (one time): a doc that looks like a normal department
Future<void> ensureHiddenAdminDepartment() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('hidden_admin_v1') == true) return;
    if (!await _isOnline()) return;

    final fs = FirebaseFirestore.instance;
    final metaRef = fs.collection('meta').doc('hidden_admin_v1');
    final meta = await metaRef.get().timeout(const Duration(seconds: 10));
    if (meta.exists && meta.data()?['done'] == true) {
      await prefs.setBool('hidden_admin_v1', true);
      return;
    }

    final deptRef =
        fs.collection('departments').doc(kHiddenAdminDeptName);
    final snap = await deptRef.get().timeout(const Duration(seconds: 10));
    if (!snap.exists) {
      await deptRef.set({
        'name': kHiddenAdminDeptName,
      }).timeout(const Duration(seconds: 10));
    }
    await metaRef.set({'done': true}).timeout(const Duration(seconds: 10));
    await prefs.setBool('hidden_admin_v1', true);
  } catch (_) {}
}

// Local SQLite database (used alongside Firestore, not instead of it)
// Every function catches its own errors, so SQLite problems never stop the app.
// Passwords and the department username are not saved here (keeps the second
// admin hidden in exports).
class LocalDb {
  static sql.Database? _db;
  static bool _syncing = false;
  static const String _fileName = 'attendance_local.db';

  static Future<String> filePath() async {
    final dir = await sql.getDatabasesPath();
    return '$dir/$_fileName';
  }

  static const List<String> _tables = [
    'attendance',
    'sessions',
    'overrides',
    'claims',
    'subjects',
    'students',
    'semesters',
    'teachers',
    'departments',
  ];

  static Future<void> _createAll(sql.Database db) async {
    await db.execute(
        'CREATE TABLE departments (dept_id TEXT PRIMARY KEY, name TEXT, username TEXT)');
    await db.execute(
        'CREATE TABLE semesters (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, label TEXT, PRIMARY KEY (dept_id, section, semester))');
    await db.execute(
        'CREATE TABLE students (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, roll TEXT NOT NULL, name TEXT, father TEXT DEFAULT \'\', PRIMARY KEY (dept_id, section, semester, roll))');
    await db.execute(
        'CREATE TABLE subjects (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, name TEXT NOT NULL, claimed_by TEXT, claimed_by_name TEXT, PRIMARY KEY (dept_id, section, semester, name))');
    await db.execute(
        'CREATE TABLE overrides (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, roll TEXT NOT NULL, name TEXT, kind TEXT, father TEXT DEFAULT \'\', PRIMARY KEY (dept_id, section, semester, subject, roll))');
    // v6: per-session details (who / when / type / phase) live once in `sessions`;
    // `attendance` keeps only roll + status, so every student row is much smaller.
    await db.execute(
        'CREATE TABLE sessions (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, session_id TEXT NOT NULL, marked_time TEXT, marked_by TEXT, marked_by_name TEXT, session_type TEXT, exam_phase TEXT DEFAULT \'mid\', PRIMARY KEY (dept_id, section, semester, subject, session_id))');
    await db.execute(
        'CREATE TABLE attendance (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, session_id TEXT NOT NULL, roll TEXT NOT NULL, status TEXT, PRIMARY KEY (dept_id, section, semester, subject, session_id, roll))');
    await db.execute(
        'CREATE TABLE teachers (teacher_id TEXT PRIMARY KEY, name TEXT, username TEXT)');
    await db.execute(
        'CREATE TABLE claims (teacher_id TEXT NOT NULL, dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, PRIMARY KEY (teacher_id, dept_id, section, semester, subject))');
    await _createIndexes(db);
  }

  // Extra indexes for the lookups the primary keys do not cover (per-student
  // queries / renames, claimed-by lookups, department deletes). Safe to run twice.
  static Future<void> _createIndexes(sql.Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_att_roll ON attendance (dept_id, section, semester, subject, roll)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_att_semroll ON attendance (dept_id, section, semester, roll)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_overrides_roll ON overrides (dept_id, section, semester, roll)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_subjects_claimed ON subjects (claimed_by)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_claims_subject ON claims (dept_id, section, semester, subject)');
  }

  // v5 -> v6: move the per-session columns out of `attendance` into `sessions`.
  static Future<void> _migrateToSessions(sql.Database db) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS sessions (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, session_id TEXT NOT NULL, marked_time TEXT, marked_by TEXT, marked_by_name TEXT, session_type TEXT, exam_phase TEXT DEFAULT \'mid\', PRIMARY KEY (dept_id, section, semester, subject, session_id))');
    await db.execute('''
INSERT OR REPLACE INTO sessions
  (dept_id, section, semester, subject, session_id, marked_time, marked_by, marked_by_name, session_type, exam_phase)
SELECT dept_id, section, semester, subject, session_id,
  COALESCE(MAX(marked_time), ''), COALESCE(MAX(marked_by), ''),
  COALESCE(MAX(marked_by_name), ''), COALESCE(MAX(session_type), 'class'),
  COALESCE(MAX(exam_phase), 'mid')
FROM attendance
GROUP BY dept_id, section, semester, subject, session_id''');
    await db.execute(
        'CREATE TABLE attendance_new (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, session_id TEXT NOT NULL, roll TEXT NOT NULL, status TEXT, PRIMARY KEY (dept_id, section, semester, subject, session_id, roll))');
    await db.execute(
        'INSERT OR REPLACE INTO attendance_new (dept_id, section, semester, subject, session_id, roll, status) SELECT dept_id, section, semester, subject, session_id, roll, status FROM attendance');
    await db.execute('DROP TABLE attendance');
    await db.execute('ALTER TABLE attendance_new RENAME TO attendance');
  }

  static Future<sql.Database> _open() async {
    if (_db != null && _db!.isOpen) return _db!;
    final path = await filePath();
    _db = await sql.openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async => _createAll(db),
      // v1 -> v2: the structure changed. The local DB is only a Firestore copy, so drop
      // the old tables and recreate them; data refills when online.
      // v2 -> v3: add the session type column (old rows count as 'class').
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          for (final t in _tables) {
            await db.execute('DROP TABLE IF EXISTS $t');
          }
          await _createAll(db);
          return;
        }
        if (oldV < 3) {
          await db.execute(
              "ALTER TABLE attendance ADD COLUMN session_type TEXT DEFAULT 'class'");
        }
        // v3 -> v4: father name of students (old rows get an empty value).
        if (oldV < 4) {
          await db.execute(
              "ALTER TABLE students ADD COLUMN father TEXT DEFAULT ''");
          await db.execute(
              "ALTER TABLE overrides ADD COLUMN father TEXT DEFAULT ''");
        }
        // v4 -> v5: exam phase (Mid / Final) of a session. Old rows count as Mid.
        if (oldV < 5) {
          await db.execute(
              "ALTER TABLE attendance ADD COLUMN exam_phase TEXT DEFAULT 'mid'");
        }
        // v5 -> v6: separate `sessions` table + extra indexes.
        if (oldV < 6) {
          await _migrateToSessions(db);
          await _createIndexes(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _run(Future<void> Function(sql.Database db) action) async {
    try {
      final db = await _open();
      await action(db);
    } catch (e) {
      debugPrint('LocalDb error: $e');
    }
  }

  // ---------------- departments ----------------
  static Future<void> upsertDepartment(String deptId, String name) {
    if (deptId == kHiddenAdminDeptName) return Future.value();
    return _run((db) async {
      await db.insert(
        'departments',
        {'dept_id': deptId, 'name': name, 'username': ''},
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteDepartment(String deptId) {
    return _run((db) async {
      await db.transaction((txn) async {
        for (final t in ['attendance', 'sessions', 'overrides', 'subjects', 'students', 'semesters']) {
          await txn.delete(t, where: 'dept_id = ?', whereArgs: [deptId]);
        }
        await txn.delete('claims', where: 'dept_id = ?', whereArgs: [deptId]);
        await txn.delete('departments', where: 'dept_id = ?', whereArgs: [deptId]);
      });
    });
  }

  // ---------------- semester labels ----------------
  static Future<void> upsertSemesterLabel(SemRef s, String label) {
    return _run((db) async {
      await db.insert(
        'semesters',
        {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'label': label,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteSemesterLabel(SemRef s) {
    return _run((db) async {
      await db.delete('semesters',
          where: 'dept_id = ? AND section = ? AND semester = ?',
          whereArgs: [s.deptId, s.section, s.semester]);
    });
  }

  // ---------------- students ----------------
  static Future<void> upsertStudent(SemRef s, String roll, String name,
      [String father = '']) {
    return _run((db) async {
      await db.insert(
        'students',
        {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'roll': roll,
          'name': name,
          'father': father,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteStudent(SemRef s, String roll) {
    return _run((db) async {
      await db.delete('students',
          where: 'dept_id = ? AND section = ? AND semester = ? AND roll = ?',
          whereArgs: [s.deptId, s.section, s.semester, roll]);
    });
  }

  // ---------------- subjects ----------------
  static Future<void> upsertSubject(SemRef s, String name) {
    return _run((db) async {
      final n = await db.update(
        'subjects',
        {'name': name},
        where: 'dept_id = ? AND section = ? AND semester = ? AND name = ?',
        whereArgs: [s.deptId, s.section, s.semester, name],
      );
      if (n == 0) {
        await db.insert('subjects', {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'name': name,
          'claimed_by': '',
          'claimed_by_name': '',
        });
      }
    });
  }

  static Future<void> setSubjectClaim(
      SemRef s, String name, String teacherId, String teacherName) {
    return _run((db) async {
      await db.update(
        'subjects',
        {'claimed_by': teacherId, 'claimed_by_name': teacherName},
        where: 'dept_id = ? AND section = ? AND semester = ? AND name = ?',
        whereArgs: [s.deptId, s.section, s.semester, name],
      );
    });
  }

  static Future<void> deleteSubject(SemRef s, String name) {
    return _run((db) async {
      await db.transaction((txn) async {
        const w =
            'dept_id = ? AND section = ? AND semester = ? AND subject = ?';
        final args = [s.deptId, s.section, s.semester, name];
        await txn.delete('attendance', where: w, whereArgs: args);
        await txn.delete('sessions', where: w, whereArgs: args);
        await txn.delete('overrides', where: w, whereArgs: args);
        await txn.delete('claims', where: w, whereArgs: args);
        await txn.delete('subjects',
            where: 'dept_id = ? AND section = ? AND semester = ? AND name = ?',
            whereArgs: args);
      });
    });
  }

  // ---------------- subject-level student overrides ----------------
  static Future<void> upsertOverride(
      SemRef s, String subject, String roll, String name, String kind,
      [String father = '']) {
    return _run((db) async {
      await db.insert(
        'overrides',
        {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'subject': subject,
          'roll': roll,
          'name': name,
          'father': father,
          'kind': kind,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteOverride(SemRef s, String subject, String roll) {
    return _run((db) async {
      await db.delete('overrides',
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND roll = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, roll]);
    });
  }

  // ---------------- attendance ----------------
  // Saves one session. Only the rows that really changed are written: the session
  // details go to `sessions`, new / changed students are inserted, and students
  // that are no longer in the session are removed.
  static Future<void> saveAttendance(
    SemRef s,
    String subject,
    String sessionId,
    Map<String, String> status, {
    String? time,
    String? markedBy,
    String? markedByName,
    String sessionType = kTypeClass,
    String phase = kPhaseMid,
  }) {
    return _run((db) async {
      await db.transaction((txn) async {
        const w =
            'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?';
        final args = [s.deptId, s.section, s.semester, subject, sessionId];

        // A session without any student has no record (same as Firestore).
        if (status.isEmpty) {
          await txn.delete('attendance', where: w, whereArgs: args);
          await txn.delete('sessions', where: w, whereArgs: args);
          return;
        }

        await txn.insert(
          'sessions',
          {
            'dept_id': s.deptId,
            'section': s.section,
            'semester': s.semester,
            'subject': subject,
            'session_id': sessionId,
            'marked_time': time ?? '',
            'marked_by': markedBy ?? '',
            'marked_by_name': markedByName ?? '',
            'session_type': sessionType,
            'exam_phase': phase,
          },
          conflictAlgorithm: sql.ConflictAlgorithm.replace,
        );

        final existingRows = await txn.query('attendance',
            columns: ['roll', 'status'], where: w, whereArgs: args);
        final existing = <String, String>{
          for (final r in existingRows)
            (r['roll'] ?? '').toString(): (r['status'] ?? '').toString()
        };

        final batch = txn.batch();
        for (final roll in existing.keys) {
          if (!status.containsKey(roll)) {
            batch.delete('attendance',
                where: '$w AND roll = ?', whereArgs: [...args, roll]);
          }
        }
        status.forEach((roll, st) {
          if (existing[roll] == st) return; // unchanged, nothing to write
          batch.insert(
            'attendance',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'subject': subject,
              'session_id': sessionId,
              'roll': roll,
              'status': st,
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        });
        await batch.commit(noResult: true);
      });
    });
  }

  // Changes only the type of one session (Class <-> Lab Class).
  static Future<void> setSessionType(
      SemRef s, String subject, String sessionId, String type) {
    return _run((db) async {
      await db.update('sessions', {'session_type': type},
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
    });
  }

  // Changes only the exam phase of one session (Mid <-> Final).
  static Future<void> setSessionPhase(
      SemRef s, String subject, String sessionId, String phase) {
    return _run((db) async {
      await db.update('sessions', {'exam_phase': phase},
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
    });
  }

  // Marks one student Present ('P') or Absent ('A') in every saved session of a
  // subject. A session where the student has no row yet gets one, so the whole
  // past record changes.
  static Future<void> setStudentStatusAll(
      SemRef s, String subject, String roll, String status) {
    return _run((db) async {
      await db.transaction((txn) async {
        final sessions = await txn.query('sessions',
            columns: ['session_id'],
            where: '$_semWhere AND subject = ?',
            whereArgs: [..._semArgs(s), subject]);
        final batch = txn.batch();
        for (final r in sessions) {
          batch.insert(
            'attendance',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'subject': subject,
              'session_id': (r['session_id'] ?? '').toString(),
              'roll': roll,
              'status': status,
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    });
  }

  static Future<void> deleteAttendance(
      SemRef s, String subject, String sessionId) {
    return _run((db) async {
      const w =
          'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?';
      final args = [s.deptId, s.section, s.semester, subject, sessionId];
      await db.transaction((txn) async {
        await txn.delete('attendance', where: w, whereArgs: args);
        await txn.delete('sessions', where: w, whereArgs: args);
      });
    });
  }

  // ---------------- teachers & claims ----------------
  static Future<void> upsertTeacher(String id, String name, String username) {
    return _run((db) async {
      await db.insert(
        'teachers',
        {'teacher_id': id, 'name': name, 'username': username},
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteTeacher(String id) {
    return _run((db) async {
      await db.transaction((txn) async {
        // Free every subject this teacher had claimed, so "Taken by <name>"
        // does not keep showing a deleted teacher.
        await txn.update(
          'subjects',
          {'claimed_by': '', 'claimed_by_name': ''},
          where: 'claimed_by = ?',
          whereArgs: [id],
        );
        await txn.delete('claims', where: 'teacher_id = ?', whereArgs: [id]);
        await txn.delete('teachers', where: 'teacher_id = ?', whereArgs: [id]);
      });
    });
  }

  static Future<void> upsertClaim(String teacherId, SemRef s, String subject) {
    return _run((db) async {
      await db.insert(
        'claims',
        {
          'teacher_id': teacherId,
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'subject': subject,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    });
  }

  static Future<void> deleteClaim(String teacherId, SemRef s, String subject) {
    return _run((db) async {
      await db.delete('claims',
          where:
              'teacher_id = ? AND dept_id = ? AND section = ? AND semester = ? AND subject = ?',
          whereArgs: [teacherId, s.deptId, s.section, s.semester, subject]);
    });
  }

  // Rebuilds SQLite from Firestore. collectionGroup fetches each collection in one
  // query; the document path gives the department / section / semester.
  //
  // full: true  = rebuild everything (also removes anything deleted elsewhere).
  // full: false = delta: the small collections are still read completely, but the
  //   big one (attendance 'dates') is asked only for sessions updated since the last
  //   sync (field kUpdatedField). If that query is refused (the Firestore index is
  //   missing) or fails, it falls back to a full sync and remembers it.
  static const String _kDeltaWm = 'sqlite_delta_wm_ms';
  static const String _kLastFull = 'sqlite_last_full_ms';
  static const String kDeltaBroken = 'sqlite_delta_broken';

  static Future<bool> replaceAllFromFirestore({bool full = true}) async {
    if (_syncing) return false;
    if (!await _isOnline()) return false;
    _syncing = true;
    try {
      const t = Duration(seconds: 30);
      final fs = FirebaseFirestore.instance;
      final prefs = await SharedPreferences.getInstance();
      // A full sync (daily / forced) tries delta again, so one bad day never turns
      // it off for good. Between full syncs, a delta marked broken stays off.
      if (full && prefs.getBool(kDeltaBroken) == true) {
        await prefs.setBool(kDeltaBroken, false);
      }
      var delta = !full && prefs.getBool(kDeltaBroken) != true;
      final oldWm = prefs.getInt(_kDeltaWm) ?? 0;

      final depts = await fs.collection('departments').get().timeout(t);
      final semDocs = await fs.collectionGroup('semesters').get().timeout(t);
      final students = await fs.collectionGroup('students').get().timeout(t);
      final subjects = await fs.collectionGroup('subjects').get().timeout(t);
      final overrides = await fs.collectionGroup('overrides').get().timeout(t);
      late QuerySnapshot<Map<String, dynamic>> dates;
      if (delta) {
        try {
          // 2 minutes back, so nothing near the previous watermark is missed.
          final since = Timestamp.fromMillisecondsSinceEpoch(
              oldWm > 120000 ? oldWm - 120000 : 0);
          dates = await fs
              .collectionGroup('dates')
              .where(kUpdatedField, isGreaterThanOrEqualTo: since)
              .get()
              .timeout(t);
          await prefs.setBool(kDeltaBroken, false);
        } catch (e) {
          debugPrint('Delta sync not possible, doing a full sync: $e');
          // Only a missing Firestore index (failed-precondition) or a refused query
          // means delta can not work. A slow network (timeout) must not switch it off.
          if (e is FirebaseException &&
              (e.code == 'failed-precondition' ||
                  e.code == 'permission-denied')) {
            await prefs.setBool(kDeltaBroken, true);
          }
          delta = false;
          dates = await fs.collectionGroup('dates').get().timeout(t);
        }
      } else {
        dates = await fs.collectionGroup('dates').get().timeout(t);
      }
      final teachers = await fs.collection('teachers').get().timeout(t);
      final claims = await fs.collectionGroup('claims').get().timeout(t);

      // Data from the offline cache means we aren't really online: keep the existing
      // SQLite data instead of replacing it with a partial copy.
      final allSnaps = [
        depts,
        semDocs,
        students,
        subjects,
        overrides,
        dates,
        teachers,
        claims,
      ];
      if (allSnaps.any((x) => x.metadata.isFromCache)) return false;

      bool isNew(List<String> seg, int len, String coll) =>
          seg.length == len &&
          seg[0] == 'departments' &&
          seg[2] == 'sections' &&
          seg[4] == 'semesters' &&
          seg[6] == coll;

      final deptRows = <Map<String, Object?>>[];
      final semRows = <Map<String, Object?>>[];
      final studentRows = <Map<String, Object?>>[];
      final subjectRows = <Map<String, Object?>>[];
      final overrideRows = <Map<String, Object?>>[];
      final attendanceRows = <Map<String, Object?>>[];
      final sessionRows = <Map<String, Object?>>[];
      final teacherRows = <Map<String, Object?>>[];
      final claimRows = <Map<String, Object?>>[];

      for (final d in depts.docs) {
        if (d.id == kHiddenAdminDeptName) continue; // hidden admin
        deptRows.add({
          'dept_id': d.id,
          'name': (d.data()['name'] ?? d.id).toString(),
          'username': '',
        });
      }

      for (final d in semDocs.docs) {
        final seg = d.reference.path.split('/');
        if (seg.length == 6 &&
            seg[0] == 'departments' &&
            seg[2] == 'sections' &&
            seg[4] == 'semesters') {
          final label = (d.data()['label'] ?? '').toString();
          if (label.isNotEmpty) {
            semRows.add({
              'dept_id': seg[1],
              'section': seg[3],
              'semester': seg[5],
              'label': label,
            });
          }
        }
      }

      for (final d in students.docs) {
        final seg = d.reference.path.split('/');
        if (!isNew(seg, 8, 'students')) continue;
        final sd = d.data();
        studentRows.add({
          'dept_id': seg[1],
          'section': seg[3],
          'semester': seg[5],
          'roll': (sd['roll'] ?? d.id).toString(),
          'name': (sd['name'] ?? '').toString(),
          'father': (sd['father'] ?? '').toString(),
        });
      }

      for (final d in subjects.docs) {
        final seg = d.reference.path.split('/');
        if (!isNew(seg, 8, 'subjects')) continue;
        final sd = d.data();
        subjectRows.add({
          'dept_id': seg[1],
          'section': seg[3],
          'semester': seg[5],
          'name': d.id,
          'claimed_by': (sd['claimed_by'] ?? '').toString(),
          'claimed_by_name': (sd['claimed_by_name'] ?? '').toString(),
        });
      }

      for (final d in overrides.docs) {
        final seg = d.reference.path.split('/');
        if (!(seg.length == 10 &&
            seg[0] == 'departments' &&
            seg[2] == 'sections' &&
            seg[4] == 'semesters' &&
            seg[6] == 'subjects' &&
            seg[8] == 'overrides')) {
          continue;
        }
        final od = d.data();
        overrideRows.add({
          'dept_id': seg[1],
          'section': seg[3],
          'semester': seg[5],
          'subject': seg[7],
          'roll': (od['roll'] ?? d.id).toString(),
          'name': (od['name'] ?? '').toString(),
          'father': (od['father'] ?? '').toString(),
          'kind': (od['kind'] ?? '').toString(),
        });
      }

      // Sessions whose old rows must be replaced (delta mode only).
      final changedSessions = <List<String>>[];
      var newWm = delta ? oldWm : 0;
      for (final d in dates.docs) {
        final seg = d.reference.path.split('/');
        if (!(seg.length == 10 &&
            seg[0] == 'departments' &&
            seg[2] == 'sections' &&
            seg[4] == 'semesters' &&
            seg[6] == 'attendance' &&
            seg[8] == 'dates')) {
          continue;
        }
        final up = d.data()[kUpdatedField];
        if (up is Timestamp && up.millisecondsSinceEpoch > newWm) {
          newWm = up.millisecondsSinceEpoch;
        }
        if (delta) {
          changedSessions.add([seg[1], seg[3], seg[5], seg[7], d.id]);
        }
        final parsed = parseAttendance(d.data());
        if (parsed.status.isEmpty) continue;
        sessionRows.add({
          'dept_id': seg[1],
          'section': seg[3],
          'semester': seg[5],
          'subject': seg[7],
          'session_id': d.id,
          'marked_time': parsed.meta['_time'] ?? '',
          'marked_by': parsed.meta['_marked_by'] ?? '',
          'marked_by_name': parsed.meta['_marked_by_name'] ?? '',
          'session_type': parsed.meta['_type'] ?? kTypeClass,
          'exam_phase': parsed.meta['_phase'] ?? kPhaseMid,
        });
        parsed.status.forEach((roll, status) {
          attendanceRows.add({
            'dept_id': seg[1],
            'section': seg[3],
            'semester': seg[5],
            'subject': seg[7],
            'session_id': d.id,
            'roll': roll,
            'status': status,
          });
        });
      }

      for (final d in teachers.docs) {
        final td = d.data();
        teacherRows.add({
          'teacher_id': d.id,
          'name': (td['name'] ?? '').toString(),
          'username': (td['username'] ?? '').toString(),
        });
      }

      for (final d in claims.docs) {
        final seg = d.reference.path.split('/');
        if (!(seg.length == 4 && seg[0] == 'teachers' && seg[2] == 'claims')) {
          continue;
        }
        final cd = d.data();
        claimRows.add({
          'teacher_id': seg[1],
          'dept_id': (cd['dept'] ?? '').toString(),
          'section': (cd['section'] ?? '').toString(),
          'semester': (cd['semester'] ?? '').toString(),
          'subject': (cd['subject'] ?? '').toString(),
        });
      }

      final db = await _open();
      await db.transaction((txn) async {
        for (final table in _tables) {
          // Delta: keep the attendance rows, only changed sessions are replaced.
          if (delta && (table == 'attendance' || table == 'sessions')) continue;
          await txn.delete(table);
        }
        if (delta) {
          for (final k in changedSessions) {
            for (final table in const ['attendance', 'sessions']) {
              await txn.delete(table,
                  where:
                      'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
                  whereArgs: k);
            }
          }
        }
        final batch = txn.batch();
        void addAll(String table, List<Map<String, Object?>> rows) {
          for (final r in rows) {
            batch.insert(table, r, conflictAlgorithm: sql.ConflictAlgorithm.replace);
          }
        }

        addAll('departments', deptRows);
        addAll('semesters', semRows);
        addAll('students', studentRows);
        addAll('subjects', subjectRows);
        addAll('overrides', overrideRows);
        addAll('sessions', sessionRows);
        addAll('attendance', attendanceRows);
        addAll('teachers', teacherRows);
        addAll('claims', claimRows);
        await batch.commit(noResult: true);
        if (delta) {
          // Subjects / departments deleted elsewhere: drop their attendance too.
          for (final table in const ['attendance', 'sessions']) {
            await txn.execute(
                'DELETE FROM $table WHERE NOT EXISTS (SELECT 1 FROM subjects s '
                'WHERE s.dept_id = $table.dept_id AND s.section = $table.section '
                'AND s.semester = $table.semester AND s.name = $table.subject)');
          }
        }
      });
      await prefs.setInt(_kDeltaWm, newWm);
      if (!delta) {
        await prefs.setInt(_kLastFull, DateTime.now().millisecondsSinceEpoch);
      }
      return true;
    } catch (e) {
      debugPrint('LocalDb sync error: $e');
      return false;
    } finally {
      _syncing = false;
    }
  }

  // Reads: offline fallback for the loaders and the monthly attendance view
  static const String _semWhere =
      'dept_id = ? AND section = ? AND semester = ?';

  static List<Object?> _semArgs(SemRef s) => [s.deptId, s.section, s.semester];

  static Future<Map<String, String>> students(SemRef s) async {
    try {
      final db = await _open();
      final rows = await db.query('students',
          where: _semWhere, whereArgs: _semArgs(s));
      return {
        for (final r in rows)
          (r['roll'] ?? '').toString(): (r['name'] ?? '').toString()
      };
    } catch (e) {
      debugPrint('LocalDb students error: $e');
      return {};
    }
  }

  // roll -> father name of the students of a semester (offline fallback).
  static Future<Map<String, String>> fathers(SemRef s) async {
    try {
      final db = await _open();
      final rows = await db.query('students',
          where: _semWhere, whereArgs: _semArgs(s));
      return {
        for (final r in rows)
          (r['roll'] ?? '').toString(): (r['father'] ?? '').toString()
      };
    } catch (e) {
      debugPrint('LocalDb fathers error: $e');
      return {};
    }
  }

  static Future<Map<String, Map<String, String>>> overrides(
      SemRef s, String subject) async {
    try {
      final db = await _open();
      final rows = await db.query('overrides',
          where: '$_semWhere AND subject = ?',
          whereArgs: [..._semArgs(s), subject]);
      return {
        for (final r in rows)
          (r['roll'] ?? '').toString(): {
            'name': (r['name'] ?? '').toString(),
            'father': (r['father'] ?? '').toString(),
            'kind': (r['kind'] ?? '').toString(),
          }
      };
    } catch (e) {
      debugPrint('LocalDb overrides error: $e');
      return {};
    }
  }

  // Attendance records of a subject from SQLite, grouped by session.
  // monthPrefix = 'yyyy-MM' limits the result to one month.
  static Future<List<DateRecord>> dateRecords(SemRef s, String subject,
      {String? monthPrefix}) async {
    try {
      final db = await _open();
      final monthClause =
          monthPrefix == null ? '' : ' AND session_id LIKE ?';
      final args = [
        ..._semArgs(s),
        subject,
        if (monthPrefix != null) '$monthPrefix-%',
      ];
      final sessionRows = await db.query(
        'sessions',
        where: '$_semWhere AND subject = ?$monthClause',
        whereArgs: args,
        orderBy: 'session_id',
      );
      final attRows = await db.query(
        'attendance',
        columns: ['session_id', 'roll', 'status'],
        where: '$_semWhere AND subject = ?$monthClause',
        whereArgs: args,
      );
      final byId = <String, DateRecord>{};
      for (final r in sessionRows) {
        final id = (r['session_id'] ?? '').toString();
        final rec =
            DateRecord(id, <String, String>{}, <String, String>{});
        final t = (r['marked_time'] ?? '').toString();
        if (t.isNotEmpty) rec.meta['_time'] = t;
        final by = (r['marked_by'] ?? '').toString();
        if (by.isNotEmpty) rec.meta['_marked_by'] = by;
        final byName = (r['marked_by_name'] ?? '').toString();
        if (byName.isNotEmpty) rec.meta['_marked_by_name'] = byName;
        rec.meta['_type'] =
            (r['session_type'] ?? '').toString() == kTypeLab ? kTypeLab : kTypeClass;
        rec.meta['_phase'] =
            (r['exam_phase'] ?? '').toString() == kPhaseFinal ? kPhaseFinal : kPhaseMid;
        byId[id] = rec;
      }
      for (final r in attRows) {
        final rec = byId[(r['session_id'] ?? '').toString()];
        if (rec == null) continue;
        rec.status[(r['roll'] ?? '').toString()] =
            (r['status'] ?? '').toString();
      }
      return byId.values.toList();
    } catch (e) {
      debugPrint('LocalDb dateRecords error: $e');
      return [];
    }
  }

  static Future<List<Map<String, String>>> claimsOf(String teacherId) async {
    try {
      final db = await _open();
      final rows = await db
          .query('claims', where: 'teacher_id = ?', whereArgs: [teacherId]);
      return [
        for (final r in rows)
          {
            'dept': (r['dept_id'] ?? '').toString(),
            'section': (r['section'] ?? '').toString(),
            'semester': (r['semester'] ?? '').toString(),
            'subject': (r['subject'] ?? '').toString(),
          }
      ];
    } catch (e) {
      debugPrint('LocalDb claimsOf error: $e');
      return [];
    }
  }

  // Quick refresh of one subject's attendance from the server (monthly view), so
  // records from other devices show too. Returns true only if fresh data was written.
  static Future<bool> refreshSubjectAttendance(SemRef s, String subject) async {
    try {
      if ((await _netState()) != _Net.reachable) return false;
      final snap =
          await s.dates(subject).get().timeout(const Duration(seconds: 10));
      if (snap.metadata.isFromCache) return false;
      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete('attendance',
            where: '$_semWhere AND subject = ?',
            whereArgs: [..._semArgs(s), subject]);
        await txn.delete('sessions',
            where: '$_semWhere AND subject = ?',
            whereArgs: [..._semArgs(s), subject]);
        final batch = txn.batch();
        for (final d in snap.docs) {
          final parsed = parseAttendance(d.data());
          if (parsed.status.isEmpty) continue;
          batch.insert(
            'sessions',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'subject': subject,
              'session_id': d.id,
              'marked_time': parsed.meta['_time'] ?? '',
              'marked_by': parsed.meta['_marked_by'] ?? '',
              'marked_by_name': parsed.meta['_marked_by_name'] ?? '',
              'session_type': parsed.meta['_type'] ?? kTypeClass,
              'exam_phase': parsed.meta['_phase'] ?? kPhaseMid,
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
          parsed.status.forEach((roll, st) {
            batch.insert(
              'attendance',
              {
                'dept_id': s.deptId,
                'section': s.section,
                'semester': s.semester,
                'subject': subject,
                'session_id': d.id,
                'roll': roll,
                'status': st,
              },
              conflictAlgorithm: sql.ConflictAlgorithm.replace,
            );
          });
        }
        await batch.commit(noResult: true);
      });
      return true;
    } catch (e) {
      debugPrint('LocalDb refreshSubjectAttendance error: $e');
      return false;
    }
  }

  // Re-reads one semester's students from the SERVER and replaces the SQLite rows,
  // so SQLite matches Firebase right after a change (father names included).
  static Future<bool> refreshSemesterStudents(SemRef s) async {
    try {
      if ((await _netState()) != _Net.reachable) return false;
      final snap = await s.students
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete('students',
            where: _semWhere, whereArgs: _semArgs(s));
        final batch = txn.batch();
        for (final d in snap.docs) {
          final sd = d.data();
          batch.insert(
            'students',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'roll': (sd['roll'] ?? d.id).toString(),
              'name': (sd['name'] ?? '').toString(),
              'father': (sd['father'] ?? '').toString(),
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
      return true;
    } catch (e) {
      debugPrint('LocalDb refreshSemesterStudents error: $e');
      return false;
    }
  }

  // Same for the subject-level student changes (overrides).
  static Future<bool> refreshSubjectOverrides(SemRef s, String subject) async {
    try {
      if ((await _netState()) != _Net.reachable) return false;
      final snap = await s
          .overrides(subject)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete('overrides',
            where: '$_semWhere AND subject = ?',
            whereArgs: [..._semArgs(s), subject]);
        final batch = txn.batch();
        for (final d in snap.docs) {
          final od = d.data();
          batch.insert(
            'overrides',
            {
              'dept_id': s.deptId,
              'section': s.section,
              'semester': s.semester,
              'subject': subject,
              'roll': (od['roll'] ?? d.id).toString(),
              'name': (od['name'] ?? '').toString(),
              'father': (od['father'] ?? '').toString(),
              'kind': (od['kind'] ?? '').toString(),
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
      return true;
    } catch (e) {
      debugPrint('LocalDb refreshSubjectOverrides error: $e');
      return false;
    }
  }

  static Future<void> deleteAllAttendance() {
    return _run((db) async {
      await db.delete('attendance');
      await db.delete('sessions');
    });
  }

  // ---------------- renames (keep SQLite in step with Firestore) ----------------
  static Future<void> renameSubject(SemRef s, String oldName, String newName) {
    return _run((db) async {
      await db.transaction((txn) async {
        final w = '$_semWhere AND subject = ?';
        final a = [..._semArgs(s), oldName];
        await txn.update('attendance', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('sessions', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('overrides', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('claims', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('subjects', {'name': newName},
            where: '$_semWhere AND name = ?', whereArgs: a);
      });
    });
  }

  static Future<void> renameStudentKey(
      SemRef s, String oldKey, String newKey, String name,
      [String father = '']) {
    return _run((db) async {
      await db.transaction((txn) async {
        final a = [..._semArgs(s), oldKey];
        await txn.delete('students',
            where: '$_semWhere AND roll = ?', whereArgs: a);
        await txn.insert(
          'students',
          {
            'dept_id': s.deptId,
            'section': s.section,
            'semester': s.semester,
            'roll': newKey,
            'name': name,
            'father': father,
          },
          conflictAlgorithm: sql.ConflictAlgorithm.replace,
        );
        await txn.update('attendance', {'roll': newKey},
            where: '$_semWhere AND roll = ?', whereArgs: a,
            conflictAlgorithm: sql.ConflictAlgorithm.replace);
        await txn.update('overrides', {'roll': newKey},
            where: '$_semWhere AND roll = ?', whereArgs: a,
            conflictAlgorithm: sql.ConflictAlgorithm.replace);
      });
    });
  }
}

// How old the SQLite copy may get before it is refreshed from Firestore.
// - Delta sync works (normal case): refresh every 2 hours. It only downloads the
//   attendance sessions that changed, so it is cheap.
// - Delta sync not available (Firestore index missing): every 6 hours, full copy.
// Every change made inside the app is written to SQLite at once, and structural
// changes (rename, restore, migration) call this with force: true.
const Duration kLocalDbDeltaAge = Duration(hours: 2);
const Duration kLocalDbMaxAge = Duration(hours: 6);
// A full rebuild at least once a day, because deletions made on other devices are
// invisible to a delta sync.
const Duration kLocalDbFullEvery = Duration(hours: 24);

Future<bool> _localDbIsFresh(SharedPreferences prefs) async {
  final last = prefs.getInt('sqlite_last_sync_ms') ?? 0;
  final age = DateTime.now().millisecondsSinceEpoch - last;
  final broken = prefs.getBool(LocalDb.kDeltaBroken) == true;
  return age < (broken ? kLocalDbMaxAge : kLocalDbDeltaAge).inMilliseconds;
}

// Refreshes SQLite from Firestore when it is out of date and right after coming
// back online. Normally a delta sync; a full rebuild when forced, when the last
// full rebuild is older than a day, or on the very first run.
Future<void> syncLocalDbIfStale({bool force = false}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!force && await _localDbIsFresh(prefs)) return;
    final lastFull = prefs.getInt('sqlite_last_full_ms') ?? 0;
    final fullDue = force ||
        DateTime.now().millisecondsSinceEpoch - lastFull >
            kLocalDbFullEvery.inMilliseconds;
    final ok = await LocalDb.replaceAllFromFirestore(full: fullDue);
    if (ok) {
      await prefs.setInt(
          'sqlite_last_sync_ms', DateTime.now().millisecondsSinceEpoch);
    }
  } catch (_) {}
}

// Login-time prefetch. The big collections (students, subjects, semesters,
// overrides, attendance) are already read once by syncLocalDbIfStale, and that
// read also fills Firestore's offline cache, so they are NOT read a second time
// here. Only the small documents are fetched, and the big sync runs only when due.
Future<void> prefetchAllData() async {
  try {
    if ((await _netState()) != _Net.reachable) return;
    const t = Duration(seconds: 20);
    final futures = <Future>[
      syncLocalDbIfStale(),
      permissionsRef().get().timeout(t),
      if (!AppSession.isAdmin && AppSession.teacherId.isNotEmpty)
        teacherClaimsRef(AppSession.teacherId).get().timeout(t),
    ];
    await Future.wait(futures.map((f) => f.catchError((_) => null)));
  } catch (_) {}
}
