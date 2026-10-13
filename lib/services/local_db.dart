part of '../main.dart';

// Local SQLite copy of the data, plus sync.

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
        'CREATE TABLE students (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, roll TEXT NOT NULL, name TEXT, PRIMARY KEY (dept_id, section, semester, roll))');
    await db.execute(
        'CREATE TABLE subjects (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, name TEXT NOT NULL, claimed_by TEXT, claimed_by_name TEXT, PRIMARY KEY (dept_id, section, semester, name))');
    await db.execute(
        'CREATE TABLE overrides (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, roll TEXT NOT NULL, name TEXT, kind TEXT, PRIMARY KEY (dept_id, section, semester, subject, roll))');
    await db.execute(
        'CREATE TABLE attendance (dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, session_id TEXT NOT NULL, roll TEXT NOT NULL, status TEXT, marked_time TEXT, marked_by TEXT, marked_by_name TEXT, session_type TEXT, PRIMARY KEY (dept_id, section, semester, subject, session_id, roll))');
    await db.execute(
        'CREATE TABLE teachers (teacher_id TEXT PRIMARY KEY, name TEXT, username TEXT)');
    await db.execute(
        'CREATE TABLE claims (teacher_id TEXT NOT NULL, dept_id TEXT NOT NULL, section TEXT NOT NULL, semester TEXT NOT NULL, subject TEXT NOT NULL, PRIMARY KEY (teacher_id, dept_id, section, semester, subject))');
  }

  static Future<sql.Database> _open() async {
    if (_db != null && _db!.isOpen) return _db!;
    final path = await filePath();
    _db = await sql.openDatabase(
      path,
      version: 3,
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
        for (final t in ['attendance', 'overrides', 'subjects', 'students', 'semesters']) {
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
  static Future<void> upsertStudent(SemRef s, String roll, String name) {
    return _run((db) async {
      await db.insert(
        'students',
        {
          'dept_id': s.deptId,
          'section': s.section,
          'semester': s.semester,
          'roll': roll,
          'name': name,
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
      SemRef s, String subject, String roll, String name, String kind) {
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
  static Future<void> saveAttendance(
    SemRef s,
    String subject,
    String sessionId,
    Map<String, String> status, {
    String? time,
    String? markedBy,
    String? markedByName,
    String sessionType = kTypeClass,
  }) {
    return _run((db) async {
      await db.transaction((txn) async {
        await txn.delete('attendance',
            where:
                'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
            whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
        final batch = txn.batch();
        status.forEach((roll, st) {
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
              'marked_time': time ?? '',
              'marked_by': markedBy ?? '',
              'marked_by_name': markedByName ?? '',
              'session_type': sessionType,
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
      await db.update('attendance', {'session_type': type},
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
    });
  }

  static Future<void> deleteAttendance(
      SemRef s, String subject, String sessionId) {
    return _run((db) async {
      await db.delete('attendance',
          where:
              'dept_id = ? AND section = ? AND semester = ? AND subject = ? AND session_id = ?',
          whereArgs: [s.deptId, s.section, s.semester, subject, sessionId]);
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
  static Future<bool> replaceAllFromFirestore() async {
    if (_syncing) return false;
    if (!await _isOnline()) return false;
    _syncing = true;
    try {
      const t = Duration(seconds: 30);
      final fs = FirebaseFirestore.instance;

      final depts = await fs.collection('departments').get().timeout(t);
      final semDocs = await fs.collectionGroup('semesters').get().timeout(t);
      final students = await fs.collectionGroup('students').get().timeout(t);
      final subjects = await fs.collectionGroup('subjects').get().timeout(t);
      final overrides = await fs.collectionGroup('overrides').get().timeout(t);
      final dates = await fs.collectionGroup('dates').get().timeout(t);
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
          'kind': (od['kind'] ?? '').toString(),
        });
      }

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
        final parsed = parseAttendance(d.data());
        parsed.status.forEach((roll, status) {
          attendanceRows.add({
            'dept_id': seg[1],
            'section': seg[3],
            'semester': seg[5],
            'subject': seg[7],
            'session_id': d.id,
            'roll': roll,
            'status': status,
            'marked_time': parsed.meta['_time'] ?? '',
            'marked_by': parsed.meta['_marked_by'] ?? '',
            'marked_by_name': parsed.meta['_marked_by_name'] ?? '',
            'session_type': parsed.meta['_type'] ?? kTypeClass,
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
          await txn.delete(table);
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
        addAll('attendance', attendanceRows);
        addAll('teachers', teacherRows);
        addAll('claims', claimRows);
        await batch.commit(noResult: true);
      });
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
      final rows = await db.query(
        'attendance',
        where:
            '$_semWhere AND subject = ?${monthPrefix == null ? '' : ' AND session_id LIKE ?'}',
        whereArgs: [
          ..._semArgs(s),
          subject,
          if (monthPrefix != null) '$monthPrefix-%',
        ],
        orderBy: 'session_id',
      );
      final byId = <String, DateRecord>{};
      for (final r in rows) {
        final id = (r['session_id'] ?? '').toString();
        final rec = byId.putIfAbsent(
            id, () => DateRecord(id, <String, String>{}, <String, String>{}));
        rec.status[(r['roll'] ?? '').toString()] =
            (r['status'] ?? '').toString();
        final t = (r['marked_time'] ?? '').toString();
        if (t.isNotEmpty) rec.meta['_time'] = t;
        final by = (r['marked_by'] ?? '').toString();
        if (by.isNotEmpty) rec.meta['_marked_by'] = by;
        final byName = (r['marked_by_name'] ?? '').toString();
        if (byName.isNotEmpty) rec.meta['_marked_by_name'] = byName;
        rec.meta['_type'] =
            (r['session_type'] ?? '').toString() == kTypeLab ? kTypeLab : kTypeClass;
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
        final batch = txn.batch();
        for (final d in snap.docs) {
          final parsed = parseAttendance(d.data());
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
                'marked_time': parsed.meta['_time'] ?? '',
                'marked_by': parsed.meta['_marked_by'] ?? '',
                'marked_by_name': parsed.meta['_marked_by_name'] ?? '',
                'session_type': parsed.meta['_type'] ?? kTypeClass,
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

  static Future<void> deleteAllAttendance() {
    return _run((db) async {
      await db.delete('attendance');
    });
  }

  // ---------------- renames (keep SQLite in step with Firestore) ----------------
  static Future<void> renameSubject(SemRef s, String oldName, String newName) {
    return _run((db) async {
      await db.transaction((txn) async {
        final w = '$_semWhere AND subject = ?';
        final a = [..._semArgs(s), oldName];
        await txn.update('attendance', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('overrides', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('claims', {'subject': newName}, where: w, whereArgs: a);
        await txn.update('subjects', {'name': newName},
            where: '$_semWhere AND name = ?', whereArgs: a);
      });
    });
  }

  static Future<void> renameStudentKey(
      SemRef s, String oldKey, String newKey, String name) {
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

// Refreshes SQLite from Firestore every few hours and right after coming back online.
Future<void> syncLocalDbIfStale({bool force = false}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('sqlite_last_sync_ms') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - last;
    if (!force && age < const Duration(hours: 1).inMilliseconds) return;
    final ok = await LocalDb.replaceAllFromFirestore();
    if (ok) {
      await prefs.setInt(
          'sqlite_last_sync_ms', DateTime.now().millisecondsSinceEpoch);
    }
  } catch (_) {}
}

// Login-time prefetch: one query each for students, subjects, semesters and
// attendance, so lists and attendance also show offline.
Future<void> prefetchAllData() async {
  try {
    if ((await _netState()) != _Net.reachable) return;
    final fs = FirebaseFirestore.instance;
    const t = Duration(seconds: 20);
    final futures = <Future>[
      fs.collection('departments').get().timeout(t),
      fs.collectionGroup('semesters').get().timeout(t),
      fs.collectionGroup('students').get().timeout(t),
      fs.collectionGroup('subjects').get().timeout(t),
      fs.collectionGroup('overrides').get().timeout(t),
      fs.collectionGroup('dates').get().timeout(t),
      permissionsRef().get().timeout(t),
      if (!AppSession.isAdmin && AppSession.teacherId.isNotEmpty)
        teacherClaimsRef(AppSession.teacherId).get().timeout(t),
    ];
    await Future.wait(futures.map((f) => f.catchError((_) => null)));
  } catch (_) {}
}
