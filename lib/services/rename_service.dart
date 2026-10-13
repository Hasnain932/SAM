part of '../main.dart';

// Rename and delete things safely (admin).

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
      (b) => b.set(sem.dates(newName).doc(d.id), d.data()),
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
}

// Changes a student's roll number. Returns the new internal key.
Future<String> changeStudentRoll(
    SemRef sem, String oldKey, String newRollRaw, String name) async {
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
  ops.add((b) => b.set(sem.students.doc(newKey), {'roll': newKey, 'name': name}));
  ops.add((b) => b.delete(sem.students.doc(oldKey)));

  // Attendance moves come first and the student record last. If something fails
  // halfway, just try again: the retry finishes the remaining moves.
  await _commitInChunks(ops);

  await LocalDb.renameStudentKey(sem, oldKey, newKey, name);
  unawaited(syncLocalDbIfStale(force: true));
  return newKey;
}

// Deletes a whole department (all sections, semesters and old data).
Future<void> deleteDepartmentEverywhere(String deptId) async {
  unawaited(FirebaseFirestore.instance
      .collection('meta')
      .doc('seed')
      .set({'done': true}, SetOptions(merge: true)).catchError((_) {}));

  for (final sec in kSections) {
    for (final sid in kSemesterIds) {
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
  await LocalDb.deleteAllAttendance();
}
